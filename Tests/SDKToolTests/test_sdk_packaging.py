"""Archive tests use an independent committed input tree, never a mutable release checkout."""

import copy
import contextlib
import importlib.util
import io
import json
import shutil
import stat
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch


REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "Scripts"))
import forsetti_sdk as sdk


class PackagingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="forsetti-sdk-test path ")
        cls.repo = Path(cls.temporary.name) / "input repository"
        cls.repo.mkdir()
        for path in sdk.CANONICAL_PATHS + ("Package.swift", "version.txt", "Sources/ForsettiCore/ForsettiVersion.swift"):
            destination = cls.repo / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((REPO / path).read_bytes())
        cls.version = (cls.repo / "version.txt").read_text().strip()
        (cls.repo / "README.md").write_text(f"**Current Version: {cls.version}** <!-- x-release-please-version -->\n")
        (cls.repo / ".release-please-manifest.json").write_text(json.dumps({".": cls.version}))
        shutil.copytree(REPO / "XcodeTemplates", cls.repo / "XcodeTemplates")
        for path in sdk.SCRIPT_PATHS:
            destination = cls.repo / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text("#!/usr/bin/env bash\nexit 0\n")
            destination.chmod(0o755)
        for path in sdk.DOC_PATHS:
            destination = cls.repo / sdk.DOC_SOURCE_PATHS[path]
            destination.parent.mkdir(parents=True, exist_ok=True)
            if path == "Documentation/Source-References.md":
                destination.write_text("[Package.swift](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/Package.swift)\n")
            else:
                destination.write_text("SDK @SDK_VERSION@. Runtime @RUNTIME_REF@ (@RUNTIME_COMMIT@). [Policy](" + ("../" if path.startswith("Documentation/") else "") + "CONSUMPTION_POLICY.md).\n")
        sdk.run("git", "init", "--quiet", str(cls.repo))
        sdk.run("git", "config", "user.name", "SDK Test", cwd=cls.repo)
        sdk.run("git", "config", "user.email", "sdk-test@example.invalid", cwd=cls.repo)
        sdk.run("git", "add", ".", cwd=cls.repo)
        sdk.run("git", "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "Fixture", cwd=cls.repo)
        cls.tree = sdk.SourceTree(cls.repo)
        cls.runtime = {"packageName": "ForsettiFramework", "url": sdk.RUNTIME_URL, "ref": cls.tree.commit, "commit": cls.tree.commit, "remoteVerified": True}
        cls.requirements = sdk.validate_package(cls.tree.read("Package.swift"))
        cls.payload, cls.manifest = sdk.build_payload(cls.tree, cls.runtime, cls.version, cls.requirements)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def payload_copy(self):
        return copy.deepcopy(self.payload)

    def modes(self, payload):
        return {path: "0755" if path in sdk.SCRIPT_PATHS else "0644" for path in payload}

    def change_manifest(self, payload, change):
        manifest = sdk.load_json(payload["sdk-manifest.json"])
        change(manifest)
        payload["sdk-manifest.json"] = sdk.canonical_json(manifest)

    def test_curated_inventory_and_canonical_source_equality(self):
        result = sdk.validate_payload(self.payload, self.modes(self.payload), self.tree)
        self.assertEqual(result["sdk"]["releaseStatus"], "unverified-candidate")
        self.assertEqual(result["verification"], {"testedEnvironments": [], "checks": []})
        for path in sdk.CANONICAL_PATHS:
            self.assertEqual(self.payload[path], self.tree.read(path))
        self.assertNotIn("sdk-manifest.json", [item["path"] for item in result["inventory"]])
        self.assertFalse(any(path.startswith(("Sources/", "Tests/", "docs/", ".git/")) for path in self.payload))
        self.assertNotIn("Package.swift", self.payload)

    def test_repeated_packaging_is_byte_reproducible(self):
        rebuilt, manifest = sdk.build_payload(self.tree, self.runtime, self.version, self.requirements)
        first = sdk.archive_bytes(self.payload, self.version)
        second = sdk.archive_bytes(rebuilt, self.version)
        self.assertEqual(first, second)
        self.assertEqual(manifest, self.manifest)
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / f"Forsetti-SDK-{self.version}.zip"
            archive.write_bytes(first)
            checksum = Path(directory) / "SHA256SUMS"
            checksum.write_text(f"{sdk.digest(first)}  {archive.name}\n")
            sdk.verify_checksum(archive, checksum)
            payload, modes, _ = sdk.read_archive(archive)
            sdk.validate_payload(payload, modes, self.tree)

    def test_missing_required_files_are_rejected(self):
        for path in ("CONSUMPTION_POLICY.md", "Documentation/Public-API.md", sdk.SCRIPT_PATHS[2], sdk.TEMPLATE_ROOT + "/Forsetti App.xctemplate/AppModule.swift", "sdk-manifest.json"):
            with self.subTest(path=path):
                payload = self.payload_copy()
                del payload[path]
                with self.assertRaises(sdk.SDKError):
                    sdk.validate_payload(payload, self.modes(payload))

    def test_forbidden_extra_payloads_rejected_even_with_updated_inventory(self):
        for path in ("Sources/ForsettiCore/Runtime.swift", "Package.swift", "Tests/test.swift", "framework-policy.json", "docs/wiki.zip", "Scripts/extra.py", "XcodeTemplates/Project Templates/Forsetti/Extra.xctemplate/TemplateInfo.plist"):
            with self.subTest(path=path):
                payload = self.payload_copy()
                payload[path] = b"not allowed"
                self.change_manifest(payload, lambda manifest: manifest["inventory"].append({"path": path, "mode": "0644", "sha256": sdk.digest(payload[path])}))
                with self.assertRaises(sdk.SDKError):
                    sdk.validate_payload(payload, self.modes(payload))

    def test_hash_tampering_is_rejected(self):
        payload = self.payload_copy()
        payload["CONSUMPTION_POLICY.md"] += b"\nchanged"
        with self.assertRaisesRegex(sdk.SDKError, "inventory or hashes"):
            sdk.validate_payload(payload, self.modes(payload))

    def test_canonical_source_tampering_rejected_after_rehash(self):
        payload = self.payload_copy()
        payload["CONSUMPTION_POLICY.md"] += b"\nchanged"
        def change(manifest):
            for item in manifest["inventory"]:
                item["sha256"] = sdk.digest(payload[item["path"]])
            for item in manifest["provenance"]["canonicalFiles"]:
                item["sha256"] = sdk.digest(payload[item["sdkPath"]])
        self.change_manifest(payload, change)
        with self.assertRaisesRegex(sdk.SDKError, "differs from its recorded source input"):
            sdk.validate_payload(payload, self.modes(payload), self.tree)

    def test_product_mismatch_is_rejected(self):
        payload = self.payload_copy()
        self.change_manifest(payload, lambda manifest: manifest["products"].append({"name": "ForsettiModulesExample", "target": "ForsettiModulesExample", "dependencies": ["ForsettiCore"]}))
        with self.assertRaisesRegex(sdk.SDKError, "products/dependencies"):
            sdk.validate_payload(payload, self.modes(payload))
        source = self.tree.read("Package.swift").replace(b'products: [', b'products: [ .library(name: "ForsettiModulesExample", targets: ["ForsettiModulesExample"]),')
        with self.assertRaisesRegex(sdk.SDKError, "product/dependency contract"):
            sdk.validate_package(source)

    def test_runtime_version_ref_and_metadata_mismatch_rejected(self):
        with self.assertRaisesRegex(sdk.SDKError, "version/requirements"):
            sdk.build_payload(self.tree, self.runtime, "999.0.0", self.requirements)
        for ref in ("main", "v999.0.0", "deadbee"):
            payload = self.payload_copy()
            self.change_manifest(payload, lambda manifest: manifest["runtime"].update(ref=ref))
            with self.subTest(ref=ref), self.assertRaises(sdk.SDKError):
                sdk.validate_payload(payload, self.modes(payload))

    def test_clean_release_cannot_claim_unrun_checks(self):
        payload = self.payload_copy()
        self.change_manifest(payload, lambda manifest: manifest["sdk"].update(releaseStatus="release"))
        with self.assertRaisesRegex(sdk.SDKError, "required environment/check evidence"):
            sdk.validate_payload(payload, self.modes(payload))

    def test_complete_verification_report_is_included_without_invention(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "verification.json"
            environment = {"name": "Recorded test environment", "osVersion": "fixture only"}
            report.write_text(json.dumps({"version": self.version, "sourceCommit": self.tree.commit, "runtimeCommit": self.tree.commit, "testedEnvironments": [environment], "checks": [{"name": name, "status": "passed", "details": "fixture evidence only"} for name in sdk.RELEASE_CHECKS]}))
            _, manifest = sdk.build_payload(self.tree, self.runtime, self.version, self.requirements, report)
            self.assertEqual(manifest["sdk"]["releaseStatus"], "release")
            self.assertEqual(manifest["verification"]["testedEnvironments"], [environment])
            report.write_text(json.dumps({"version": "999.0.0"}))
            with self.assertRaisesRegex(sdk.SDKError, "does not match"):
                sdk.build_payload(self.tree, self.runtime, self.version, self.requirements, report)
            report.write_text("[]")
            with self.assertRaisesRegex(sdk.SDKError, "must be a JSON object"):
                sdk.build_payload(self.tree, self.runtime, self.version, self.requirements, report)

    def test_failed_additional_check_prevents_release_claim(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "verification.json"
            checks = [{"name": name, "status": "passed", "details": "fixture evidence only"} for name in sdk.RELEASE_CHECKS]
            checks.append({"name": "additional-acceptance", "status": "failed", "details": "known outstanding failure"})
            report.write_text(json.dumps({"testedEnvironments": [{"name": "Test fixture"}], "checks": checks}))
            payload, manifest = sdk.build_payload(self.tree, self.runtime, self.version, self.requirements, report)
            self.assertEqual(manifest["sdk"]["releaseStatus"], "unverified-candidate")
            self.change_manifest(payload, lambda value: value["sdk"].update(releaseStatus="release"))
            with self.assertRaisesRegex(sdk.SDKError, "required environment/check evidence"):
                sdk.validate_payload(payload, self.modes(payload))

    def test_declared_consumer_tools_and_boolean_metadata_checked(self):
        self.assertEqual(self.manifest["requirements"]["developmentTools"]["python"], "Python 3.9 or newer")
        self.assertIn("compatible iOS/macOS SDKs", self.manifest["requirements"]["developmentTools"]["xcode"])
        for section, key, value in (("source", "dirty", 0), ("source", "dirty", "false"), ("runtime", "remoteVerified", 1), ("runtime", "remoteVerified", "true")):
            payload = self.payload_copy()
            self.change_manifest(payload, lambda manifest: manifest[section].update({key: value}))
            with self.subTest(section=section, key=key, value=value), self.assertRaisesRegex(sdk.SDKError, "must be boolean"):
                sdk.validate_payload(payload, self.modes(payload))

    def test_templates_must_match_complete_plist_payload(self):
        payload = self.payload_copy()
        unexpected = sdk.TEMPLATE_ROOT + "/Forsetti Manifest.xctemplate/private.swift"
        payload[unexpected] = b"import Foundation"
        with self.assertRaisesRegex(sdk.SDKError, "unexpected template files"):
            sdk.validate_payload(payload, self.modes(payload))

    def test_escaping_paths_and_symlinks_rejected(self):
        for path in ("../escape", "/absolute", "folder/../escape", "folder//file", "folder\\file", "./file"):
            with self.subTest(path=path), self.assertRaises(sdk.SDKError):
                sdk.safe_path(path)
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "symlink.zip"
            with zipfile.ZipFile(archive, "w") as output:
                info = zipfile.ZipInfo("Forsetti-SDK-" + self.version + "/README.md", date_time=(1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
                output.writestr(info, "/etc/passwd")
            with self.assertRaisesRegex(sdk.SDKError, "Nonregular"):
                sdk.read_archive(archive)

    def test_duplicate_zip_members_and_wrong_permissions_rejected(self):
        payload = self.payload_copy()
        modes = self.modes(payload)
        modes[sdk.SCRIPT_PATHS[0]] = "0644"
        with self.assertRaisesRegex(sdk.SDKError, "permissions"):
            sdk.validate_payload(payload, modes)
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "duplicate.zip"
            with zipfile.ZipFile(archive, "w") as output:
                info = zipfile.ZipInfo("Forsetti-SDK-" + self.version + "/README.md", date_time=(1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = (stat.S_IFREG | 0o644) << 16
                import warnings
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", UserWarning)
                    output.writestr(info, b"one")
                    output.writestr(info, b"two")
            with self.assertRaisesRegex(sdk.SDKError, "Duplicate archive"):
                sdk.read_archive(archive)

    def test_local_links_and_upstream_reference_mapping_checked(self):
        payload = self.payload_copy()
        payload["README.md"] = b"[Missing](missing.md)\n"
        with self.assertRaisesRegex(sdk.SDKError, "Broken SDK-local"):
            sdk.validate_links(payload, self.manifest)
        payload = self.payload_copy()
        payload["Documentation/Source-References.md"] = b"No mappings"
        with self.assertRaisesRegex(sdk.SDKError, "Package.swift"):
            sdk.validate_links(payload, self.manifest)

    def test_external_checksum_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "Forsetti-SDK.zip"
            archive.write_bytes(b"contents")
            sums = Path(directory) / "SHA256SUMS"
            sums.write_text("0" * 64 + "  Forsetti-SDK.zip\n")
            with self.assertRaisesRegex(sdk.SDKError, "incorrect"):
                sdk.verify_checksum(archive, sums)

    def test_dirty_source_requires_explicit_development_flag(self):
        extra = self.repo / "untracked.txt"
        try:
            extra.write_text("unrelated work must be preserved")
            with self.assertRaisesRegex(sdk.SDKError, "clean source worktree"):
                sdk.SourceTree(self.repo)
            tree = sdk.SourceTree(self.repo, development=True)
            _, manifest = sdk.build_payload(tree, self.runtime, self.version, self.requirements)
            self.assertEqual(manifest["sdk"]["releaseStatus"], "development-candidate")
            self.assertTrue(manifest["source"]["dirty"])
            self.assertTrue(extra.exists())
        finally:
            extra.unlink(missing_ok=True)

    def test_selected_git_tree_ignores_working_byte_mutation(self):
        original = (self.repo / "CONSUMPTION_POLICY.md").read_bytes()
        try:
            (self.repo / "CONSUMPTION_POLICY.md").write_bytes(b"dirty working bytes")
            self.assertEqual(self.tree.read("CONSUMPTION_POLICY.md"), original)
        finally:
            (self.repo / "CONSUMPTION_POLICY.md").write_bytes(original)

    def test_source_version_disagreement_rejected(self):
        state = self.repo / ".release-please-manifest.json"
        original = state.read_bytes()
        try:
            state.write_text(json.dumps({".": "999.0.0"}))
            with self.assertRaisesRegex(sdk.SDKError, "versions must agree"):
                sdk.validate_version(sdk.SourceTree(self.repo, development=True))
        finally:
            state.write_bytes(original)

    def test_committed_and_working_template_symlinks_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory) / "symlink input"
            sdk.run("git", "clone", "--quiet", str(self.repo), str(repository))
            source_path = sdk.TEMPLATE_ROOT + "/Forsetti Manifest.xctemplate/ModuleManifest.json"
            link = repository / source_path
            link.unlink()
            link.symlink_to("/etc/passwd")
            tree = sdk.SourceTree(repository, development=True)
            with self.assertRaisesRegex(sdk.SDKError, "Symlink input"):
                sdk.collect_payload(tree, self.version, self.runtime)
            sdk.run("git", "add", source_path, cwd=repository)
            sdk.run("git", "-c", "user.name=SDK Test", "-c", "user.email=sdk-test@example.invalid", "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "Symlink fixture", cwd=repository)
            committed = sdk.SourceTree(repository)
            with self.assertRaisesRegex(sdk.SDKError, "not a regular file"):
                committed.read(source_path)

    def test_cli_repeated_output_and_overwrite_protection(self):
        specification = importlib.util.spec_from_file_location("sdk_packaging_command", REPO / "Scripts/package-forsetti-sdk.py")
        module = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(module)
        with tempfile.TemporaryDirectory(prefix="sdk output with spaces ") as directory:
            output = Path(directory) / "release files"
            arguments = ["package-forsetti-sdk.py", "--output", str(output), "--runtime-ref", self.tree.commit]
            with patch.object(module, "__file__", str(self.repo / "Scripts/package-forsetti-sdk.py")), patch.object(module, "verified_runtime", return_value=(self.runtime, self.version, self.requirements)), patch.object(sys, "argv", arguments), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(module.main(), 0)
                original = (output / f"Forsetti-SDK-{self.version}.zip").read_bytes()
                self.assertEqual(module.main(), 0)
                (output / "SHA256SUMS").write_text("unrelated preserved content")
                errors = io.StringIO()
                with contextlib.redirect_stderr(errors):
                    self.assertEqual(module.main(), 1)
                self.assertIn("Refusing to replace", errors.getvalue())
                self.assertEqual((output / f"Forsetti-SDK-{self.version}.zip").read_bytes(), original)
                self.assertEqual((output / "SHA256SUMS").read_text(), "unrelated preserved content")

    def test_cli_source_provenance_verification(self):
        specification = importlib.util.spec_from_file_location("sdk_verification_command", REPO / "Scripts/verify-forsetti-sdk.py")
        module = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(module)
        with tempfile.TemporaryDirectory(prefix="verify SDK path ") as directory:
            archive = Path(directory) / f"Forsetti-SDK-{self.version}.zip"
            data = sdk.archive_bytes(self.payload, self.version)
            archive.write_bytes(data)
            (Path(directory) / "SHA256SUMS").write_text(f"{sdk.digest(data)}  {archive.name}\n")
            arguments = ["verify-forsetti-sdk.py", "--archive", str(archive), "--source-repo", str(self.repo)]
            output = io.StringIO()
            with patch.object(sys, "argv", arguments), contextlib.redirect_stdout(output):
                self.assertEqual(module.main(), 0)
            self.assertIn("Canonical source equality verified", output.getvalue())


if __name__ == "__main__":
    unittest.main()
