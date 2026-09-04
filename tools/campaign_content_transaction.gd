class_name CampaignContentTransaction
extends RefCounted
## Write-ahead transaction for an ordered set of Godot Resources.
##
## The durable transaction directory contains validated staging payloads,
## byte-exact backups, a manifest and an append-only state journal. A later
## invocation rolls every prepared/committing transaction back before it starts
## new work. Commit promotes the staged bytes; it never serializes a second time
## directly over an official target.

const STAGING_PARENT := "user://qix-campaign-content-staging"
const MANIFEST_NAME := "manifest.json"
const JOURNAL_NAME := "journal.jsonl"
const SCHEMA := "qix.campaign-content-transaction.v3"
const WAL_SCHEMA := "qix.campaign-content-wal.v1"
const LOCK_SCHEMA := "qix.campaign-content-lock.v1"
const LOCK_DIRECTORY_NAME := ".txn_active.lock"
const LOCK_OWNER_NAME := "owner.json"
const LOCK_PORT_BASE := 42000
const LOCK_PORT_SPAN := 20000

## Deterministic failure seams used by rollback/recovery tests.
var fail_after_commits: int = -1
var interrupt_after_commits: int = -1
var rollback_performed: bool = false
var interruption_simulated: bool = false
var last_stage_path: String = ""
var staged_count: int = 0
var committed_count: int = 0
var promoted_from_stage_count: int = 0
var recovered_transaction_count: int = 0
var stale_lock_recovered: bool = false

var _transaction_id := ""
var _resource_state: Array = []
var _lock_server: TCPServer
var _lock_token := ""
var _lock_port := -1
var _prepared_manifest_sha256 := ""


func execute(entries: Array) -> PackedStringArray:
	_reset_run_state()
	var acquired_here := _lock_server == null
	var errors := PackedStringArray()
	if acquired_here:
		errors = acquire_exclusive_lock()
	if not errors.is_empty():
		return errors
	errors = _execute_locked(entries)
	if acquired_here:
		var release_errors := release_exclusive_lock()
		for release_error in release_errors:
			errors.append(release_error)
	return errors


func _execute_locked(entries: Array) -> PackedStringArray:
	var errors := _lock_ownership_errors()
	if not errors.is_empty():
		return errors
	errors = _recover_incomplete_transactions_locked()
	if not errors.is_empty():
		return errors
	errors = _validate_entries(entries)
	if not errors.is_empty():
		return errors

	# A single stable slot keeps ResourceSaver's generated text identifiers
	# deterministic across runs. Recovery above guarantees an abandoned slot is
	# resolved before it can be reused.
	_transaction_id = "txn_active"
	last_stage_path = STAGING_PARENT.path_join(_transaction_id)
	var make_stage_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(last_stage_path),
	)
	if make_stage_error != OK:
		errors.append("não criou staging: %s" % error_string(make_stage_error))
		return errors

	_resource_state = _capture_resource_state(entries)
	var manifest := _snapshot_targets(entries, errors)
	if not errors.is_empty():
		_restore_resource_cache(entries)
		_cleanup_stage()
		return errors

	_bind_resources_to_targets(entries)
	_stage(entries, manifest, errors)
	if errors.is_empty():
		var manifest_error := _write_manifest(manifest)
		if manifest_error != OK:
			errors.append("não persistiu manifest: %s" % error_string(manifest_error))
	if errors.is_empty():
		_prepared_manifest_sha256 = _canonical_manifest_sha256(manifest)
		if _prepared_manifest_sha256.is_empty():
			errors.append("não calculou manifest_sha256 canônico")
	if errors.is_empty():
		var journal_error := _append_journal("prepared")
		if journal_error != OK:
			errors.append("não persistiu journal preparado: %s" % error_string(journal_error))
	if not errors.is_empty():
		_restore_resource_cache(entries)
		_cleanup_stage()
		return errors
	var authorization_errors := _validate_manifest_authorization(manifest)
	if not authorization_errors.is_empty():
		for authorization_error in authorization_errors:
			errors.append("prepared recusado antes do commit: %s" % authorization_error)
		_restore_resource_cache(entries)
		return errors

	var committing_error := _append_journal("committing")
	if committing_error != OK:
		errors.append("não persistiu início do commit: %s" % error_string(committing_error))
	else:
		_commit_from_stage(manifest, errors)

	if interruption_simulated:
		# Models an abrupt process death: a fresh instance must recover from disk.
		return errors

	if not errors.is_empty():
		_rollback_manifest(manifest, errors)
		_restore_resource_cache(entries)
		if rollback_performed:
			_cleanup_stage()
		return errors

	var committed_error := _append_journal("committed")
	if committed_error != OK:
		errors.append("commit aplicado, mas journal final falhou: %s" % error_string(committed_error))
		_rollback_manifest(manifest, errors)
		_restore_resource_cache(entries)
		if rollback_performed:
			_cleanup_stage()
		return errors

	_cleanup_stage()
	return errors


## Recover durable transactions abandoned by a killed generator. A committed
## transaction only needs staging cleanup; every earlier state is rolled back.
func recover_incomplete_transactions() -> PackedStringArray:
	var acquired_here := _lock_server == null
	var errors := PackedStringArray()
	if acquired_here:
		errors = acquire_exclusive_lock()
	if not errors.is_empty():
		return errors
	errors = _lock_ownership_errors()
	if errors.is_empty():
		errors = _recover_incomplete_transactions_locked()
	if acquired_here:
		var release_errors := release_exclusive_lock()
		for release_error in release_errors:
			errors.append(release_error)
	return errors


