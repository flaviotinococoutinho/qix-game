@tool
@icon("res://addons/curve2collision/icon.svg")
extends Path2D
class_name CurveCollision2D

## 使い方:
## 1. StaticBody2D / Area2D などの子としてこのノードを追加する
## 2. いつも通り曲線を描く(カーブポイントを追加・編集)
## 3. thickness(太さ)を設定するだけで、太さを持った
##    CollisionPolygon2D が自動生成・自動更新される
## 4. 閉じた枠を作りたい場合は closed_loop を ON にする
##
## 形状の生成には Godot 内蔵の Geometry2D のポリゴンオフセット(Clipper)を
## 使用している。太さは常に一定で、急カーブでの自己交差はライブラリ側が
## 正しく解消するため、太さが痩せるような歪みは発生しない。

@export var thickness: float = 32.0:
	set(value):
		thickness = max(value, 0.1)
		_regenerate()

@export var closed_loop: bool = false:
	set(value):
		closed_loop = value
		_regenerate()

## 曲線を直線に分解する精度。小さいほど滑らかだが頂点数が増える
@export var tolerance_degrees: float = 4.0:
	set(value):
		tolerance_degrees = max(value, 0.1)
		_regenerate()

## 芯線(オフセット前の曲線)の頂点数の上限。これを超える分は間引かれる。
## 生成後のポリゴンは角の丸め処理により、これより多い頂点を持つことがある
@export var max_vertices: int = 120:
	set(value):
		max_vertices = max(value, 6)
		_regenerate()

## 角の処理方法。Round=丸め / Square=面取り / Miter=尖らせる
@export_enum("Round", "Square", "Miter") var join_type: int = 0:
	set(value):
		join_type = value
		_regenerate()

## 端の処理方法。Round=丸め / Square=はみ出して四角 / Butt=切り落とし
## (closed_loop が ON のときは無視される)
@export_enum("Round", "Square", "Butt") var end_type: int = 0:
	set(value):
		end_type = value
		_regenerate()

## OFF にすると曲線を編集しても自動更新されなくなる(重い曲線用)
@export var auto_update: bool = true

## チェックを入れると強制的に再生成する(手動更新用トリガー)
@export var regenerate_now: bool = false:
	set(value):
		if value:
			_regenerate()
		regenerate_now = false

const COLLISION_NAME_PREFIX := "GeneratedCollision"

var _generation_failed: bool = false


func _ready() -> void:
	if curve and not curve.changed.is_connected(_on_curve_changed):
		curve.changed.connect(_on_curve_changed)
	_regenerate()


func _on_curve_changed() -> void:
	if auto_update:
		_regenerate()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not curve or curve.point_count < 2:
		warnings.append("曲線に2つ以上の点を追加してください。")
	if not (get_parent() is CollisionObject2D):
		warnings.append("親ノードが StaticBody2D / Area2D などの CollisionObject2D 系でないと、生成されたコリジョンは機能しません。")
	if _generation_failed:
		warnings.append("コリジョン形状を生成できませんでした。Thickness が曲線の大きさに対して極端でないか確認してください。")
	return warnings


## 生成先の親ノード。
## CollisionPolygon2D は CollisionObject2D 系(StaticBody2D, Area2D など)の
## 直接の子でないと衝突判定として機能しないため、親がその系統なら親の子として作る。
func _get_target_parent() -> Node:
	var parent: Node = get_parent()
	return parent if parent is CollisionObject2D else self


func _regenerate() -> void:
	_generation_failed = false

	if not curve or curve.point_count < 2:
		_apply_polygons([])
		return

	# 曲線を直線の点列に変換(カーブが急なところほど点が増える賢い分割)
	var raw_points: PackedVector2Array = curve.tessellate(5, tolerance_degrees)
	if raw_points.size() < 2:
		_apply_polygons([])
		return

	var points: PackedVector2Array = _decimate(raw_points, max_vertices)
	if points.size() < 2:
		_apply_polygons([])
		return

	var half: float = thickness / 2.0
	var shapes: Array[PackedVector2Array] = []

	if closed_loop:
		shapes = _build_ring(points, half)
	else:
		shapes.assign(Geometry2D.offset_polyline(points, half, _join_const(), _end_const()))

	if shapes.is_empty():
		_generation_failed = true

	_apply_polygons(shapes)
	update_configuration_warnings()


