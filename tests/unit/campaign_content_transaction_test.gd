extends TestCase

const TRANSACTION_SCRIPT := "res://tools/campaign_content_transaction.gd"
const STAGING_PARENT := "user://qix-campaign-content-staging"
const LOCK_DIRECTORY := STAGING_PARENT + "/.txn_active.lock"


func test_successful_commit_stages_every_resource_and_cleans_the_stage() -> void:
	var transaction = _new_transaction()
	if transaction == null:
		return
	var root := _test_root("success")
	_cleanup_tree(root)
	var first := _rules(111)
	var second := _rules(222)
	var errors: PackedStringArray = transaction.execute([
		{"path": root + "/first.tres", "resource": first},
		{"path": root + "/second.tres", "resource": second},
	])
	eq(errors, PackedStringArray())
	ok(FileAccess.file_exists(root + "/first.tres"))
	ok(FileAccess.file_exists(root + "/second.tres"))
	var loaded_first := ResourceLoader.load(
		root + "/first.tres", "", ResourceLoader.CACHE_MODE_IGNORE,
	) as GameRules
	var loaded_second := ResourceLoader.load(
		root + "/second.tres", "", ResourceLoader.CACHE_MODE_IGNORE,
	) as GameRules
	ok(loaded_first != null)
	ok(loaded_second != null)
	if loaded_first != null:
		eq(loaded_first.completion_bonus, 111)
	if loaded_second != null:
		eq(loaded_second.completion_bonus, 222)
	eq(transaction.promoted_from_stage_count, 2, "commit deve promover os payloads validados do staging")
	ok(not DirAccess.dir_exists_absolute(transaction.last_stage_path))
	_cleanup_tree(root)