func _recover_incomplete_transactions_locked() -> PackedStringArray:
	var errors := PackedStringArray()
	var parent_absolute := ProjectSettings.globalize_path(STAGING_PARENT)
	if not DirAccess.dir_exists_absolute(parent_absolute):
		return errors
	var directory := DirAccess.open(parent_absolute)
	if directory == null:
		errors.append("não abriu staging parent para recovery")
		return errors
	var names := Array(directory.get_directories())
	names.sort()
	for name_variant in names:
		var name := String(name_variant)
		if not name.begins_with("txn_"):
			continue
		last_stage_path = STAGING_PARENT.path_join(name)
		_transaction_id = name
		var manifest := _read_manifest(last_stage_path)
		if manifest.is_empty():
			if FileAccess.file_exists(last_stage_path.path_join(MANIFEST_NAME)):
				# A present but unreadable/non-Dictionary manifest may belong to a
				# partially committed transaction. Never destroy its backups.
				errors.append("recovery %s: manifest presente, mas inválido; staging preservado" % name)
			else:
				# Manifest is persisted before committing, so an absent manifest
				# never granted authority to mutate live targets.
				_cleanup_stage()
			continue
		var validation := _validate_manifest(manifest)
		var manifest_entries: Array = manifest.get("entries", []) if manifest.get("entries") is Array else []
		var wal := _validate_wal(manifest, manifest_entries.size())
		for wal_error in wal.errors:
			validation.append(wal_error)
		if not validation.is_empty():
			for validation_error in validation:
				errors.append("recovery %s: %s" % [name, validation_error])
			continue
		var state := String(wal.state)
		committed_count = int(wal.committed_count)
		_prepared_manifest_sha256 = String(wal.manifest_sha256)
		if state == "committed" or state == "rolled_back":
			var terminal_errors := _validate_terminal_target_state(manifest, state)
			if not terminal_errors.is_empty():
				for terminal_error in terminal_errors:
					errors.append("recovery %s: %s" % [name, terminal_error])
				continue
			_cleanup_stage()
			continue
		var rollback_errors := PackedStringArray()
		_rollback_manifest(manifest, rollback_errors)
		if rollback_errors.is_empty():
			recovered_transaction_count += 1
			_cleanup_stage()
		else:
			for rollback_error in rollback_errors:
				errors.append("recovery %s: %s" % [name, rollback_error])
	return errors


func _reset_run_state() -> void:
	rollback_performed = false
	interruption_simulated = false
	staged_count = 0
	committed_count = 0
	promoted_from_stage_count = 0
	recovered_transaction_count = 0
	stale_lock_recovered = false
	last_stage_path = ""
	_transaction_id = ""
	_resource_state.clear()
	_prepared_manifest_sha256 = ""


## Acquires the project-scoped generator lock without a clock-based lease.
##
## The TCP listener is the authoritative interprocess guard: the kernel keeps
## the port exclusive while this process is alive and releases it on crash.
## The lock directory is diagnostic metadata only. It may be reaped as stale
## *only after* this process has successfully bound the guard port, which proves
## that no cooperating generator still owns the slot. A port collision with an
## unrelated program therefore fails closed instead of deleting staging.
func acquire_exclusive_lock() -> PackedStringArray:
	var errors := PackedStringArray()
	if _lock_server != null:
		errors = _lock_ownership_errors()
		return errors
	var parent_absolute := ProjectSettings.globalize_path(STAGING_PARENT)
	var parent_error := DirAccess.make_dir_recursive_absolute(parent_absolute)
	if parent_error != OK:
		errors.append("não criou staging parent para lock: %s" % error_string(parent_error))
		return errors

	var server := TCPServer.new()
	var port := _project_lock_port()
	var listen_error := server.listen(port, "127.0.0.1")
	if listen_error != OK:
		var owner_summary := _existing_lock_owner_summary()
		errors.append(
			(
				"lock exclusivo ocupado ou porta indisponível em 127.0.0.1:%d%s; "
				+ "nenhum staging foi recuperado ou removido"
			) % [port, owner_summary],
		)
		return errors

	# From this point until server.stop(), no second cooperating process can
	# enter recovery. A leftover directory therefore belongs to a crashed owner.
	var lock_path := _lock_directory_path()
	var lock_absolute := ProjectSettings.globalize_path(lock_path)
	if DirAccess.dir_exists_absolute(lock_absolute):
		_remove_tree(lock_absolute)
		if DirAccess.dir_exists_absolute(lock_absolute):
			server.stop()
			errors.append("guardião adquirido, mas lock stale não pôde ser preservadamente removido")
			return errors
		stale_lock_recovered = true
	var directory_error := DirAccess.make_dir_absolute(lock_absolute)
	if directory_error != OK:
		server.stop()
		errors.append("não criou metadado do lock exclusivo: %s" % error_string(directory_error))
		return errors

	var entropy := "%s:%s:%s:%s" % [
		ProjectSettings.globalize_path("res://"),
		OS.get_process_id(),
		Time.get_ticks_usec(),
		Time.get_unix_time_from_system(),
	]
	var token := entropy.sha256_text()
	var owner := {
		"schema": LOCK_SCHEMA,
		"token": token,
		"pid": OS.get_process_id(),
		"port": port,
		"project_root": ProjectSettings.globalize_path("res://").simplify_path(),
		"acquired_unix_time": int(Time.get_unix_time_from_system()),
	}
	var owner_error := _write_text(lock_path.path_join(LOCK_OWNER_NAME), JSON.stringify(owner, "  ") + "\n")
	if owner_error != OK:
		_remove_tree(lock_absolute)
		server.stop()
		errors.append("não persistiu metadado do lock exclusivo: %s" % error_string(owner_error))
		return errors

	_lock_server = server
	_lock_token = token
	_lock_port = port
	return errors


