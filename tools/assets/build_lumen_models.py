"""Biblioteca original Lumen, construída pelo MCP oficial do Blender.

Execute via blender_mcp_job.py; QIX_PROJECT_ROOT aponta para o checkout.
Geometria própria, materiais PBR sem texturas externas e componentes animáveis.
Frente em -Y no Blender (+Z no glTF/Godot); pivô central, dimensão ~2 unidades.
"""
import bpy
import hashlib
import json
import math
import os
from pathlib import Path

project = Path(os.environ["QIX_PROJECT_ROOT"])
out = project / "assets/models/lumen"
source = project / "tools/assets/source"
out.mkdir(parents=True, exist_ok=True)
source.mkdir(parents=True, exist_ok=True)
(source / ".gdignore").touch()
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, rgb, metallic=0.0, roughness=0.35, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    p = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if p is None:
        p = mat.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
        output = mat.node_tree.nodes.new("ShaderNodeOutputMaterial")
        mat.node_tree.links.new(p.outputs["BSDF"], output.inputs["Surface"])
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Roughness"].default_value = roughness
    p.inputs["Emission Color"].default_value = (*rgb, 1)
    p.inputs["Emission Strength"].default_value = emission
    return mat


carbon = material("Lumen • graphite titanium", (0.018, 0.035, 0.05), 0.7)
ceramic = material("Lumen • pearl ceramic", (0.7, 0.85, 0.87), 0.28)
teal = material("Lumen • ion cyan", (0.03, 0.85, 0.67), 0.35, emission=1.0)
gold = material("Lumen • warm brass", (0.85, 0.45, 0.1), 0.6)
pink = material("Lumen • hostile plasma", (0.95, 0.035, 0.16), 0.25, emission=1.0)
ember = material("Lumen • amber plasma", (1.0, 0.28, 0.025), 0.1, emission=1.0)
white = material("Lumen • hot lens", (0.87, 1.0, 1.0), emission=0.8)
violet = material("Lumen • spectral alloy", (0.2, 0.07, 0.4), 0.65)
roots = []
root = None


def actor(name):
    global root
    root = bpy.data.objects.new("Lumen_" + name, None)
    root["lumen_asset_id"] = name.lower()
    bpy.context.collection.objects.link(root)
    roots.append(root)
    return root


def finish(name, mat):
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    obj.parent = root
    return obj


def ico(name, loc, scale, mat, subdivisions=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1, location=loc)
    obj = finish(name, mat)
    obj.scale = scale
    return obj


def box(name, loc, scale, mat, bevel=0.08):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = finish(name, mat)
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = obj.modifiers.new("Manufactured edge", "BEVEL")
    mod.width, mod.segments = bevel, 2
    obj.modifiers.new("Surface normals", "WEIGHTED_NORMAL")
    return obj


def ring(name, loc, radius, tube, mat):
    bpy.ops.mesh.primitive_torus_add(major_segments=40, minor_segments=6,
        location=loc, rotation=(math.pi/2, 0, 0), major_radius=radius, minor_radius=tube)
    return finish(name, mat)


def cone(name, loc, radius, depth, mat, rotation=(0, 0, 0), vertices=6):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=radius*0.15,
        depth=depth, location=loc, rotation=rotation)
    return finish(name, mat)


actor("Surveyor")
ico("Housing", (0, 0, 0), (0.48, 0.26, 0.8), carbon, 2)
ico("Ceramic carapace", (0, -0.12, 0.12), (0.39, 0.22, 0.64), ceramic)
ico("Core", (0, -0.32, 0.24), (0.22, 0.13, 0.3), teal, 2)
ring("Lens guard", (0, -0.3, 0.24), 0.28, 0.035, carbon)
for side, name in [(-1, "Left"), (1, "Right")]:
    wing = box("Wing" + name, (side*0.64, 0.015, -0.12), (0.65, 0.24, 0.42), ceramic)
    wing.rotation_euler[1] = side * -0.28
    box("Rail" + name, (side*0.66, -0.14, -0.12), (0.46, 0.04, 0.08), teal, 0.015)
    cone("Thruster" + name, (side*0.49, 0.03, -0.53), 0.16, 0.36, carbon)
    ico("Exhaust" + name, (side*0.49, 0.03, -0.75), (0.10, 0.10, 0.25), teal)
