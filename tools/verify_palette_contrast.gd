extends SceneTree
## Uso: Godot --headless --path . --script res://tools/verify_palette_contrast.gd
##
## Imprime a separação medida entre estados do campo — paleta padrão e cada rodada autorada — e
## falha se algum par piorar em relação ao piso registrado em `PaletteContrast.PAIR_FLOOR`.
## Pares abaixo da meta WCAG aparecem marcados, mas não derrubam o comando: são dívida conhecida
## e registrada em `docs/ART_DIRECTION.md`, não regressão desta execução.

const PaletteContrast := preload("res://tools/palette_contrast.gd")
const CAMPAIGN_PATH := "res://content/campaigns/main_campaign.tres"


func _initialize() -> void:
	var failures := PackedStringArray()
	var below_target := 0
	var palettes := _palettes()
	for entry in palettes:
		var measurement: Dictionary = PaletteContrast.measure(entry["visual"])
		_print_measurement("%s — campo" % entry["label"], measurement)
		below_target += measurement["below_target"].size()
		for regression in PaletteContrast.regressions(measurement):
			failures.append("%s — %s" % [entry["label"], regression])

	# O cursor sai numa tabela própria porque é outra pergunta: "onde está a borda" é uma leitura
	# do campo, "onde eu estou" é uma leitura da silhueta contra o chão em que ela pousa.
	for entry in palettes:
		var measurement: Dictionary = PaletteContrast.measure_cursor(entry["visual"])
		_print_measurement("%s — cursor sobre o chão" % entry["label"], measurement)
		below_target += measurement["below_target"].size()
		for regression in PaletteContrast.regressions(measurement):
			failures.append("%s — %s" % [entry["label"], regression])

	print("")
	print("meta WCAG 2.1 SC 1.4.11: %.1f:1" % PaletteContrast.TARGET_RATIO)
	print("pares abaixo da meta: %d (dívida registrada, não regressão)" % below_target)
	if failures.is_empty():
		print("catraca: nenhum par abaixo do piso registrado")
		quit(0)
		return
	for failure in failures:
		printerr("REGRESSÃO: " + failure)
	quit(1)


## A paleta padrão entra na medição porque é o que um host antigo desenha quando `visual` é nulo.
func _palettes() -> Array[Dictionary]:
	var entries: Array[Dictionary] = [
		{"label": "paleta padrão", "visual": RoundVisualDefinition.new()},
	]
	var campaign := load(CAMPAIGN_PATH) as CampaignDefinition
	if campaign == null:
		printerr("campanha ausente em " + CAMPAIGN_PATH)
		return entries
	for content in campaign.rounds:
		if content == null or content.visual == null:
			continue
		entries.append({"label": String(content.round_id), "visual": content.visual})
	return entries


func _print_measurement(label: String, measurement: Dictionary) -> void:
	print("")
	print("== %s ==" % label)
	print("  par                        pior  visão          tri   pro   deu   tri3  cromía  meta")
	for entry in measurement["pairs"]:
		var by_vision: Dictionary = entry["by_vision"]
		print("  %-24s %6.2f  %-13s %5.2f %5.2f %5.2f %5.2f  %5.0f%%  %s" % [
			entry["pair"],
			entry["worst_ratio"],
			entry["worst_vision"],
			by_vision["tricromata"],
			by_vision["protanopia"],
			by_vision["deuteranopia"],
			by_vision["tritanopia"],
			entry["chroma_retention"] * 100.0,
			"ok" if entry["meets_target"] else "ABAIXO",
		])
	print("  pior par: %s a %.2f:1" % [measurement["worst_pair"], measurement["worst_ratio"]])
