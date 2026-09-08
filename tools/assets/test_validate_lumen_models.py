"""Validação de admissão GLB: fixtures binárias pequenas e independentes."""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

VALIDATOR = Path(__file__).with_name("validate_lumen_models.py")


def triangle_glb(index=2, mutate=None):
    binary = struct.pack("<9f3H", 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, index)
    document = {"asset": {"version": "2.0"}, "scene": 0,
        "scenes": [{"nodes": [0]}], "nodes": [{"name": "Lumen_Fixture", "children": [1]},
            {"name": "Hull", "mesh": 0}], "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
        "buffers": [{"byteLength": 42}], "bufferViews": [{"buffer": 0, "byteLength": 36},
            {"buffer": 0, "byteOffset": 36, "byteLength": 6}],
        "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}]}
    if mutate:
        mutate(document)
    encoded = json.dumps(document).encode()
    encoded += b" " * (-len(encoded) % 4)
    binary += b"\0" * (-len(binary) % 4)
    chunks = struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
    chunks += struct.pack("<II", len(binary), 0x004E4942) + binary
    return struct.pack("<4sII", b"glTF", 2, len(chunks) + 12) + chunks


class LumenAdmissionTest(unittest.TestCase):
    def module(self):
        self.assertTrue(VALIDATOR.is_file(), "falta o gate de admissão GLB")
        spec = importlib.util.spec_from_file_location("qix_glb", VALIDATOR)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_an_index_outside_the_position_accessor_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "índice"):
            self.module().inspect_glb(triangle_glb(index=3))

    def test_triangle_budget_counts_every_visible_mesh_instance(self):
        def two_instances(doc):
            doc["nodes"].append({"name": "Hull2", "mesh": 0})
            doc["nodes"][0]["children"].append(2)
        report = self.module().inspect_glb(triangle_glb(mutate=two_instances))
        self.assertEqual(report["triangles"], 2)

    def fixture_manifest(self, root):
        path = root / "assets/models/lumen/fixture.glb"
        path.parent.mkdir(parents=True)
        data = triangle_glb()
        path.write_bytes(data)
        return {"original_geometry": True, "external_textures": [], "assets": [
            {"path": "assets/models/lumen/fixture.glb", "bytes": len(data),
                "sha256": hashlib.sha256(data).hexdigest(), "triangles": 1, "components": ["Hull"]}]}

    def test_boolean_is_not_an_authored_triangle_count(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            manifest = self.fixture_manifest(root)
            manifest["assets"][0]["triangles"] = True
            with self.assertRaises(ValueError):
                self.module().validate_manifest(manifest, root, expected_ids=("fixture",))

    def test_valid_triangle_and_manifest_have_independent_expected_totals(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            report = self.module().validate_manifest(self.fixture_manifest(root), root, expected_ids=("fixture",))
        self.assertEqual(report["status"], "ok")
        self.assertEqual(report["triangles_total"], 1)
        self.assertEqual(report["assets"][0]["nodes"], 2)
        self.assertEqual(report["assets"][0]["root"], "Lumen_Fixture")

    def test_corrupt_header_and_truncated_chunks_are_rejected(self):
        data = triangle_glb()
        for corrupt in (b"bad", b"oops" + data[4:], data[:-1], data + b"extra"):
            with self.subTest(length=len(corrupt)), self.assertRaises(ValueError):
                self.module().inspect_glb(corrupt)

    def test_accessor_cannot_escape_its_view(self):
        data = triangle_glb(mutate=lambda doc: doc["accessors"][0].update({"byteOffset": 4}))
        with self.assertRaisesRegex(ValueError, "bufferView"):
            self.module().inspect_glb(data)

    def test_external_buffer_and_image_uris_are_rejected(self):
        for mutate in (lambda doc: doc["buffers"][0].update({"uri": "external.bin"}),
                lambda doc: doc.update({"images": [{"uri": "https://example.invalid/texture.png"}]})):
            with self.subTest(mutate=mutate), self.assertRaises(ValueError):
                self.module().inspect_glb(triangle_glb(mutate=mutate))

    def test_cyclic_nodes_and_nonfinite_transforms_are_rejected(self):
        for mutate in (lambda doc: doc["nodes"][1].update({"children": [0]}),
                lambda doc: doc["nodes"][0].update({"translation": [float("nan"), 0, 0]})):
            with self.subTest(mutate=mutate), self.assertRaises(ValueError):
                self.module().inspect_glb(triangle_glb(mutate=mutate))

    def test_hash_counts_components_and_paths_are_verified(self):
        for key, value in (("sha256", "0" * 64), ("triangles", 2), ("bytes", 1),
                ("components", ["wrong"]), ("path", "../fixture.glb")):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                manifest = self.fixture_manifest(root)
                manifest["assets"][0][key] = value
                with self.assertRaises(ValueError):
                    self.module().validate_manifest(manifest, root, expected_ids=("fixture",))

    def test_missing_and_duplicate_assets_are_rejected(self):
        for duplicate in (False, True):
            with self.subTest(duplicate=duplicate), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                manifest = self.fixture_manifest(root)
                manifest["assets"] = manifest["assets"] * 2 if duplicate else []
                with self.assertRaises(ValueError):
                    self.module().validate_manifest(manifest, root, expected_ids=("fixture",))

    def test_symlink_cannot_export_admission_outside_project(self):
        with tempfile.TemporaryDirectory() as folder, tempfile.TemporaryDirectory() as external:
            root = Path(folder)
            manifest = self.fixture_manifest(root)
            asset = root / manifest["assets"][0]["path"]
            outside = Path(external) / "fixture.glb"
            outside.write_bytes(asset.read_bytes())
            asset.unlink()
            asset.symlink_to(outside)
            with self.assertRaisesRegex(ValueError, "symlink"):
                self.module().validate_manifest(manifest, root, expected_ids=("fixture",))


if __name__ == "__main__":
    unittest.main()