## Releases only metadata carrying this instance's token. If metadata was
## tampered while held, it is preserved for diagnosis and release fails closed;
## the kernel guard is still stopped so a later process can safely classify it
## as stale after binding the same port.
func release_exclusive_lock() -> PackedStringArray:
	var errors := PackedStringArray()
	if _lock_server == null:
		return errors
	var ownership_errors := _lock_ownership_errors()
	if ownership_errors.is_empty():
		var lock_absolute := ProjectSettings.globalize_path(_lock_directory_path())
		_remove_tree(lock_absolute)
		if DirAccess.dir_exists_absolute(lock_absolute):
			errors.append("não removeu metadado do lock exclusivo")
	else:
		for ownership_error in ownership_errors:
			errors.append("release recusou metadado divergente: %s" % ownership_error)
	_lock_server.stop()
	_lock_server = null
	_lock_token = ""
	_lock_port = -1
	return errors


func _lock_ownership_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if _lock_server == null or not _lock_server.is_listening():
		errors.append("guardião do lock exclusivo não está ativo")
		return errors
	var owner_path := _lock_directory_path().path_join(LOCK_OWNER_NAME)
	if not FileAccess.file_exists(owner_path):
		errors.append("metadado do lock exclusivo ausente")
		return errors
	var parsed: Variant = _parse_json(FileAccess.get_file_as_string(owner_path))
	if not (parsed is Dictionary):
		errors.append("metadado do lock exclusivo não é JSON Dictionary")
		return errors
	var owner: Dictionary = parsed
	if typeof(owner.get("schema")) != TYPE_STRING or String(owner.schema) != LOCK_SCHEMA:
		errors.append("schema do lock exclusivo inválido")
	if typeof(owner.get("token")) != TYPE_STRING or String(owner.token) != _lock_token:
		errors.append("token do lock exclusivo não pertence a esta instância")
	if typeof(owner.get("port")) != TYPE_FLOAT and typeof(owner.get("port")) != TYPE_INT:
		errors.append("porta do lock exclusivo inválida")
	elif int(owner.port) != _lock_port:
		errors.append("porta do lock exclusivo divergente")
	return errors


func _project_lock_port() -> int:
	# Derive from the guarded user:// slot, not res://: opening the same checkout
	# through a symlink must not yield a second port for the same staging data.
	var guarded_parent := ProjectSettings.globalize_path(STAGING_PARENT).simplify_path()
	return LOCK_PORT_BASE + (int(guarded_parent.hash()) & 0x7fffffff) % LOCK_PORT_SPAN


func _lock_directory_path() -> String:
	return STAGING_PARENT.path_join(LOCK_DIRECTORY_NAME)


func _existing_lock_owner_summary() -> String:
	var owner_path := _lock_directory_path().path_join(LOCK_OWNER_NAME)
	if not FileAccess.file_exists(owner_path):
		return ""
	var parsed: Variant = _parse_json(FileAccess.get_file_as_string(owner_path))
	if not (parsed is Dictionary):
		return " (metadado presente e inválido)"
	var owner: Dictionary = parsed
	return " (owner pid=%s, desde=%s)" % [
		str(owner.get("pid", "?")),
		str(owner.get("acquired_unix_time", "?")),
	]


