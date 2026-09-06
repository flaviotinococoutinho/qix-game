extends TestCase
## O eixo do stick analógico tem trava; o sentido dentro do eixo, não.
##
## `GameInputAdapter.choose_direction` já declara, para o caminho digital, que a direção atual
## vence o empate: "mantém a direção atual em diagonais/sobreposição". O caminho analógico não
## tinha a mesma regra — reavaliava `absf(x) > absf(y)` a cada `InputEventJoypadMotion`, e um
## `InputEventJoypadMotion` chega por eixo, não por vetor.
##
## Por que isso importa **neste** jogo: aqui uma troca de direção com `draw` apertado não é uma
## curva suave, é um canto novo na trilha confirmada. Um stick parado perto de 45° com o ruído
## normal do potenciômetro produzia uma escada de cantos que o jogador não pediu — e cada canto
## alonga a trilha, que é exatamente a moeda de risco que `TrailExposure` lê para acelerar o pulso
## e disparar o aviso do HUD. O jogador pagava exposição por um movimento que não fez.
##
## A trava é só de **eixo**. Inverter o sentido dentro do eixo já sustentado (de RIGHT para LEFT)
## continua imediato: isso é sempre um pedido explícito, nunca ruído.

const NEUTRAL_DEVICE := 0


func _motion(device: int, axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	return event


## Empurra o stick por eventos separados de eixo, como faz o hardware real.
func _push(adapter: GameInputAdapter, x: float, y: float) -> void:
	adapter.handle_event(_motion(NEUTRAL_DEVICE, JOY_AXIS_LEFT_X, x))
	adapter.handle_event(_motion(NEUTRAL_DEVICE, JOY_AXIS_LEFT_Y, y))


## Direção pela superfície pública: nenhum canal digital nem touch ligado.
func _direction(adapter: GameInputAdapter) -> int:
	return adapter.sample_from_state(
		MoveIntent.Dir.NONE, false, false, false, false, false
	).direction


func test_sem_direcao_sustentada_o_desempate_e_o_antigo() -> void:
	# Sem eixo sustentado a regra não muda: `|x| > |y|`, e o empate exato vai para o vertical.
	eq(
		GameInputAdapter.resolve_analog_direction(Vector2(0.5, 0.3), MoveIntent.Dir.NONE),
		MoveIntent.Dir.RIGHT,
		"x domina",
	)
	eq(
		GameInputAdapter.resolve_analog_direction(Vector2(0.3, 0.5), MoveIntent.Dir.NONE),
		MoveIntent.Dir.DOWN,
		"y domina",
	)
	eq(
		GameInputAdapter.resolve_analog_direction(Vector2(0.5, 0.5), MoveIntent.Dir.NONE),
		MoveIntent.Dir.DOWN,
		"empate exato continua vertical, como antes",
	)


func test_empate_exato_fica_com_o_eixo_ja_sustentado() -> void:
	# O hardware manda um eixo por evento, então na prática sempre há um eixo estabelecido antes
	# de a diagonal se formar: o empate perfeito nunca chega "limpo". Antes desta mudança o
	# segundo evento arrancava a direção do primeiro; agora quem está valendo continua valendo.
	var adapter := GameInputAdapter.new()
	_push(adapter, 0.5, 0.5)
	eq(_direction(adapter), MoveIntent.Dir.RIGHT, "o eixo x chegou primeiro e segura o empate")

	adapter = GameInputAdapter.new()
	adapter.handle_event(_motion(NEUTRAL_DEVICE, JOY_AXIS_LEFT_Y, 0.5))
	adapter.handle_event(_motion(NEUTRAL_DEVICE, JOY_AXIS_LEFT_X, 0.5))
	eq(_direction(adapter), MoveIntent.Dir.DOWN, "o eixo y chegou primeiro e segura o empate")

	adapter = GameInputAdapter.new()
	_push(adapter, 0.3, 0.5)
	eq(
		_direction(adapter),
		MoveIntent.Dir.DOWN,
		"0.3 sozinho não passa do limiar de pressão: quem estabelece o eixo é o y",
	)


func test_ruido_na_diagonal_nao_troca_o_eixo() -> void:
	var adapter := GameInputAdapter.new()
	_push(adapter, 0.60, 0.60)
	var held := _direction(adapter)
	ne(held, MoveIntent.Dir.NONE, "o stack a 0.60/0.60 está bem acima do limiar de pressão")

	# Ruído de potenciômetro: ±0.02 em torno da diagonal, um eixo por evento.
	var jitter := [0.02, -0.02, 0.01, -0.03, 0.03, -0.01, 0.02, -0.02]
	for index in jitter.size():
		var dx: float = jitter[index]
		var dy: float = jitter[(index + 3) % jitter.size()]
		_push(adapter, 0.60 + dx, 0.60 + dy)
		eq(
			_direction(adapter),
			held,
			"ruído de %.2f/%.2f não pode virar um canto na trilha" % [dx, dy],
		)


func test_intencao_clara_ainda_troca_o_eixo() -> void:
	var adapter := GameInputAdapter.new()
	_push(adapter, 0.0, 0.9)
	eq(_direction(adapter), MoveIntent.Dir.DOWN, "descendo")

	# 21° fora do eixo vertical: é gesto, não ruído.
	_push(adapter, 0.8, 0.3)
	eq(_direction(adapter), MoveIntent.Dir.RIGHT, "o jogador virou de verdade")


func test_inverter_o_sentido_no_mesmo_eixo_e_imediato() -> void:
	var adapter := GameInputAdapter.new()
	_push(adapter, 0.9, 0.0)
	eq(_direction(adapter), MoveIntent.Dir.RIGHT, "indo para a direita")

	_push(adapter, -0.9, 0.0)
	eq(_direction(adapter), MoveIntent.Dir.LEFT, "meia-volta não passa pela trava de eixo")


func test_soltar_o_stick_continua_zerando_a_direcao() -> void:
	var adapter := GameInputAdapter.new()
	_push(adapter, 0.9, 0.0)
	ne(_direction(adapter), MoveIntent.Dir.NONE, "stick empurrado")

	_push(adapter, 0.10, 0.0)
	eq(
		_direction(adapter),
		MoveIntent.Dir.NONE,
		"abaixo de ANALOG_RELEASE_THRESHOLD a direção some, com trava ou sem",
	)