func test_failed_commit_restores_existing_files_byte_for_byte() -> void:
	var transaction = _new_transaction()
	if transaction == null:
		return
	var root := _test_root("rollback_existing")
	_cleanup_tree(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var first_path := root + "/first.tres"
	var second_path := root + "/second.tres"
	eq(ResourceSaver.save(_rules(10), first_path), OK)
	eq(ResourceSaver.save(_rules(20), second_path), OK)
	var before_first := FileAccess.get_file_as_bytes(first_path)
	var before_second := FileAccess.get_file_as_bytes(second_path)
	transaction.fail_after_commits = 1
	var errors: PackedStringArray = transaction.execute([
		{"path": first_path, "resource": _rules(1010)},
		{"path": second_path, "resource": _rules(2020)},
	])
	ok(not errors.is_empty(), "falha injetada precisa abortar a transação")
	eq(FileAccess.get_file_as_bytes(first_path), before_first)
	eq(FileAccess.get_file_as_bytes(second_path), before_second)
	ok(transaction.rollback_performed)
	ok(not DirAccess.dir_exists_absolute(transaction.last_stage_path))
	_cleanup_tree(root)


func test_rollback_removes_targets_that_did_not_exist_before_commit() -> void:
	var transaction = _new_transaction()
	if transaction == null:
		return
	var root := _test_root("rollback_new")
	_cleanup_tree(root)
	transaction.fail_after_commits = 1
	var first_path := root + "/created.tres"
	var second_path := root + "/never_committed.tres"
	var errors: PackedStringArray = transaction.execute([
		{"path": first_path, "resource": _rules(3030)},
		{"path": second_path, "resource": _rules(4040)},
	])
	ok(not errors.is_empty())
	ok(not FileAccess.file_exists(first_path))
	ok(not FileAccess.file_exists(second_path))
	ok(transaction.rollback_performed)
	_cleanup_tree(root)


func test_duplicate_target_is_rejected_before_any_mutation() -> void:
	var transaction = _new_transaction()
	if transaction == null:
		return
	var root := _test_root("duplicate")
	_cleanup_tree(root)
	var path := root + "/same.tres"
	var errors: PackedStringArray = transaction.execute([
		{"path": path, "resource": _rules(1)},
		{"path": path, "resource": _rules(2)},
	])
	ok(not errors.is_empty())
	ok(errors[0].contains("duplicado"))
	ok(not FileAccess.file_exists(path))
	_cleanup_tree(root)


func test_abandoned_commit_is_recovered_from_durable_manifest_and_backups() -> void:
	var transaction = _new_transaction()
	if transaction == null:
		return
	var root := _test_root("crash_recovery")
	_cleanup_tree(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var first_path := root + "/first.tres"
	var second_path := root + "/second.tres"
	eq(ResourceSaver.save(_rules(11), first_path), OK)
	eq(ResourceSaver.save(_rules(22), second_path), OK)
	var before_first := FileAccess.get_file_as_bytes(first_path)
	var before_second := FileAccess.get_file_as_bytes(second_path)

	transaction.interrupt_after_commits = 1
	var interrupted: PackedStringArray = transaction.execute([
		{"path": first_path, "resource": _rules(1111)},
		{"path": second_path, "resource": _rules(2222)},
	])
	ok(not interrupted.is_empty())
	ok(transaction.interruption_simulated)
	ok(DirAccess.dir_exists_absolute(transaction.last_stage_path))
	ok(FileAccess.file_exists(transaction.last_stage_path + "/manifest.json"))
	ok(FileAccess.file_exists(transaction.last_stage_path + "/journal.jsonl"))
	ok(FileAccess.get_file_as_bytes(first_path) != before_first, "primeiro arquivo comprova commit parcial")
	eq(FileAccess.get_file_as_bytes(second_path), before_second)

	var recovery = _new_transaction()
	if recovery == null:
		return
	var recovery_errors: PackedStringArray = recovery.recover_incomplete_transactions()
	eq(recovery_errors, PackedStringArray())
	eq(recovery.recovered_transaction_count, 1)
	eq(FileAccess.get_file_as_bytes(first_path), before_first)
	eq(FileAccess.get_file_as_bytes(second_path), before_second)
	ok(not DirAccess.dir_exists_absolute(transaction.last_stage_path))
	_cleanup_tree(root)


func test_rollback_restores_resource_cache_owner_and_old_value() -> void:
	var transaction = _new_transaction()
	if transaction == null:
		return
	var root := _test_root("cache_restore")
	_cleanup_tree(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var first_path := root + "/first.tres"
	var second_path := root + "/second.tres"
	eq(ResourceSaver.save(_rules(31), first_path), OK)
	eq(ResourceSaver.save(_rules(32), second_path), OK)
	var cached_old := ResourceLoader.load(first_path) as GameRules
	ok(cached_old != null)
	transaction.fail_after_commits = 1
	var replacement := _rules(3131)
	var errors: PackedStringArray = transaction.execute([
		{"path": first_path, "resource": replacement},
		{"path": second_path, "resource": _rules(3232)},
	])
	ok(not errors.is_empty())
	var loaded_after := ResourceLoader.load(first_path) as GameRules
	ok(loaded_after == cached_old, "rollback devolve ownership do path ao Resource antes cacheado")
	if loaded_after != null:
		eq(loaded_after.completion_bonus, 31)
	eq(replacement.resource_path, "")
	_cleanup_tree(root)


func test_paths_with_traversal_or_non_resource_extension_are_rejected() -> void:
	var transaction = _new_transaction()
	if transaction == null:
		return
	for invalid_path in [
		"user://transaction-tests/../escape.tres",
		"res://../escape.tres",
		"user://transaction-tests//double.tres",
		"user://transaction-tests/not-a-resource.json",
	]:
		var errors: PackedStringArray = transaction.execute([
			{"path": invalid_path, "resource": _rules(1)},
		])
		ok(not errors.is_empty(), "precisa rejeitar %s" % invalid_path)


func test_recovery_rejects_wrong_transaction_id_without_touching_targets() -> void:
	var fixture := _interrupted_fixture("tampered_transaction_id")
	if fixture.is_empty():
		return
	var manifest: Dictionary = _read_json_dictionary(String(fixture.manifest_path))
	manifest["transaction_id"] = "txn_attacker"
	_write_json(String(fixture.manifest_path), manifest)

	var recovery = _new_transaction()
	if recovery == null:
		return
	var errors: PackedStringArray = recovery.recover_incomplete_transactions()
	ok(not errors.is_empty(), "transaction_id divergente precisa falhar fechado")
	ok(_errors_contain(errors, "transaction_id"))
	eq(FileAccess.get_file_as_bytes(String(fixture.first_path)), fixture.partial_first)
	eq(FileAccess.get_file_as_bytes(String(fixture.second_path)), fixture.before_second)
	ok(DirAccess.dir_exists_absolute(String(fixture.stage_path)))
	_cleanup_tree(String(fixture.stage_path))
	_cleanup_tree(String(fixture.root))


func test_wal_anchor_rejects_valid_false_existed_and_recanonicalized_canary_target() -> void:
	var fixture := _interrupted_fixture("wal_anchor_target_rewrite")
	if fixture.is_empty():
		return
	var canary_path := String(fixture.root) + "/canary/first.tres"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(canary_path.get_base_dir()))
	eq(ResourceSaver.save(_rules(9191), canary_path), OK)
	var canary_bytes := FileAccess.get_file_as_bytes(canary_path)
	var manifest: Dictionary = _read_json_dictionary(String(fixture.manifest_path))
	var records: Array = manifest.entries
	var first: Dictionary = records[0]
	first["target"] = canary_path
	first["existed"] = false
	first["backup"] = ""
	first["backup_size"] = 0
	first["backup_sha256"] = ""
	first["next"] = canary_path + ".qix-next-txn_active"
	first["old"] = canary_path + ".qix-old-txn_active"
	records[0] = first
	manifest["entries"] = records
	_write_json(String(fixture.manifest_path), manifest)

	var recovery = _new_transaction()
	if recovery == null:
		return
	var errors: PackedStringArray = recovery.recover_incomplete_transactions()
	ok(not errors.is_empty(), "manifesto estruturalmente válido, mas diferente do prepared, deve ser recusado")
	ok(_errors_contain(errors, "manifest_sha256"))
	eq(FileAccess.get_file_as_bytes(canary_path), canary_bytes, "rollback não pode apagar target recanonizado")
	eq(FileAccess.get_file_as_bytes(String(fixture.first_path)), fixture.partial_first)
	eq(FileAccess.get_file_as_bytes(String(fixture.second_path)), fixture.before_second)
	ok(DirAccess.dir_exists_absolute(String(fixture.stage_path)))
	_cleanup_tree(String(fixture.stage_path))
	_cleanup_tree(String(fixture.root))


func test_backup_same_size_corruption_fails_closed_before_any_target_mutation() -> void:
	var fixture := _interrupted_fixture("corrupt_backup_digest")
	if fixture.is_empty():
		return
	var manifest: Dictionary = _read_json_dictionary(String(fixture.manifest_path))
	var backup_path := String((manifest.entries as Array)[0].backup)
	var corrupted := FileAccess.get_file_as_bytes(backup_path)
	ok(not corrupted.is_empty())
	if corrupted.is_empty():
		return
	corrupted[0] = corrupted[0] ^ 0x01
	_write_bytes(backup_path, corrupted)

	var recovery = _new_transaction()
	if recovery == null:
		return
	var errors: PackedStringArray = recovery.recover_incomplete_transactions()
	ok(not errors.is_empty(), "backup com mesmo tamanho e SHA diferente deve bloquear rollback")
	ok(_errors_contain(errors, "backup_sha256"))
	eq(FileAccess.get_file_as_bytes(String(fixture.first_path)), fixture.partial_first)
	eq(FileAccess.get_file_as_bytes(String(fixture.second_path)), fixture.before_second)
	ok(DirAccess.dir_exists_absolute(String(fixture.stage_path)))
	_cleanup_tree(String(fixture.stage_path))
	_cleanup_tree(String(fixture.root))


func test_payload_same_size_corruption_fails_closed_before_rollback() -> void:
	var fixture := _interrupted_fixture("corrupt_payload_digest")
	if fixture.is_empty():
		return
	var manifest: Dictionary = _read_json_dictionary(String(fixture.manifest_path))
	var payload_path := String((manifest.entries as Array)[0].payload)
	var corrupted := FileAccess.get_file_as_bytes(payload_path)
	ok(not corrupted.is_empty())
	if corrupted.is_empty():
		return
	corrupted[corrupted.size() - 1] = corrupted[corrupted.size() - 1] ^ 0x01
	_write_bytes(payload_path, corrupted)

	var recovery = _new_transaction()
	if recovery == null:
		return
	var errors: PackedStringArray = recovery.recover_incomplete_transactions()
	ok(not errors.is_empty(), "payload com mesmo tamanho e SHA diferente deve bloquear recovery")
	ok(_errors_contain(errors, "payload_sha256"))
	eq(FileAccess.get_file_as_bytes(String(fixture.first_path)), fixture.partial_first)
	eq(FileAccess.get_file_as_bytes(String(fixture.second_path)), fixture.before_second)
	ok(DirAccess.dir_exists_absolute(String(fixture.stage_path)))
	_cleanup_tree(String(fixture.stage_path))
	_cleanup_tree(String(fixture.root))


func test_wal_rejects_bare_committed_append_before_cleaning_partial_stage() -> void:
	var fixture := _interrupted_fixture("wal_bare_committed")
	if fixture.is_empty():
		return
	_append_text(String(fixture.stage_path) + "/journal.jsonl", "{\"state\":\"committed\"}\n")
	_assert_recovery_fails_closed(fixture, "WAL record")


func test_wal_rejects_apparently_valid_but_premature_committed_terminal() -> void:
	var fixture := _interrupted_fixture("wal_premature_terminal")
	if fixture.is_empty():
		return
	var prepared := _first_journal_record(String(fixture.stage_path))
	var terminal := prepared.duplicate(true)
	terminal["state"] = "committed"
	terminal["committed_count"] = 1
	terminal["unix_time"] = int(Time.get_unix_time_from_system())
	_append_journal_fixture(String(fixture.stage_path), terminal)
	_assert_recovery_fails_closed(fixture, "terminal committed prematuro")


func test_wal_rejects_regressive_and_greater_than_entry_counts() -> void:
	for case in [
		{"suffix": "wal_regressive_count", "count": 0, "needle": "regressivo"},
		{"suffix": "wal_excess_count", "count": 3, "needle": "fora do intervalo"},
	]:
		var fixture := _interrupted_fixture(String(case.suffix))
		if fixture.is_empty():
			return
		var prepared := _first_journal_record(String(fixture.stage_path))
		var progress := prepared.duplicate(true)
		progress["state"] = "committing"
		progress["committed_count"] = int(case.count)
		progress["unix_time"] = int(Time.get_unix_time_from_system())
		_append_journal_fixture(String(fixture.stage_path), progress)
		_assert_recovery_fails_closed(fixture, String(case.needle))


func test_wal_rejects_truncated_json_and_records_after_terminal() -> void:
	var truncated := _interrupted_fixture("wal_truncated_json")
	if truncated.is_empty():
		return
	_append_text(String(truncated.stage_path) + "/journal.jsonl", "{\"state\":")
	_assert_recovery_fails_closed(truncated, "JSON inválido")

	var extra := _interrupted_fixture("wal_record_after_terminal")
	if extra.is_empty():
		return
	var prepared := _first_journal_record(String(extra.stage_path))
	var rolled_back := prepared.duplicate(true)
	rolled_back["state"] = "rolled_back"
	rolled_back["committed_count"] = 1
	rolled_back["unix_time"] = int(Time.get_unix_time_from_system())
	_append_journal_fixture(String(extra.stage_path), rolled_back)
	var trailing := rolled_back.duplicate(true)
	trailing["state"] = "committing"
	_append_journal_fixture(String(extra.stage_path), trailing)
	_assert_recovery_fails_closed(extra, "após terminal")


func test_wal_rejects_digest_and_transaction_divergence_on_any_record() -> void:
	for case in [
		{"suffix": "wal_digest_divergent", "field": "manifest_sha256", "value": "0".repeat(64), "needle": "manifest_sha256"},
		{"suffix": "wal_transaction_divergent", "field": "transaction_id", "value": "txn_other", "needle": "transaction_id"},
	]:
		var fixture := _interrupted_fixture(String(case.suffix))
		if fixture.is_empty():
			return
		var prepared := _first_journal_record(String(fixture.stage_path))
		var record := prepared.duplicate(true)
		record["state"] = "committing"
		record["committed_count"] = 2
		record[String(case.field)] = case.value
		record["unix_time"] = int(Time.get_unix_time_from_system())
		_append_journal_fixture(String(fixture.stage_path), record)
		_assert_recovery_fails_closed(fixture, String(case.needle))


func test_wal_terminal_requires_targets_to_match_claimed_durable_state() -> void:
	for terminal_state in ["committed", "rolled_back"]:
		var fixture := _interrupted_fixture("wal_forged_%s" % terminal_state)
		if fixture.is_empty():
			return
		var prepared := _first_journal_record(String(fixture.stage_path))
		if terminal_state == "committed":
			var final_progress := prepared.duplicate(true)
			final_progress["state"] = "committing"
			final_progress["committed_count"] = 2
			final_progress["unix_time"] = int(Time.get_unix_time_from_system())
			_append_journal_fixture(String(fixture.stage_path), final_progress)
		var terminal := prepared.duplicate(true)
		terminal["state"] = terminal_state
		terminal["committed_count"] = 2 if terminal_state == "committed" else 1
		terminal["unix_time"] = int(Time.get_unix_time_from_system())
		_append_journal_fixture(String(fixture.stage_path), terminal)
		_assert_recovery_fails_closed(fixture, "%s_target_sha256" % terminal_state)


func test_recovery_preserves_staging_when_present_manifest_is_malformed_json() -> void:
	var fixture := _interrupted_fixture("malformed_manifest")
	if fixture.is_empty():
		return
	_write_text(String(fixture.manifest_path), "{manifest truncado")

	var recovery = _new_transaction()
	if recovery == null:
		return
	var errors: PackedStringArray = recovery.recover_incomplete_transactions()
	ok(not errors.is_empty(), "manifest presente e ilegível nunca equivale a pré-manifest")
	ok(_errors_contain(errors, "manifest presente, mas inválido"))
	eq(FileAccess.get_file_as_bytes(String(fixture.first_path)), fixture.partial_first)
	eq(FileAccess.get_file_as_bytes(String(fixture.second_path)), fixture.before_second)
	ok(DirAccess.dir_exists_absolute(String(fixture.stage_path)), "backups precisam ficar preservados")
	_cleanup_tree(String(fixture.stage_path))
	_cleanup_tree(String(fixture.root))


func test_recovery_rejects_non_boolean_existed_and_preserves_canary() -> void:
	var fixture := _interrupted_fixture("tampered_existed")
	if fixture.is_empty():
		return
	var canary_path := String(fixture.root) + "/do-not-remove.tres"
	eq(ResourceSaver.save(_rules(9090), canary_path), OK)
	var canary_bytes := FileAccess.get_file_as_bytes(canary_path)
	var manifest: Dictionary = _read_json_dictionary(String(fixture.manifest_path))
	var records: Array = manifest.entries
	var first: Dictionary = records[0]
	first["existed"] = "false"
	first["next"] = canary_path
	records[0] = first
	manifest["entries"] = records
	_write_json(String(fixture.manifest_path), manifest)

	var recovery = _new_transaction()
	if recovery == null:
		return
	var errors: PackedStringArray = recovery.recover_incomplete_transactions()
	ok(not errors.is_empty(), "existed precisa ser bool JSON real")
	ok(_errors_contain(errors, "existed"))
	eq(FileAccess.get_file_as_bytes(canary_path), canary_bytes, "manifest inválido não remove canary")
	eq(FileAccess.get_file_as_bytes(String(fixture.first_path)), fixture.partial_first)
	ok(DirAccess.dir_exists_absolute(String(fixture.stage_path)))
	_cleanup_tree(String(fixture.stage_path))
	_cleanup_tree(String(fixture.root))


func test_recovery_rejects_non_adjacent_next_and_old_paths_before_rollback() -> void:
	var fixture := _interrupted_fixture("tampered_adjacent_paths")
	if fixture.is_empty():
		return
	var canary_next := String(fixture.root) + "/canary-next.tres"
	var canary_old := String(fixture.root) + "/canary-old.tres"
	eq(ResourceSaver.save(_rules(7001), canary_next), OK)
	eq(ResourceSaver.save(_rules(7002), canary_old), OK)
	var next_bytes := FileAccess.get_file_as_bytes(canary_next)
	var old_bytes := FileAccess.get_file_as_bytes(canary_old)
	var manifest: Dictionary = _read_json_dictionary(String(fixture.manifest_path))
	var records: Array = manifest.entries
	var first: Dictionary = records[0]
	first["next"] = canary_next
	first["old"] = canary_old
	records[0] = first
	manifest["entries"] = records
	_write_json(String(fixture.manifest_path), manifest)

	var recovery = _new_transaction()
	if recovery == null:
		return
	var errors: PackedStringArray = recovery.recover_incomplete_transactions()
	ok(not errors.is_empty(), "next/old não derivados do target precisam falhar fechado")
	ok(_errors_contain(errors, "next"))
	ok(_errors_contain(errors, "old"))
	eq(FileAccess.get_file_as_bytes(canary_next), next_bytes)
	eq(FileAccess.get_file_as_bytes(canary_old), old_bytes)
	eq(FileAccess.get_file_as_bytes(String(fixture.first_path)), fixture.partial_first)
	ok(DirAccess.dir_exists_absolute(String(fixture.stage_path)))
	_cleanup_tree(String(fixture.stage_path))
	_cleanup_tree(String(fixture.root))


func test_second_process_cannot_recover_or_delete_an_active_stage() -> void:
	var root := _test_root("process_lock")
	_cleanup_tree(root)
	var holder := _spawn_lock_holder(root)
	if holder.is_empty():
		return
	var status := _wait_for_file(String(holder.ready_path), int(holder.pid), 5000)
	eq(status, "READY", "processo auxiliar precisa deter o lock")
	if status != "READY":
		_stop_holder(holder, true)
		_cleanup_tree(root)
		return
	var active_stage := STAGING_PARENT + "/txn_active"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(active_stage))
	var sentinel := active_stage + "/active-owner-sentinel.txt"
	_write_text(sentinel, "owner ainda executando")

	var contender = _new_transaction()
	if contender == null:
		_stop_holder(holder)
		return
	var target := root + "/must-not-exist.tres"
	var errors: PackedStringArray = contender.execute([
		{"path": target, "resource": _rules(5150)},
	])
	ok(not errors.is_empty(), "segundo processo precisa receber busy/fail-closed")
	ok(_errors_contain(errors, "lock exclusivo"))
	ok(FileAccess.file_exists(sentinel), "contender não pode limpar staging do dono ativo")
	ok(not FileAccess.file_exists(target))

	_stop_holder(holder)
	_cleanup_tree(active_stage)
	_cleanup_tree(root)


func test_crashed_process_lock_is_reclaimed_only_after_kernel_guard_is_free() -> void:
	var root := _test_root("stale_process_lock")
	_cleanup_tree(root)
	var holder := _spawn_lock_holder(root)
	if holder.is_empty():
		return
	var status := _wait_for_file(String(holder.ready_path), int(holder.pid), 5000)
	eq(status, "READY")
	if status != "READY":
		_stop_holder(holder, true)
		_cleanup_tree(root)
		return
	var abandoned_stage := STAGING_PARENT + "/txn_active"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(abandoned_stage))
	var sentinel := abandoned_stage + "/abandoned-sentinel.txt"
	_write_text(sentinel, "crash antes do manifest")
	ok(DirAccess.dir_exists_absolute(LOCK_DIRECTORY), "lock-dir diagnóstico precisa existir")

	_stop_holder(holder, true)
	ok(DirAccess.dir_exists_absolute(LOCK_DIRECTORY), "SIGKILL deixa apenas metadado stale")
	var recovery = _new_transaction()
	if recovery == null:
		return
	var target := root + "/after-crash.tres"
	var errors: PackedStringArray = recovery.execute([
		{"path": target, "resource": _rules(6160)},
	])
	eq(errors, PackedStringArray())
	ok(recovery.stale_lock_recovered, "novo processo reabre somente após adquirir guardião do kernel")
	ok(not FileAccess.file_exists(sentinel))
	ok(FileAccess.file_exists(target))
	ok(not DirAccess.dir_exists_absolute(LOCK_DIRECTORY), "release normal remove metadado do lock")
	_cleanup_tree(root)