cone("Cartography stylus", (0, -0.02, 0.88), 0.12, 0.32, gold)

actor("Core")
ico("Housing", (0, 0, 0), (0.68, 0.38, 0.68), carbon, 2)
ico("Core", (0, -0.33, 0), (0.42, 0.22, 0.42), pink, 2)
ico("Eye", (0, -0.55, 0), (0.11, 0.05, 0.24), white)
ring("Crown", (0, -0.15, 0), 0.85, 0.065, gold)
ring("Inner orbit", (0, -0.3, 0), 0.52, 0.035, violet)
for i in range(6):
    angle = i*math.tau/6
    x, z = math.sin(angle), math.cos(angle)
    plate = ico("Petal%02d" % i, (x*0.72, -0.05, z*0.72), (0.22, 0.22, 0.49), violet)
    plate.rotation_euler[1] = angle
    ico("Plasma%02d" % i, (x*0.96, -0.12, z*0.96), (0.075, 0.065, 0.075), pink)

actor("Walker")
ico("Housing", (0, 0, 0), (0.58, 0.25, 0.48), carbon)
ico("Core", (0, -0.25, 0), (0.28, 0.12, 0.29), gold, 2)
for side in (-1, 1):
    for z in (-0.28, 0.28):
        leg = box("Leg%s%s" % (side, z), (side*0.58, 0.02, z), (0.48, 0.11, 0.1), ceramic, 0.025)
        leg.rotation_euler[1] = side*z
    ico("Antenna%s" % side, (side*0.23, -0.12, 0.58), (0.07, 0.07, 0.19), ember)

actor("Dart")
cone("Housing", (0, 0, 0.12), 0.28, 1.25, carbon, vertices=4)
cone("Core", (0, -0.08, 0.37), 0.14, 0.82, pink, vertices=4)
for side in (-1, 1):
    fin = box("Fin%s" % side, (side*0.29, 0, -0.28), (0.33, 0.1, 0.38), gold, 0.025)
    fin.rotation_euler[1] = side*0.45
ico("Exhaust", (0, 0, -0.65), (0.10, 0.10, 0.34), ember)

actor("Ember")
ico("Core", (0, 0, 0), (0.35, 0.22, 0.48), ember, 2)
ico("Heart", (0, -0.2, 0.08), (0.13, 0.08, 0.22), white)
ring("Crown", (0, 0.06, 0), 0.52, 0.045, gold)
for i in range(3):
    a = i*math.tau/3
    ico("Spark%d" % i, (math.sin(a)*0.59, 0, math.cos(a)*0.59), (0.10, 0.07, 0.10), ember)

actor("Beacon")
box("Housing", (0, 0.06, 0), (0.80, 0.16, 0.80), carbon)
ring("Crown", (0, -0.07, 0), 0.48, 0.04, gold)
ico("Core", (0, -0.25, 0), (0.24, 0.24, 0.38), teal)
for i in range(4):
    a = i*math.tau/4
    box("Receiver%d" % i, (math.sin(a)*0.51, -0.07, math.cos(a)*0.51), (0.13, 0.18, 0.13), ceramic, 0.025)

manifest = {"generator": "Blender official MCP / execute_blender_code_for_cli",
    "blender": bpy.app.version_string, "original_geometry": True, "external_textures": [], "assets": []}
for a in roots:
    bpy.ops.object.select_all(action="DESELECT")
    a.select_set(True)
    for obj in a.children_recursive:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = a
    path = out / (a["lumen_asset_id"] + ".glb")
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
        export_apply=True, export_animations=False, export_cameras=False, export_lights=False)
    triangles = 0
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in a.children_recursive:
        if obj.type == "MESH":
            evaluated = obj.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            mesh.calc_loop_triangles()
            triangles += len(mesh.loop_triangles)
            evaluated.to_mesh_clear()
    manifest["assets"].append({"path": str(path.relative_to(project)), "triangles": triangles,
        "components": [o.name for o in a.children_recursive], "bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
for i, a in enumerate(roots):
    a.location.x = (i % 3)*3.0
    a.location.z = -(i // 3)*3.0
bpy.ops.wm.save_as_mainfile(filepath=str(source / "lumen_actor_library.blend"))
(out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
result = manifest
