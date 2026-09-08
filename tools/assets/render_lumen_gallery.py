"""Render de inspeção da biblioteca editável pelo MCP Blender, sem sobrescrever fonte."""
import bpy
import os
from pathlib import Path
from mathutils import Vector

project = Path(os.environ["QIX_PROJECT_ROOT"])
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 960
scene.render.resolution_y = 660
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
world = bpy.data.worlds.new("Inspection environment")
world.use_nodes = True
background = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
background.inputs[0].default_value = (0.012, 0.022, 0.035, 1)
background.inputs[1].default_value = 0.35
scene.world = world
target = Vector((3, 0, -1.5))
bpy.ops.object.camera_add(location=(3, -14, 1.0))
camera = bpy.context.object
camera.rotation_euler = (target-camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 9.0
scene.camera = camera
for name, location, color, energy, size in [
    ("Key", (-2, -5, 6), (0.68, 0.89, 1), 1600, 5),
    ("Warm rim", (7, -1, 3), (1, 0.36, 0.18), 1000, 4),
    ("Fill", (3, -5, -4), (0.22, 1, 0.78), 600, 3),
]:
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.object
    light.name = name
    light.data.color, light.data.energy, light.data.shape, light.data.size = color, energy, "DISK", size
    light.rotation_euler = (target-light.location).to_track_quat("-Z", "Y").to_euler()
scene.view_settings.view_transform = "AgX"
path = project / "build/modernization/lumen-models-gallery.png"
scene.render.filepath = str(path)
bpy.ops.render.render(write_still=True)
result = {"render": str(path), "width": 960, "height": 660, "blender": bpy.app.version_string}