func _new_transaction():
	var script := load(TRANSACTION_SCRIPT) as GDScript
	ok(script != null, "CampaignContentTransaction precisa existir")
	if script == null:
		return null
	ok(script.can_instantiate(), "CampaignContentTransaction precisa carregar")
	return script.new()


func _interrupted_fixture(suffix: String) -> Dictionary:
	var transaction = _new_transaction()
	if transaction == null:
		return {}
	var root := _test_root(suffix)
	_cleanup_tree(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var first_path := root + "/first.tres"
	var second_path := root + "/second.tres"
	eq(ResourceSaver.save(_rules(81), first_path), OK)
	eq(ResourceSaver.save(_rules(82), second_path), OK)
	var before_second := FileAccess.get_file_as_bytes(second_path)
	transaction.interrupt_after_commits = 1
	var errors: PackedStringArray = transaction.execute([
		{"path": first_path, "resource": _rules(8181)},
		{"path": second_path, "resource": _rules(8282)},
	])
	ok(not errors.is_empty())
	ok(transaction.interruption_simulated)
	return {
		"root": root,
		"stage_path": transaction.last_stage_path,
		"manifest_path": transaction.last_stage_path + "/manifest.json",
		"first_path": first_path,
		"second_path": second_path,
		"partial_first": FileAccess.get_file_as_bytes(first_path),
		"before_second": before_second,
	}


func _spawn_lock_holder(root: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var ready_path := root + "/holder-ready.txt"
	var release_path := root + "/holder-release.txt"
	var helper_path := root + "/lock_holder.gd"
	var helper_source := """extends SceneTree
var transaction

func _initialize() -> void:
	transaction = load(\"res://tools/campaign_content_transaction.gd\").new()
	var errors: PackedStringArray = transaction.acquire_exclusive_lock()
	_write_status(%s, \"READY\" if errors.is_empty() else \"ERROR: \" + \" | \".join(errors))
	if not errors.is_empty():
		quit(2)
		return
	var deadline := Time.get_ticks_msec() + 15000
	while not FileAccess.file_exists(%s) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(10)
	var release_errors: PackedStringArray = transaction.release_exclusive_lock()
	quit(0 if release_errors.is_empty() else 3)

func _write_status(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(value)
		file.flush()
		file.close()
""" % [JSON.stringify(ready_path), JSON.stringify(release_path)]
	_write_text(helper_path, helper_source)
	var args := PackedStringArray([
		"--headless",
		"--audio-driver", "Dummy",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", ProjectSettings.globalize_path(helper_path),
	])
	var pid := OS.create_process(OS.get_executable_path(), args)
	ok(pid > 0, "precisa iniciar processo Godot concorrente")
	if pid <= 0:
		return {}
	return {
		"pid": pid,
		"ready_path": ready_path,
		"release_path": release_path,
	}


func _wait_for_file(path: String, pid: int, timeout_ms: int) -> String:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(path):
			return FileAccess.get_file_as_string(path).strip_edges()
		if not OS.is_process_running(pid):
			break
		OS.delay_msec(10)
	return ""


func _stop_holder(holder: Dictionary, force: bool = false) -> void:
	var pid := int(holder.get("pid", -1))
	if pid <= 0:
		return
	if force:
		eq(OS.kill(pid), OK, "processo auxiliar precisa ser encerrado abruptamente")
		OS.delay_msec(50)
		return
	_write_text(String(holder.release_path), "release")
	var deadline := Time.get_ticks_msec() + 5000
	var running := true
	while running and Time.get_ticks_msec() < deadline:
		running = OS.is_process_running(pid)
		if not running:
			break
		OS.delay_msec(10)
	if running:
		OS.kill(pid)
	ok(not running, "processo auxiliar precisa terminar")


func _read_json_dictionary(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	ok(parsed is Dictionary, "fixture precisa ter manifest JSON")
	return parsed if parsed is Dictionary else {}


func _write_json(path: String, value: Dictionary) -> void:
	_write_text(path, JSON.stringify(value, "  ") + "\n")


func _append_journal_fixture(stage_path: String, record: Dictionary) -> void:
	_append_text(stage_path + "/journal.jsonl", JSON.stringify(record) + "\n")


func _first_journal_record(stage_path: String) -> Dictionary:
	var contents := FileAccess.get_file_as_string(stage_path + "/journal.jsonl")
	var first_line := contents.split("\n", false)[0]
	return _parse_json_dictionary(String(first_line))


func _parse_json_dictionary(contents: String) -> Dictionary:
	var parser := JSON.new()
	var parse_error := parser.parse(contents)
	eq(parse_error, OK, "fixture WAL precisa conter JSON válido")
	return parser.data if parser.data is Dictionary else {}


func _assert_recovery_fails_closed(fixture: Dictionary, needle: String) -> void:
	var recovery = _new_transaction()
	if recovery == null:
		return
	var errors: PackedStringArray = recovery.recover_incomplete_transactions()
	ok(not errors.is_empty(), "WAL inválido precisa falhar fechado")
	ok(_errors_contain(errors, needle), "erro precisa explicar %s: %s" % [needle, errors])
	eq(FileAccess.get_file_as_bytes(String(fixture.first_path)), fixture.partial_first)
	eq(FileAccess.get_file_as_bytes(String(fixture.second_path)), fixture.before_second)
	ok(DirAccess.dir_exists_absolute(String(fixture.stage_path)))
	_cleanup_tree(String(fixture.stage_path))
	_cleanup_tree(String(fixture.root))


func _write_text(path: String, value: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	ok(file != null, "precisa escrever fixture %s" % path)
	if file == null:
		return
	file.store_string(value)
	file.flush()
	file.close()


func _append_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	ok(file != null, "precisa abrir fixture append-only %s" % path)
	if file == null:
		return
	file.seek_end()
	file.store_string(value)
	file.flush()
	file.close()


func _write_bytes(path: String, value: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	ok(file != null, "precisa escrever fixture binária %s" % path)
	if file == null:
		return
	file.store_buffer(value)
	file.flush()
	file.close()


func _errors_contain(errors: PackedStringArray, needle: String) -> bool:
	for error in errors:
		if error.contains(needle):
			return true
	return false


func _rules(completion_bonus: int) -> GameRules:
	var rules := GameRules.new()
	rules.completion_bonus = completion_bonus
	return rules


func _test_root(suffix: String) -> String:
	return "user://transaction-tests/%s" % suffix


func _cleanup_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var directory := DirAccess.open(absolute)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var child := absolute.path_join(name)
		if directory.current_is_dir():
			_cleanup_tree(child)
		else:
			DirAccess.remove_absolute(child)
		name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute)
