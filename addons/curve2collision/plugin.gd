@tool
extends EditorPlugin

## CurveCollision2D は curve_collision_2d.gd 側で
##   class_name CurveCollision2D
##   @icon("res://addons/curve2collision/icon.svg")
## として登録済みなので、ここで add_custom_type を呼ぶ必要はない。
## (両方書くと同名クラスの二重登録になり、Godot が警告を出す)
##
## このスクリプトは、将来インスペクタ拡張やビューポート用ギズモを
## 追加するときの受け皿として残してある。


func _enter_tree() -> void:
	pass


func _exit_tree() -> void:
	pass