func _validate_entries(entries: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	if entries.is_empty():
		errors.append("transação sem Resources")
		return errors
	var seen := {}
	for index in entries.size():
		var entry = entries[index]
		if not (entry is Dictionary):
			errors.append("entrada %d não é Dictionary" % index)
			continue
		var path := String(entry.get("path", ""))
		var path_error := _target_path_error(path)
		if not path_error.is_empty():
			errors.append("entrada %d: %s" % [index, path_error])
		elif seen.has(path):
			errors.append("destino duplicado: %s" % path)
		else:
			seen[path] = true
		if not (entry.get("resource") is Resource):
			errors.append("entrada %d sem Resource" % index)
	return errors


func _target_path_error(path: String) -> String:
	var prefix := ""
	if path.begins_with("res://"):
		prefix = "res://"
	elif path.begins_with("user://"):
		prefix = "user://"
	else:
		return "destino fora de res:// ou user://: %s" % path
	var relative := path.trim_prefix(prefix)
	if relative.is_empty() or relative.begins_with("/") or relative.contains("\\"):
		return "destino não canônico: %s" % path
	for component in relative.split("/", true):
		if component.is_empty() or component == "." or component == "..":
			return "destino contém traversal ou segmento inválido: %s" % path
	var extension := path.get_extension().to_lower()
	if extension != "tres" and extension != "res":
		return "destino de Resource precisa usar .tres ou .res: %s" % path
	var root_absolute := ProjectSettings.globalize_path(prefix).simplify_path().trim_suffix("/")
	var target_absolute := ProjectSettings.globalize_path(path).simplify_path()
	if not target_absolute.begins_with(root_absolute + "/"):
		return "destino escapou da raiz %s: %s" % [prefix, path]
	return ""


func _capture_resource_state(entries: Array) -> Array:
	var state: Array = []
	for entry in entries:
		var path := String(entry.path)
		var resource := entry.resource as Resource
		state.append({
			"resource": resource,
			"original_path": resource.resource_path,
			"cached": ResourceLoader.get_cached_ref(path),
			"target": path,
		})
	return state


func _bind_resources_to_targets(entries: Array) -> void:
	# Pre-bind the graph so parents point at canonical child paths in payloads.
	for entry in entries:
		(entry.resource as Resource).take_over_path(String(entry.path))


func _restore_resource_cache(entries: Array) -> void:
	for index in entries.size():
		var state: Dictionary = _resource_state[index]
		var resource := state.resource as Resource
		resource.resource_path = ""
		var cached := state.cached as Resource
		if cached != null and cached != resource:
			cached.take_over_path(String(state.target))
		var original_path := String(state.original_path)
		if not original_path.is_empty():
			resource.take_over_path(original_path)
	_resource_state.clear()


func _snapshot_targets(entries: Array, errors: PackedStringArray) -> Dictionary:
	var manifest_entries: Array = []
	var backup_dir := last_stage_path.path_join("backup")
	var payload_dir := last_stage_path.path_join("payload")
	var validation_dir := last_stage_path.path_join("validation")
	for directory in [backup_dir, payload_dir, validation_dir]:
		var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		if directory_error != OK:
			errors.append("não criou diretório transacional %s: %s" % [directory, error_string(directory_error)])
			return {}
	for index in entries.size():
		var target := String(entries[index].path)
		var existed := FileAccess.file_exists(target)
		var backup_path := backup_dir.path_join("%03d.bin" % index)
		var backup_size := 0
		var backup_sha256 := ""
		if existed:
			var bytes := FileAccess.get_file_as_bytes(target)
			var open_error := FileAccess.get_open_error()
			if open_error != OK:
				errors.append("não leu backup de %s: %s" % [target, error_string(open_error)])
				return {}
			var backup_error := _write_bytes(backup_path, bytes)
			if backup_error != OK or FileAccess.get_file_as_bytes(backup_path) != bytes:
				errors.append("não persistiu backup byte a byte de %s" % target)
				return {}
			backup_size = bytes.size()
			backup_sha256 = _sha256_bytes(bytes)
		manifest_entries.append({
			"target": target,
			"existed": existed,
			"backup": backup_path if existed else "",
			"backup_size": backup_size,
			"backup_sha256": backup_sha256,
			"payload": payload_dir.path_join("%03d_%s" % [index, target.get_file()]),
			"payload_size": 0,
			"payload_sha256": "",
			"next": target + ".qix-next-" + _transaction_id,
			"old": target + ".qix-old-" + _transaction_id,
		})
	return {
		"schema": SCHEMA,
		"transaction_id": _transaction_id,
		"entries": manifest_entries,
	}


func _stage(entries: Array, manifest: Dictionary, errors: PackedStringArray) -> void:
	var manifest_entries: Array = manifest.get("entries", [])
	# First serialize the exact bytes that will later be promoted.
	for index in entries.size():
		var resource := entries[index].resource as Resource
		var payload_path := String(manifest_entries[index].payload)
		var payload_error := ResourceSaver.save(resource, payload_path)
		if payload_error != OK:
			errors.append("staging payload falhou para %s: %s" % [entries[index].path, error_string(payload_error)])
			return
		var payload_bytes := FileAccess.get_file_as_bytes(payload_path)
		var payload_read_error := FileAccess.get_open_error()
		if payload_read_error != OK:
			errors.append("não releu staging payload %s: %s" % [payload_path, error_string(payload_read_error)])
			return
		if payload_bytes.is_empty():
			errors.append("staging payload vazio: %s" % payload_path)
			return
		var record: Dictionary = manifest_entries[index]
		record["payload_size"] = payload_bytes.size()
		record["payload_sha256"] = _sha256_bytes(payload_bytes)
		manifest_entries[index] = record
	manifest["entries"] = manifest_entries

	# Then build a shadow graph entirely inside staging. For text Resources the
	# only difference from the promotable bytes is dependency path remapping.
	# This validates a brand-new interconnected campaign without touching live
	# destinations and without bundling global class scripts as subresources.
	var validation_paths := {}
	for index in entries.size():
		var target := String(entries[index].path)
		validation_paths[target] = last_stage_path.path_join(
			"validation/%03d_%s" % [index, target.get_file()],
		)
	for index in entries.size():
		var payload_path := String(manifest_entries[index].payload)
		var validation_path := String(validation_paths[String(entries[index].path)])
		if payload_path.get_extension().to_lower() == "tres":
			var payload_text := FileAccess.get_file_as_string(payload_path)
			if FileAccess.get_open_error() != OK:
				errors.append("não leu payload para validação: %s" % payload_path)
				return
			for target_variant in validation_paths:
				var target := String(target_variant)
				payload_text = payload_text.replace(
					"path=\"%s\"" % target,
					"path=\"%s\"" % String(validation_paths[target]),
				)
			var validation_write_error := _write_text(validation_path, payload_text)
			if validation_write_error != OK:
				errors.append("não escreveu shadow staging: %s" % error_string(validation_write_error))
				return
		else:
			var copy_error := DirAccess.copy_absolute(
				ProjectSettings.globalize_path(payload_path),
				ProjectSettings.globalize_path(validation_path),
			)
			if copy_error != OK:
				errors.append("não copiou payload binário para validação: %s" % error_string(copy_error))
				return
		var reloaded := ResourceLoader.load(validation_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if reloaded == null:
			errors.append("staging não recarregou: %s" % validation_path)
			return
		staged_count += 1


func _write_manifest(manifest: Dictionary) -> Error:
	var path := last_stage_path.path_join(MANIFEST_NAME)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.flush()
	file.close()
	return OK


func _append_journal(state: String) -> Error:
	var path := last_stage_path.path_join(JOURNAL_NAME)
	if not _is_sha256_text(_prepared_manifest_sha256):
		return ERR_INVALID_DATA
	var record := {
		"schema": WAL_SCHEMA,
		"state": state,
		"transaction_id": _transaction_id,
		"manifest_sha256": _prepared_manifest_sha256,
		"committed_count": committed_count,
		"unix_time": int(Time.get_unix_time_from_system()),
	}
	var file: FileAccess
	if FileAccess.file_exists(path):
		file = FileAccess.open(path, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(path, FileAccess.WRITE_READ)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(record) + "\n")
	file.flush()
	file.close()
	return OK


func _commit_from_stage(manifest: Dictionary, errors: PackedStringArray) -> void:
	for record_variant in manifest.entries:
		var record: Dictionary = record_variant
		if interrupt_after_commits >= 0 and committed_count >= interrupt_after_commits:
			interruption_simulated = true
			errors.append("interrupção simulada após %d arquivo(s)" % committed_count)
			return
		if fail_after_commits >= 0 and committed_count >= fail_after_commits:
			errors.append("falha de commit injetada após %d arquivo(s)" % committed_count)
			return
		var promotion_error := _promote_payload(record)
		if promotion_error != OK:
			errors.append("commit falhou para %s: %s" % [record.target, error_string(promotion_error)])
			return
		committed_count += 1
		promoted_from_stage_count += 1
		var journal_error := _append_journal("committing")
		if journal_error != OK:
			errors.append("não persistiu progresso do commit: %s" % error_string(journal_error))
			return


func _promote_payload(record: Dictionary) -> Error:
	var target := String(record.target)
	var next_path := String(record.next)
	var old_path := String(record.old)
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	if directory_error != OK:
		return directory_error
	_remove_file_if_present(next_path)
	_remove_file_if_present(old_path)
	var copy_error := DirAccess.copy_absolute(
		ProjectSettings.globalize_path(String(record.payload)),
		ProjectSettings.globalize_path(next_path),
	)
	if copy_error != OK:
		return copy_error
	if FileAccess.file_exists(target):
		var move_old_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(target),
			ProjectSettings.globalize_path(old_path),
		)
		if move_old_error != OK:
			_remove_file_if_present(next_path)
			return move_old_error
	var promote_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(next_path),
		ProjectSettings.globalize_path(target),
	)
	if promote_error != OK:
		if FileAccess.file_exists(old_path):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(old_path), ProjectSettings.globalize_path(target))
		_remove_file_if_present(next_path)
		return promote_error
	_remove_file_if_present(old_path)
	return OK


