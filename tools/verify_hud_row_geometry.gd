extends SceneTree
## Uso: Godot --headless --path . --script res://tools/verify_hud_row_geometry.gd
##
## Mede a **altura** das linhas de texto do HUD nas condições em que o jogo as monta, e falha se
## alguma linha deixar de caber na barra que a hospeda ou encostar no trilho do objetivo.
##
## Por que uma ferramenta em vez de um teste: `tests/unit/game_hud_layout_test.gd` corre dentro de
## `_initialize()`, antes de a árvore processar um único frame, e nessa janela o mínimo de um
## `Label` ainda vale 23 px — o `size` pedido é clampado para cima e nenhuma medição vertical ali
## diz a verdade. O runner mede o eixo X (cujo mínimo é 1 px) e declara o contrato vertical pelas
## constantes; **esta** ferramenta é quem confere que as constantes descrevem o que se desenha.
##
## O HUD entra na árvore durante um frame já em curso, exatamente como no jogo. Medido em
## 2026-09-06: nessa via o `size` assenta em `TEXT_HEIGHT` já no `add_child`, sem esperar frame
## nenhum, e permanece estável nos frames seguintes.

const TOP_BAND := ["Round", "Score", "Percent", "Vitals"]
const BOTTOM_BAND := ["RoundTitle", "Status"]
## Quatro frames: um para montar e três para provar que nada assenta noutro valor depois.
const FRAMES_TO_OBSERVE := 4

var _hud: QixGameHud
var _frames: int = 0
## Mensagem → primeiro frame em que apareceu. Uma linha alta falha em todos os frames; repetir a
## queixa quatro vezes esconde as outras cinco linhas em vez de as mostrar.
var _failures: Dictionary = {}


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_hud = QixGameHud.new()
		# `add_child` numa árvore que já processa dispara `_ready` como o jogo dispara.
		root.add_child(_hud)
		print("HUD montado durante o frame 1, como na via de produção.")
		print("")
		print("  rótulo      pos.y   altura   mínimo   fonte   linha ocupada")

	_measure(_frames)
	if _frames < FRAMES_TO_OBSERVE:
		return false

	print("")
	if _failures.is_empty():
		print("catraca: as %d linhas de texto cabem nas suas barras em %d frames consecutivos" % [
			TOP_BAND.size() + BOTTOM_BAND.size(), FRAMES_TO_OBSERVE])
		quit(0)
		return true
	for message: String in _failures:
		printerr("REGRESSÃO (desde o frame %d): %s" % [_failures[message], message])
	quit(1)
	return true


func _measure(frame: int) -> void:
	_check_band(frame, TOP_BAND, 0.0, QixGameHud.TOP_BAR_HEIGHT)
	_check_band(
		frame, BOTTOM_BAND,
		QixGameHud.BOTTOM_BAR_Y,
		QixGameHud.BOTTOM_BAR_Y + QixGameHud.BOTTOM_BAR_HEIGHT)


func _check_band(frame: int, band: Array, bar_top: float, bar_bottom: float) -> void:
	for node_name: String in band:
		var label := _hud.get_node(node_name) as Label
		var top := label.position.y
		var bottom := top + label.size.y
		var font_height := label.get_theme_font("font").get_height(
			label.get_theme_font_size("font_size"))
		if frame == 1:
			print("  %-11s %5.1f   %6.1f   %6.1f   %5.1f   %.1f..%.1f" % [
				node_name, top, label.size.y,
				label.get_combined_minimum_size().y, font_height, top, bottom])

		# A altura pedida é a que o jogo desenha: se o mínimo do `Label` a empurrar para cima,
		# a linha cresce por baixo e come o vizinho sem que nada avise.
		if not is_equal_approx(label.size.y, QixGameHud.TEXT_HEIGHT):
			_fail(frame, "%s tem %.1f px de altura onde TEXT_HEIGHT pede %.1f" % [
				node_name, label.size.y, QixGameHud.TEXT_HEIGHT])
		if top < bar_top or bottom > bar_bottom:
			_fail(frame, "%s ocupa %.1f..%.1f e a barra vai de %.1f a %.1f" % [
				node_name, top, bottom, bar_top, bar_bottom])
		# O glifo é desenhado centrado no retângulo; é ele, não o retângulo, que se lê.
		if font_height > label.size.y:
			_fail(frame, "%s: fonte de %.1f px numa linha de %.1f" % [
				node_name, font_height, label.size.y])


func _fail(frame: int, message: String) -> void:
	if not _failures.has(message):
		_failures[message] = frame


## O trilho do objetivo divide os 19 px da barra superior com os números. Verificado aqui, e não
## só nas constantes, porque quem cresce é o retângulo do `Label`, não a constante.
func _initialize() -> void:
	if QixGameHud.TOP_TEXT_Y + QixGameHud.TEXT_HEIGHT > QixGameHud.TRACK_Y:
		_fail(0, "a linha do topo desce até %.1f e o trilho começa em %.1f" % [
			QixGameHud.TOP_TEXT_Y + QixGameHud.TEXT_HEIGHT, QixGameHud.TRACK_Y])
