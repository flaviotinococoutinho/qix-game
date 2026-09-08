#!/usr/bin/env python3
"""Gate offline da biblioteca Lumen; subconjunto GLB estático usado pelo projeto.

Não substitui o validador Khronos integral nem a importação Godot. Orçamentos
independentes do manifesto impedem um arquivo alterar o próprio limite.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import struct
import sys

EXPECTED_IDS = ("surveyor", "core", "walker", "dart", "ember", "beacon")
MAX_BYTES = 500_000
MAX_TRIANGLES = 5_000
MAX_NODES = 128
COMPONENTS = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
    5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def integer(value, message):
    require(type(value) is int and value >= 0, message)
    return value


def reference(values, index, label):
    integer(index, f"índice inválido: {label}")
    require(index < len(values), f"índice fora do limite: {label}")
    return values[index]


def inspect_glb(data):
    require(12 <= len(data) <= MAX_BYTES, "GLB fora do orçamento de bytes")
    magic, version, length = struct.unpack_from("<4sII", data)
    require(magic == b"glTF" and version == 2 and length == len(data), "Cabeçalho GLB inválido")
    chunks, offset = [], 12
    while offset < len(data):
        require(offset + 8 <= len(data), "Cabeçalho de chunk truncado")
        size, kind = struct.unpack_from("<II", data, offset)
        offset += 8
        require(size % 4 == 0 and offset + size <= len(data), "Chunk truncado ou desalinhado")
        chunks.append((kind, data[offset:offset + size]))
        offset += size
    require([kind for kind, _ in chunks] == [0x4E4F534A, 0x004E4942], "GLB exige JSON e BIN únicos")
    document = json.loads(chunks[0][1])
    require(isinstance(document, dict) and document.get("asset", {}).get("version") == "2.0", "Versão glTF inválida")
    require(not document.get("extensionsRequired"), "Extensão glTF obrigatória não suportada")
    require(not document.get("animations") and not document.get("skins"), "Biblioteca estática não admite animação/skin")
    buffers = document.get("buffers", [])
    require(len(buffers) == 1 and "uri" not in buffers[0], "Buffer externo ou múltiplo não permitido")
    binary = chunks[1][1]
    byte_length = integer(buffers[0].get("byteLength"), "byteLength inválido")
    require(byte_length <= len(binary) <= byte_length + 3, "BIN diverge do buffer declarado")
    require(all("uri" not in item for item in document.get("images", [])), "Imagem externa não permitida")
    views = document.get("bufferViews", [])
    for view in views:
        require(view.get("buffer") == 0, "bufferView referencia buffer inexistente")
        start = integer(view.get("byteOffset", 0), "Offset de bufferView inválido")
        size = integer(view.get("byteLength"), "Tamanho de bufferView inválido")
        require(size > 0 and start + size <= byte_length, "bufferView fora do BIN")
    accessors = document.get("accessors", [])
    values = []
    for accessor in accessors:
        require(not accessor.get("sparse"), "Accessor sparse não suportado por este gate")
        view = reference(views, accessor.get("bufferView"), "bufferView de accessor")
        kind, width = accessor.get("componentType"), WIDTHS.get(accessor.get("type"))
        require(kind in COMPONENTS and width is not None, "Formato de accessor não suportado")
        code, size = COMPONENTS[kind]
        count = integer(accessor.get("count"), "Contagem de accessor inválida")
        require(count > 0, "Accessor vazio")
        start = integer(accessor.get("byteOffset", 0), "Offset de accessor inválido")
        stride = integer(view.get("byteStride", width * size), "Stride inválido")
        require(stride >= width * size and stride <= 252 and stride % size == 0,
            "Stride de accessor inválido")
        require(start % size == 0 and (view.get("byteOffset", 0) + start) % size == 0,
            "Accessor desalinhado")
        require(start + (count - 1) * stride + width * size <= view["byteLength"], "Accessor fora do bufferView")
        rows = [struct.unpack_from("<" + code * width, binary, view.get("byteOffset", 0) + start + i * stride)
            for i in range(count)]
        require(all(math.isfinite(v) for row in rows for v in row), "Accessor contém valor não finito")
        values.append(rows)
    meshes = document.get("meshes", [])
    require(meshes, "GLB sem meshes")
    mesh_triangles = []
    for mesh in meshes:
        triangles = 0
        require(mesh.get("primitives"), "Mesh sem primitivas")
        for primitive in mesh["primitives"]:
            require(primitive.get("mode", 4) == 4, "Somente primitivas TRIANGLES são admitidas")
            attributes = primitive.get("attributes", {})
            position_id = attributes.get("POSITION")
            positions = reference(accessors, position_id, "POSITION")
            require(positions.get("type") == "VEC3" and positions.get("componentType") == 5126, "POSITION deve ser VEC3 float")
            for attribute_id in attributes.values():
                attribute = reference(accessors, attribute_id, "atributo")
                require(attribute["count"] == positions["count"], "Atributos com contagens divergentes")
            if "indices" in primitive:
                indices = reference(accessors, primitive["indices"], "accessor de índices")
                require(indices.get("type") == "SCALAR" and indices.get("componentType") in (5121, 5123, 5125), "Formato de índices inválido")
                require(all(row[0] < positions["count"] for row in values[primitive["indices"]]), "índice de vértice fora de POSITION")
                count = indices["count"]
            else:
                count = positions["count"]
            require(count % 3 == 0, "Contagem não forma triângulos completos")
            if "material" in primitive:
                reference(document.get("materials", []), primitive["material"], "material")
            triangles += count // 3
        mesh_triangles.append(triangles)
    require(0 < sum(mesh_triangles) <= MAX_TRIANGLES, "GLB fora do orçamento de triângulos")
    nodes = document.get("nodes", [])
    require(0 < len(nodes) <= MAX_NODES, "GLB fora do orçamento de nodes")
    scene = reference(document.get("scenes", []), document.get("scene", 0), "scene")
    roots = scene.get("nodes", [])
    require(len(roots) == 1, "Ator exige uma única raiz")
    visited = set()
    def visit(index):
        node = reference(nodes, index, "node")
        require(index not in visited, "Hierarquia contém ciclo ou múltiplos pais")
        visited.add(index)
        for transform, width in (("matrix", 16), ("translation", 3), ("rotation", 4), ("scale", 3)):
            if transform in node:
                require(len(node[transform]) == width and all(type(v) in (float, int) and math.isfinite(v)
                    for v in node[transform]), "Transform inválido")
        if "mesh" in node:
            reference(meshes, node["mesh"], "mesh")
        for child in node.get("children", []):
            visit(child)
    visit(roots[0])
    require(len(visited) == len(nodes), "GLB contém nodes fora da cena do ator")
    triangles = sum(mesh_triangles[node["mesh"]] for node in nodes if "mesh" in node)
    require(0 < triangles <= MAX_TRIANGLES, "Instâncias fora do orçamento de triângulos")
    return {"triangles": triangles, "nodes": len(nodes), "meshes": len(meshes),
        "root": nodes[roots[0]].get("name"),
        "components": [node.get("name") for index, node in enumerate(nodes) if index != roots[0]]}


def validate_manifest(manifest, project_root, expected_ids=EXPECTED_IDS):
    require(isinstance(manifest, dict) and isinstance(manifest.get("assets"), list), "Manifesto sem assets")
    require(manifest.get("original_geometry") is True and manifest.get("external_textures") == [], "Proveniência do manifesto incompatível")
    root = Path(project_root).resolve()
    expected = {f"assets/models/lumen/{name}.glb": name for name in expected_ids}
    seen, reports = set(), []
    for asset in manifest["assets"]:
        raw = asset.get("path", "")
        require(isinstance(raw, str) and raw in expected and raw not in seen, "Caminho/ID inesperado ou duplicado")
        path = (root / PurePosixPath(raw)).resolve()
        require(path.is_relative_to(root), "Asset escapa do projeto por symlink")
        require(path.stat().st_size <= MAX_BYTES, f"Asset fora do orçamento de bytes: {raw}")
        integer(asset.get("bytes"), "Bytes do manifesto devem ser inteiros")
        integer(asset.get("triangles"), "Triângulos do manifesto devem ser inteiros")
        data = path.read_bytes()
        require(len(data) == asset.get("bytes"), f"Tamanho divergente: {raw}")
        digest = hashlib.sha256(data).hexdigest()
        require(digest == asset.get("sha256"), f"SHA-256 divergente: {raw}")
        metrics = inspect_glb(data)
        require(metrics["triangles"] == asset.get("triangles"), f"Triângulos divergentes: {raw}")
        components = asset.get("components", [])
        require(isinstance(components, list) and sorted(metrics["components"]) == sorted(components), f"Componentes divergentes: {raw}")
        require(metrics["root"] == "Lumen_" + expected[raw].capitalize(), f"Raiz inesperada: {raw}")
        reports.append({"id": expected[raw], "path": raw, "bytes": len(data), "sha256": digest, **metrics})
        seen.add(raw)
    require(seen == set(expected), "Manifesto não contém o conjunto completo esperado")
    return {"status": "ok", "validation": "lumen-static-glb-v1", "assets": reports,
        "bytes_total": sum(item["bytes"] for item in reports),
        "triangles_total": sum(item["triangles"] for item in reports)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args(argv)
    try:
        path = args.manifest or args.project_root / "assets/models/lumen/manifest.json"
        print(json.dumps(validate_manifest(json.loads(path.read_text()), args.project_root), indent=2))
        return 0
    except (OSError, ValueError, TypeError, KeyError, struct.error) as error:
        print(json.dumps({"status": "failed", "error": str(error)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