func _rollback_manifest(manifest: Dictionary, errors: PackedStringArray) -> void:
	var validation_errors := _validate_manifest_authorization(manifest)
	if not validation_errors.is_empty():
		for validation_error in validation_errors:
			errors.append("rollback recusado antes de mutar arquivos: %s" % validation_error)
		return
	var rollback_errors := PackedStringArray()
	var records: Array = (manifest.get("entries", []) as Array).duplicate(true)
	records.reverse()
	for record_variant in records:
		var record: Dictionary = record_variant
		_remove_file_if_present(String(record.get("next", "")))
		_remove_file_if_present(String(record.get("old", "")))
		var target := String(record.target)
		if record.existed:
			var backup_path := String(record.backup)
			var bytes := FileAccess.get_file_as_bytes(backup_path)
			var read_error := FileAccess.get_open_error()
			if read_error != OK:
				rollback_errors.append("rollback não leu backup de %s: %s" % [target, error_string(read_error)])
				continue
			var restore_error := _replace_with_bytes(target, bytes)
			if restore_error != OK:
				rollback_errors.append("rollback não restaurou %s: %s" % [target, error_string(restore_error)])
		elif FileAccess.file_exists(target):
			var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
			if remove_error != OK:
				rollback_errors.append("rollback não removeu %s: %s" % [target, error_string(remove_error)])
	if rollback_errors.is_empty():
		rollback_performed = true
		var journal_error := _append_journal("rolled_back")
		if journal_error != OK:
			rollback_performed = false
			rollback_errors.append("rollback aplicado, mas journal falhou: %s" % error_string(journal_error))
	for rollback_error in rollback_errors:
		errors.append(rollback_error)


func _replace_with_bytes(target: String, bytes: PackedByteArray) -> Error:
	var rollback_next := target + ".qix-rollback-" + _transaction_id
	var rollback_old := target + ".qix-rollback-old-" + _transaction_id
	_remove_file_if_present(rollback_next)
	_remove_file_if_present(rollback_old)
	var write_error := _write_bytes(rollback_next, bytes)
	if write_error != OK:
		return write_error
	if FileAccess.file_exists(target):
		var move_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(target),
			ProjectSettings.globalize_path(rollback_old),
		)
		if move_error != OK:
			_remove_file_if_present(rollback_next)
			return move_error
	var replace_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(rollback_next),
		ProjectSettings.globalize_path(target),
	)
	if replace_error != OK:
		if FileAccess.file_exists(rollback_old):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(rollback_old), ProjectSettings.globalize_path(target))
		_remove_file_if_present(rollback_next)
		return replace_error
	_remove_file_if_present(rollback_old)
	return OK


