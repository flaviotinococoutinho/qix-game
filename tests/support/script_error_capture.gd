extends Logger
## Captura apenas erros de runtime GDScript durante a janela de um teste.
##
## Não possui class_name para manter o runner autocontido. O callback pode ser
## chamado por threads distintas do engine, portanto todo estado é protegido.

var _mutex := Mutex.new()
var _capturing := false
var _errors := PackedStringArray()


func begin_capture() -> void:
	_mutex.lock()
	_capturing = true
	_errors.clear()
	_mutex.unlock()


func end_capture() -> PackedStringArray:
	_mutex.lock()
	var captured := _errors.duplicate()
	_capturing = false
	_errors.clear()
	_mutex.unlock()
	return captured


func _log_error(
	function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	_script_backtraces: Array,
) -> void:
	# push_error, warnings, ERR_FAIL e shaders não são erros de execução do teste.
	if error_type != ERROR_TYPE_SCRIPT:
		return
	_mutex.lock()
	if _capturing:
		var message := rationale if not rationale.is_empty() else code
		if message.is_empty():
			message = "erro de script sem mensagem"
		_errors.append("%s (%s:%d em %s)" % [message, file, line, function])
	_mutex.unlock()
