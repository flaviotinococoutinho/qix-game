extends TestCase

const ScriptErrorCapture := preload("res://tests/support/script_error_capture.gd")


func test_capture_retains_only_script_runtime_errors() -> void:
	var capture = ScriptErrorCapture.new()
	capture.begin_capture()
	capture._log_error(
		"probe",
		"res://tests/probe.gd",
		12,
		"expected engine error",
		"",
		false,
		Logger.ERROR_TYPE_ERROR,
		[],
	)
	capture._log_error(
		"probe",
		"res://tests/probe.gd",
		13,
		"Invalid call",
		"",
		false,
		Logger.ERROR_TYPE_SCRIPT,
		[],
	)
	var errors: PackedStringArray = capture.end_capture()
	eq(errors.size(), 1)
	ok(errors[0].contains("Invalid call"))
	ok(errors[0].contains("res://tests/probe.gd:13"))


func test_capture_window_is_reset_between_tests() -> void:
	var capture = ScriptErrorCapture.new()
	capture.begin_capture()
	capture._log_error("first", "a.gd", 1, "one", "", false, Logger.ERROR_TYPE_SCRIPT, [])
	eq(capture.end_capture().size(), 1)
	capture.begin_capture()
	eq(capture.end_capture(), PackedStringArray())
