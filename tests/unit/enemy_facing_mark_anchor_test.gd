extends TestCase
## Defende a âncora das marcas de rumo de `QixEnemyView`: elas nascem *na* borda do anel de tinta.
##
## O anel da ADR-0011 é um losango. As marcas de rumo — a proa de PURSUIT e a haste de SWEEP —
## partiam de `_facing * RIM_RADIUS`, que é o ponto da borda de um *círculo* de raio 5. As duas
## geometrias só coincidem nas quatro direções axiais, e `BossBehaviorController` anda em
## dezasseis: nas outras doze a marca nascia fora do contorno, com folga de até 1,46 px — mais do
## que a espessura de 1 px do próprio anel. O efeito não é sutil no campo 240×320: em vez de uma
## proa saindo da silhueta, o jogador via um traço solto ao lado dela, exatamente no rumo em que
## precisa de ler para onde a ameaça está comprometida antes que ela alcance a trilha.
##
## A guarda é geométrica, não pictórica: `rim_point` é a mesma função que `_draw` chama, então o
## que este teste mede é o que a tela desenha. Falha se alguém voltar a tratar o anel como
## círculo, ou trocar o losango por outra forma sem trazer a âncora junto.

const BossBehaviorProfileScript = preload("res://game/enemies/boss_behavior_profile.gd")
const BossBehaviorControllerScript = preload("res://game/enemies/boss_behavior_controller.gd")

## Tolerância de ponto flutuante para "está sobre a borda". Duas ordens de grandeza abaixo do
## pixel, portanto invisível, mas apertada o bastante para recusar a fórmula circular.
const EPSILON := 0.0001


## Distância de Chebyshev-dual do ponto ao centro na métrica do losango: |x| + |y| vale `radius`
## exatamente sobre a borda, menos dentro, mais fora.
func _diamond_span(point: Vector2) -> float:
	return absf(point.x) + absf(point.y)


func _facing_of(index: int) -> Vector2:
	return Vector2(
		float(BossBehaviorControllerScript.DIRECTION_X[index]) / 256.0,
		float(BossBehaviorControllerScript.DIRECTION_Y[index]) / 256.0,
	).normalized()


func test_a_ancora_pousa_na_borda_do_losango_nas_dezasseis_direcoes() -> void:
	for index in 16:
		var facing := _facing_of(index)
		var anchor := QixEnemyView.rim_point(facing, QixEnemyView.RIM_RADIUS)
		ok(
			absf(_diamond_span(anchor) - QixEnemyView.RIM_RADIUS) < EPSILON,
			"direção %d: a âncora está sobre o losango do anel (|x|+|y| = %f)" % [
				index, _diamond_span(anchor),
			],
		)
		ok(
			anchor.normalized().dot(facing) > 0.9999,
			"direção %d: a âncora aponta no rumo observado, não noutro" % index,
		)
		ok(
			anchor.length() <= QixEnemyView.RIM_RADIUS + EPSILON,
			"direção %d: a âncora nunca cai fora do raio máximo do anel" % index,
		)


func test_a_formula_circular_soltava_a_marca_do_contorno_e_a_nova_nao() -> void:
	# Mede a regressão que motivou a mudança, para que ela não volte por descuido: a folga da
	# fórmula antiga contra zero folga da nova. O pior caso é a diagonal (índices 2, 6, 10, 14).
	var worst_old := 0.0
	var worst_new := 0.0
	for index in 16:
		var facing := _facing_of(index)
		var edge := QixEnemyView.rim_point(facing, QixEnemyView.RIM_RADIUS)
		var circular := facing * QixEnemyView.RIM_RADIUS
		# "Folga" é a distância radial entre onde a marca nasce e onde o contorno realmente passa.
		worst_old = maxf(worst_old, circular.length() - edge.length())
		worst_new = maxf(worst_new, absf(_diamond_span(edge) - QixEnemyView.RIM_RADIUS))
	var ring_thickness := QixEnemyView.RIM_RADIUS - QixEnemyView.BODY_RADIUS
	ok(
		worst_old > ring_thickness,
		"a folga da fórmula circular (%f px) excedia a espessura do anel (%f px)" % [
			worst_old, ring_thickness,
		],
	)
	ok(worst_new < EPSILON, "a âncora atual não abre folga em nenhuma das dezasseis direções")


func test_direcao_degenerada_nao_produz_nan() -> void:
	# `_facing` nasce de uma normalização; um vetor nulo devolveria NaN numa divisão ingénua e
	# NaN em `draw_line` apaga a marca inteira sem erro no log.
	var anchor := QixEnemyView.rim_point(Vector2.ZERO, QixEnemyView.RIM_RADIUS)
	eq(anchor, Vector2.ZERO, "direção nula colapsa no centro em vez de virar NaN")
	ok(not is_nan(anchor.x) and not is_nan(anchor.y), "a âncora é sempre um número")


func test_a_silhueta_publica_a_ancora_do_rumo_observado_sem_mutar_a_simulacao() -> void:
	var rules := GameRules.new()
	var profile = BossBehaviorProfileScript.new()
	profile.pattern = BossBehaviorProfileScript.Pattern.PURSUIT
	rules.boss_behavior = profile
	rules.boss_turn_every_ticks = 0
	var definition := RoundDefinition.new()
	definition.field_width = 17
	definition.field_height = 13
	definition.player_spawn = Vector2i(8, 0)
	definition.boss_start = Vector2i(8, 6)
	var simulation := GameSimulation.new(rules, definition, 441)
	for _tick in 9:
		simulation.step(MoveIntent.none())
	var before := simulation.state_checksum()

	var view := QixEnemyView.new()
	view.sync(simulation)
	var geometry := view.silhouette_geometry()
	var anchor: Vector2 = geometry["mark_origin"]
	var facing: Vector2 = view.presentation_state()["facing"]
	ok(
		absf(_diamond_span(anchor) - QixEnemyView.RIM_RADIUS) < EPSILON,
		"a âncora publicada pousa no anel para o rumo que a simulação produziu",
	)
	ok(anchor.normalized().dot(facing) > 0.9999, "a âncora segue o mesmo rumo que a view observou")
	eq(simulation.state_checksum(), before, "ler a silhueta não toca no domínio (invariante 6)")
	view.free()