## 閉じた曲線を、外周と内周を持つリング状のポリゴンにする。
## CollisionPolygon2D は穴を直接表現できないため、外周と内周を
## 継ぎ目(スリット)でつないだ一続きのポリゴンとして返す。
func _build_ring(points: PackedVector2Array, half: float) -> Array[PackedVector2Array]:
	var outer_list: Array = Geometry2D.offset_polygon(points, half, _join_const())
	var inner_list: Array = Geometry2D.offset_polygon(points, -half, _join_const())

	var result: Array[PackedVector2Array] = []
	if outer_list.is_empty():
		return result

	var outer: PackedVector2Array = outer_list[0]

	# 内側が消えた(太さが図形より大きい)場合は、塗りつぶしの塊として扱う
	if inner_list.is_empty():
		result.append(outer)
		return result

	var inner: PackedVector2Array = inner_list[0]
	result.append(_stitch_ring(outer, inner))
	return result


func _stitch_ring(outer: PackedVector2Array, inner: PackedVector2Array) -> PackedVector2Array:
	# 内周を、外周の始点に最も近い点から始まるように回転させる(継ぎ目を最短にする)
	var best_index: int = 0
	var best_distance: float = INF
	for i in range(inner.size()):
		var d: float = outer[0].distance_squared_to(inner[i])
		if d < best_distance:
			best_distance = d
			best_index = i

	var rotated: PackedVector2Array = []
	for i in range(inner.size()):
		rotated.append(inner[(best_index + i) % inner.size()])

	# 外周と内周の回転方向を逆にすることで、内側が穴として抜ける
	if Geometry2D.is_polygon_clockwise(outer) == Geometry2D.is_polygon_clockwise(rotated):
		rotated.reverse()

	var ring: PackedVector2Array = []
	ring.append_array(outer)
	ring.append(outer[0])
	ring.append_array(rotated)
	ring.append(rotated[0])
	return ring


## 生成されたポリゴン群を、必要な数だけ CollisionPolygon2D の子ノードに反映する
func _apply_polygons(shapes: Array[PackedVector2Array]) -> void:
	var target_parent: Node = _get_target_parent()
	if not is_instance_valid(target_parent):
		return

	var existing: Array[CollisionPolygon2D] = []
	for child in target_parent.get_children():
		if child is CollisionPolygon2D and String(child.name).begins_with(COLLISION_NAME_PREFIX) \
				and not child.is_queued_for_deletion():
			existing.append(child)

	# 足りない分を作る
	while existing.size() < shapes.size():
		var polygon_node := CollisionPolygon2D.new()
		polygon_node.name = COLLISION_NAME_PREFIX if existing.is_empty() else "%s%d" % [COLLISION_NAME_PREFIX, existing.size() + 1]
		target_parent.add_child(polygon_node)
		if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			polygon_node.owner = get_tree().edited_scene_root
		existing.append(polygon_node)

	# 余った分を削除する
	while existing.size() > shapes.size():
		var extra: CollisionPolygon2D = existing.pop_back()
		extra.queue_free()

	for i in range(shapes.size()):
		existing[i].polygon = shapes[i]


func _join_const() -> int:
	match join_type:
		1: return Geometry2D.JOIN_SQUARE
		2: return Geometry2D.JOIN_MITER
		_: return Geometry2D.JOIN_ROUND


func _end_const() -> int:
	match end_type:
		1: return Geometry2D.END_SQUARE
		2: return Geometry2D.END_BUTT
		_: return Geometry2D.END_ROUND


func _decimate(points: PackedVector2Array, max_count: int) -> PackedVector2Array:
	if points.size() <= max_count:
		return points
	var result: PackedVector2Array = []
	var last_index: int = points.size() - 1
	var step: float = float(last_index) / float(max_count - 1)
	var f: float = 0.0
	while f <= float(last_index) + 0.0001:
		result.append(points[int(round(min(f, last_index)))])
		f += step
	return result
