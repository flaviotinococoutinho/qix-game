class_name TestCase
extends RefCounted
## Base mínima para testes headless sem addon. Cada método `test_*` corre isolado.

var failed: bool = false
var messages: String = ""
var assertions: int = 0


func reset() -> void:
	failed = false
	messages = ""
	assertions = 0


func fail(msg: String) -> void:
	failed = true
	messages += "    " + msg + "\n"


func ok(cond: bool, msg: String = "") -> void:
	assertions += 1
	if not cond:
		fail("esperado verdadeiro: " + msg)


func eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	assertions += 1
	if actual != expected:
		fail("%s\n      esperado: %s\n      obtido:   %s" % [msg, str(expected), str(actual)])


func ne(actual: Variant, unexpected: Variant, msg: String = "") -> void:
	assertions += 1
	if actual == unexpected:
		fail("%s — não devia ser %s" % [msg, str(unexpected)])