func _validate_manifest_authorization(manifest: Dictionary) -> PackedStringArray:
	var errors := _validate_manifest(manifest)
	var entries_value: Variant = manifest.get("entries")
	var entry_count: int = entries_value.size() if entries_value is Array else 0
	var wal := _validate_wal(manifest, entry_count)
	for wal_error in wal.errors:
		errors.append(wal_error)
	return errors


## Parses and validates every WAL record before any state is trusted. Each line
## repeats the immutable manifest hash, schema and transaction id. The sequence
## is a strict state machine rather than a "last JSON wins" log reader.
func _validate_wal(manifest: Dictionary, entry_count: int) -> Dictionary:
	var errors := PackedStringArray()
	var result := {
		"errors": errors,
		"state": "",
		"committed_count": 0,
		"manifest_sha256": "",
	}
	var journal_path := last_stage_path.path_join(JOURNAL_NAME)
	if not FileAccess.file_exists(journal_path):
		errors.append("WAL ausente")
		result.errors = errors
		return result
	var file := FileAccess.open(journal_path, FileAccess.READ)
	if file == null:
		errors.append("não abriu WAL para validação")
		result.errors = errors
		return result
	var actual_manifest_sha256 := _canonical_manifest_sha256(manifest)
	var records: Array[Dictionary] = []
	var line_number := 0
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		line_number += 1
		var parsed: Variant = _parse_json(line)
		if not (parsed is Dictionary):
			errors.append("WAL record %d contém JSON inválido ou truncado" % line_number)
			continue
		var record: Dictionary = parsed
		var errors_before := errors.size()
		var allowed_fields := {
			"schema": true,
			"state": true,
			"transaction_id": true,
			"manifest_sha256": true,
			"committed_count": true,
			"unix_time": true,
		}
		for key_variant in record.keys():
			var key := String(key_variant)
			if not allowed_fields.has(key):
				errors.append("WAL record %d contém campo extra: %s" % [line_number, key])
		if typeof(record.get("schema")) != TYPE_STRING or String(record.get("schema", "")) != WAL_SCHEMA:
			errors.append("WAL record %d schema inválido" % line_number)
		if typeof(record.get("state")) != TYPE_STRING:
			errors.append("WAL record %d state precisa ser String" % line_number)
		if typeof(record.get("transaction_id")) != TYPE_STRING \
				or String(record.get("transaction_id", "")) != _transaction_id:
			errors.append("WAL record %d transaction_id divergente" % line_number)
		if typeof(record.get("manifest_sha256")) != TYPE_STRING \
				or not _is_sha256_text(String(record.get("manifest_sha256", ""))):
			errors.append("WAL record %d manifest_sha256 inválido" % line_number)
		elif String(record.manifest_sha256) != actual_manifest_sha256:
			errors.append("WAL record %d manifest_sha256 divergente" % line_number)
		var count := _wal_nonnegative_integer(
			record.get("committed_count"), "committed_count", line_number, errors,
		)
		if count > entry_count:
			errors.append(
				"WAL record %d committed_count fora do intervalo 0..%d: %d"
				% [line_number, entry_count, count],
			)
		_wal_nonnegative_integer(record.get("unix_time"), "unix_time", line_number, errors)
		if errors.size() != errors_before:
			continue
		var state := String(record.state)
		if state not in ["prepared", "committing", "committed", "rolled_back"]:
			errors.append("WAL record %d state desconhecido: %s" % [line_number, state])
			continue
		records.append({"state": state, "count": count, "line": line_number})
	file.close()

	var phase := "start"
	var progress := 0
	var prepared_count := 0
	var terminal_seen := false
	for record in records:
		var state := String(record.state)
		var count := int(record.count)
		var line := int(record.line)
		if terminal_seen:
			errors.append("WAL record %d aparece após terminal" % line)
			continue
		match state:
			"prepared":
				prepared_count += 1
				if phase != "start" or count != 0:
					errors.append("WAL prepared desordenado; precisa ser único e count=0")
				phase = "prepared"
				progress = 0
			"committing":
				if phase == "prepared":
					if count != 0:
						errors.append("WAL início committing precisa ter count=0")
					phase = "committing"
					progress = count
				elif phase == "committing":
					if count != progress + 1:
						errors.append(
							"WAL committing regressivo, repetido ou não monotônico: %d após %d"
							% [count, progress],
						)
					progress = count
				else:
					errors.append("WAL committing desordenado antes de prepared")
			"committed":
				if phase != "committing" or count != entry_count or progress != entry_count:
					errors.append(
						"WAL terminal committed prematuro: count=%d, progresso=%d, entries=%d"
						% [count, progress, entry_count],
					)
				terminal_seen = true
				phase = "committed"
			"rolled_back":
				var coherent := (phase == "prepared" and count == 0) \
					or (phase == "committing" and count == progress)
				if not coherent:
					errors.append("WAL terminal rolled_back com sequência ou count incoerente")
				terminal_seen = true
				phase = "rolled_back"
		result.state = state
		result.committed_count = count
	if prepared_count != 1:
		errors.append("WAL precisa conter prepared exatamente uma vez; encontrou %d" % prepared_count)
	if records.is_empty():
		errors.append("WAL sem records válidos")
	result.manifest_sha256 = actual_manifest_sha256
	result.errors = errors
	return result


func _wal_nonnegative_integer(
	value: Variant,
	field: String,
	line_number: int,
	errors: PackedStringArray,
) -> int:
	var parsed := -1
	if typeof(value) == TYPE_INT:
		parsed = int(value)
	elif typeof(value) == TYPE_FLOAT and is_finite(float(value)) \
			and float(value) == floor(float(value)):
		parsed = int(value)
	else:
		errors.append("WAL record %d %s precisa ser inteiro JSON" % [line_number, field])
		return -1
	if parsed < 0:
		errors.append("WAL record %d %s não pode ser negativo" % [line_number, field])
	return parsed


func _validate_manifest(manifest: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if typeof(manifest.get("schema")) != TYPE_STRING or String(manifest.get("schema", "")) != SCHEMA:
		errors.append("schema de manifest inválido")
	if typeof(manifest.get("transaction_id")) != TYPE_STRING:
		errors.append("transaction_id de manifest precisa ser String")
	elif String(manifest.transaction_id) != _transaction_id:
		errors.append(
			"transaction_id divergente: esperado %s, obtido %s"
			% [_transaction_id, String(manifest.transaction_id)],
		)
	if _transaction_id.is_empty() or not _transaction_id.begins_with("txn_") \
			or _transaction_id.contains("/") or _transaction_id.contains("\\") \
			or _transaction_id == "txn_." or _transaction_id == "txn_..":
		errors.append("transaction_id interno não canônico")
	var expected_stage := STAGING_PARENT.path_join(_transaction_id)
	if last_stage_path != expected_stage:
		errors.append("staging não corresponde ao transaction_id")
	var manifest_entries_value: Variant = manifest.get("entries")
	if not (manifest_entries_value is Array) or manifest_entries_value.is_empty():
		errors.append("manifest sem entries")
		return errors
	var manifest_entries: Array = manifest_entries_value
	var seen_targets := {}
	for index in manifest_entries.size():
		var record_variant: Variant = manifest_entries[index]
		if not (record_variant is Dictionary):
			errors.append("entry %d de manifest inválida" % index)
			continue
		var record: Dictionary = record_variant
		if typeof(record.get("target")) != TYPE_STRING:
			errors.append("entry %d: target precisa ser String" % index)
			continue
		var target := String(record.target)
		var target_error := _target_path_error(target)
		if not target_error.is_empty():
			errors.append("entry %d: %s" % [index, target_error])
		if seen_targets.has(target):
			errors.append("entry %d: target duplicado no manifest: %s" % [index, target])
		else:
			seen_targets[target] = true

		if typeof(record.get("existed")) != TYPE_BOOL:
			errors.append("entry %d: existed precisa ser bool" % index)
		var existed: bool = record.get("existed") if typeof(record.get("existed")) == TYPE_BOOL else false
		for field in ["payload", "backup", "next", "old", "payload_sha256", "backup_sha256"]:
			if typeof(record.get(field)) != TYPE_STRING:
				errors.append("entry %d: %s precisa ser String" % [index, field])
		var payload_size := _manifest_nonnegative_size(record, "payload_size", index, errors)
		var backup_size := _manifest_nonnegative_size(record, "backup_size", index, errors)

		var expected_payload := last_stage_path.path_join(
			"payload/%03d_%s" % [index, target.get_file()],
		)
		var expected_backup := last_stage_path.path_join("backup/%03d.bin" % index) if existed else ""
		var expected_next := target + ".qix-next-" + _transaction_id
		var expected_old := target + ".qix-old-" + _transaction_id
		_validate_exact_manifest_path(record, "payload", expected_payload, index, errors)
		_validate_exact_manifest_path(record, "backup", expected_backup, index, errors)
		_validate_exact_manifest_path(record, "next", expected_next, index, errors)
		_validate_exact_manifest_path(record, "old", expected_old, index, errors)

		var payload_sha256 := String(record.get("payload_sha256", "")) \
			if typeof(record.get("payload_sha256")) == TYPE_STRING else ""
		if payload_size == 0:
			errors.append("entry %d: payload_size precisa ser positivo" % index)
		if not _is_sha256_text(payload_sha256):
			errors.append("entry %d: payload_sha256 precisa ser SHA-256 lowercase" % index)
		if typeof(record.get("payload")) == TYPE_STRING \
				and String(record.payload) == expected_payload \
				and payload_size > 0 and _is_sha256_text(payload_sha256):
			_validate_artifact_integrity(
				expected_payload, payload_size, payload_sha256, "payload", index, errors,
			)

		var backup_sha256 := String(record.get("backup_sha256", "")) \
			if typeof(record.get("backup_sha256")) == TYPE_STRING else ""
		if existed:
			if not _is_sha256_text(backup_sha256):
				errors.append("entry %d: backup_sha256 precisa ser SHA-256 lowercase" % index)
			if typeof(record.get("backup")) == TYPE_STRING \
					and String(record.backup) == expected_backup \
					and backup_size >= 0 and _is_sha256_text(backup_sha256):
				_validate_artifact_integrity(
					expected_backup, backup_size, backup_sha256, "backup", index, errors,
				)
		else:
			if backup_size != 0:
				errors.append("entry %d: backup_size precisa ser zero quando existed=false" % index)
			if not backup_sha256.is_empty():
				errors.append("entry %d: backup_sha256 precisa ser vazio quando existed=false" % index)
	return errors


func _validate_exact_manifest_path(
	record: Dictionary,
	field: String,
	expected: String,
	index: int,
	errors: PackedStringArray,
) -> void:
	if typeof(record.get(field)) != TYPE_STRING:
		return
	var actual := String(record.get(field))
	if actual != expected:
		errors.append(
			"entry %d: %s não é o path canônico esperado; esperado %s, obtido %s"
			% [index, field, expected, actual],
		)


func _manifest_nonnegative_size(
	record: Dictionary,
	field: String,
	index: int,
	errors: PackedStringArray,
) -> int:
	var value: Variant = record.get(field)
	var size := -1
	if typeof(value) == TYPE_INT:
		size = int(value)
	elif typeof(value) == TYPE_FLOAT and is_finite(float(value)) \
			and float(value) == floor(float(value)):
		size = int(value)
	else:
		errors.append("entry %d: %s precisa ser inteiro JSON" % [index, field])
		return -1
	if size < 0:
		errors.append("entry %d: %s não pode ser negativo" % [index, field])
		return -1
	return size


func _validate_artifact_integrity(
	path: String,
	expected_size: int,
	expected_sha256: String,
	label: String,
	index: int,
	errors: PackedStringArray,
) -> void:
	if not FileAccess.file_exists(path):
		errors.append("entry %d: %s esperado ausente" % [index, label])
		return
	var bytes := FileAccess.get_file_as_bytes(path)
	var read_error := FileAccess.get_open_error()
	if read_error != OK:
		errors.append("entry %d: não leu %s: %s" % [index, label, error_string(read_error)])
		return
	if bytes.size() != expected_size:
		errors.append(
			"entry %d: %s_size diverge; esperado %d, obtido %d"
			% [index, label, expected_size, bytes.size()],
		)
	var actual_sha256 := _sha256_bytes(bytes)
	if actual_sha256 != expected_sha256:
		errors.append(
			"entry %d: %s_sha256 diverge; esperado %s, obtido %s"
			% [index, label, expected_sha256, actual_sha256],
		)


func _validate_terminal_target_state(manifest: Dictionary, state: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var records: Array = manifest.get("entries", [])
	for index in records.size():
		var record: Dictionary = records[index]
		var target := String(record.target)
		if state == "committed":
			_validate_artifact_integrity(
				target,
				int(record.payload_size),
				String(record.payload_sha256),
				"committed_target",
				index,
				errors,
			)
		elif record.existed:
			_validate_artifact_integrity(
				target,
				int(record.backup_size),
				String(record.backup_sha256),
				"rolled_back_target",
				index,
				errors,
			)
		elif FileAccess.file_exists(target):
			errors.append("entry %d: rolled_back target novo ainda existe: %s" % [index, target])
		for temporary_field in ["next", "old"]:
			var temporary_path := String(record.get(temporary_field, ""))
			if FileAccess.file_exists(temporary_path):
				errors.append(
					"entry %d: terminal %s ainda possui temporário %s"
					% [index, state, temporary_field],
				)
	return errors


func _read_manifest(stage_path: String) -> Dictionary:
	var path := stage_path.path_join(MANIFEST_NAME)
	if not FileAccess.file_exists(path):
		return {}
	var manifest_text := FileAccess.get_file_as_string(path)
	if FileAccess.get_open_error() != OK:
		return {}
	var parsed: Variant = _parse_json(manifest_text)
	return parsed if parsed is Dictionary else {}


func _parse_json(contents: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(contents) != OK:
		return null
	return parser.data


func _canonical_manifest_sha256(manifest: Dictionary) -> String:
	# Round-trip first so an in-memory int and its JSON number representation
	# canonicalize exactly like the manifest read by a later process. sort_keys
	# removes Dictionary insertion-order and whitespace from the authority hash.
	var encoded := JSON.stringify(manifest, "", true, true)
	var normalized: Variant = _parse_json(encoded)
	if not (normalized is Dictionary):
		return ""
	var canonical := JSON.stringify(normalized, "", true, true)
	return canonical.sha256_text()


func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


func _is_sha256_text(value: String) -> bool:
	if value.length() != 64:
		return false
	for byte in value.to_ascii_buffer():
		if not (byte >= 48 and byte <= 57) and not (byte >= 97 and byte <= 102):
			return false
	return true


func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
	var resolved := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(resolved.get_base_dir())
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(resolved, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	file.close()
	return OK


func _write_text(path: String, contents: String) -> Error:
	var resolved := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(resolved.get_base_dir())
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(resolved, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(contents)
	file.flush()
	file.close()
	return OK


func _remove_file_if_present(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _cleanup_stage() -> void:
	if last_stage_path.is_empty():
		return
	var stage_absolute := ProjectSettings.globalize_path(last_stage_path).simplify_path()
	var parent_absolute := ProjectSettings.globalize_path(STAGING_PARENT).simplify_path().trim_suffix("/")
	if not stage_absolute.begins_with(parent_absolute + "/"):
		return
	_remove_tree(stage_absolute)


func _remove_tree(absolute_path: String) -> void:
	if not DirAccess.dir_exists_absolute(absolute_path):
		return
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var child := absolute_path.path_join(name)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
		name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute_path)
