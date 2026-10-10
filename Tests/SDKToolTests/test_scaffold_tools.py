"""Consumer tools run from an extracted kit with no framework source checkout."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import zipfile

REPOSITORY = Path(__file__).resolve().parents[2]
SCRIPTS = (
    "install-forsetti-xcode-template.sh",
    "uninstall-forsetti-xcode-template.sh",
    "generate-forsetti-scaffold.sh",
)
TEMPLATES = {
    "app": ("Forsetti App.xctemplate", 8, "AppModule"),
    "ui": ("Forsetti UI Module.xctemplate", 3, "UIModule"),
    "service": ("Forsetti Service Module.xctemplate", 2, "ServiceModule"),
    "manifest": ("Forsetti Manifest.xctemplate", 1, "Module"),
}


class ScaffoldToolTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="forsetti tools ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.kit = self.root / "extracted SDK with spaces"
        self.cwd = self.root / "unrelated working directory"
        self.cwd.mkdir()
        archive = self.root / "kit.zip"
        with zipfile.ZipFile(archive, "w") as output:
            for script in SCRIPTS:
                source = REPOSITORY / "Scripts" / script
                output.write(source, "Scripts/" + script)
            for source in (REPOSITORY / "XcodeTemplates").rglob("*"):
                if source.is_file():
                    output.write(source, source.relative_to(REPOSITORY).as_posix())
        with zipfile.ZipFile(archive) as package:
            package.extractall(self.kit)
        for script in SCRIPTS:
            (self.kit / "Scripts" / script).chmod(0o755)

    def run_script(self, script, *arguments, success=True):
        result = subprocess.run([str(self.kit / "Scripts" / script), *map(str, arguments)],
                                cwd=self.cwd, capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertTrue(result.stderr.strip(), "failure must be actionable")
            self.assertNotIn("Traceback", result.stderr)
        return result

    def generate(self, template="app", name="Consumer", module_id="org.example.consumer", output=None,
                 success=True, *extras):
        output = self.root / "consumer sources" if output is None else output
        result = self.run_script("generate-forsetti-scaffold.sh", "--template", template,
                                 "--name", name, "--module-id", module_id, "--output", output,
                                 *extras, success=success)
        return json.loads(result.stdout) if success else result

    def test_all_templates_generate_only_plist_declared_app_owned_files(self):
        for template, (directory, count, suffix) in TEMPLATES.items():
            with self.subTest(template=template):
                output = self.root / (template + " output")
                module_id = "org.example." + template
                inventory = self.generate(template, module_id=module_id, output=output)
                actual = sorted(path.relative_to(output).as_posix() for path in output.rglob("*") if path.is_file())
                self.assertEqual(inventory["generated_files"], actual)
                self.assertEqual(len(actual), count)
                self.assertEqual(inventory["entry_point"], "Consumer" + suffix)
                source = self.kit / "XcodeTemplates/Project Templates/Forsetti" / directory
                with (source / "TemplateInfo.plist").open("rb") as stream:
                    definition = plistlib.load(stream)
                expected = sorted(node.replace("___PACKAGENAME:identifier___", "Consumer") for node in definition["Nodes"])
                self.assertEqual(actual, expected)
                self.assertEqual(sorted(inventory["source_files"]), sorted(
                    (source / payload["Path"]).relative_to(self.kit).as_posix()
                    for payload in definition["Definitions"].values()))
                for relative in actual:
                    self.assertTrue(relative.endswith((".swift", ".json")))
                    text = (output / relative).read_text()
                    self.assertNotIn("___", text)
                    self.assertNotIn("com.yourcompany", text)
                    self.assertNotIn("com.forsetti.iap", text)
                    if relative.endswith(".json"):
                        self.assertEqual(Path(relative).parent.as_posix(), "Resources/ForsettiManifests")
                        value = json.loads(text)
                        self.assertEqual(value["moduleID"], module_id)
                        self.assertEqual(value["entryPoint"], "Consumer" + suffix)
                        self.assertIsNone(value.get("iapProductID"))
                    elif relative.endswith(suffix + ".swift"):
                        self.assertIn(f'static let moduleID = "{module_id}"', text)
                        self.assertIn(f'static let entryPoint = "Consumer{suffix}"', text)

    def test_app_registry_and_production_activation_gate_are_preserved(self):
        inventory = self.generate()
        output = Path(inventory["output"])
        registry = (output / "ConsumerModuleRegistry.swift").read_text()
        bootstrap = (output / "ConsumerForsettiBootstrap.swift").read_text()
        content = (output / "ContentView.swift").read_text()
        self.assertIn("try registry.register(entryPoint: ConsumerAppModule.Constants.entryPoint)", registry)
        self.assertIn("manifestsBundle: .main", bootstrap)
        self.assertIn('manifestsSubdirectory: "ForsettiManifests"', bootstrap)
        self.assertIn("ForsettiEntitlementProviderFactory.makeDefault()", bootstrap)
        self.assertIn("activationStrategy: .activate(moduleIDs: [ConsumerAppModule.Constants.moduleID])", bootstrap)
        self.assertIn("if controller.activeUIModuleID == ConsumerAppModule.Constants.moduleID", bootstrap)
        self.assertIn("productionState = .failed", bootstrap)
        self.assertIn("case .ready:", content)
        self.assertNotIn("case .production:\n                ConsumerAppModuleView()", content)

    def test_ui_and_service_contract_identities_match_json(self):
        for template, namespace in (("app", "app-module"), ("ui", "ui-module"), ("service", "service-module")):
            with self.subTest(template=template):
                output = self.root / template
                module_id = "org.example." + template
                inventory = self.generate(template, module_id=module_id, output=output)
                suffix = TEMPLATES[template][2]
                swift = next(output.rglob("Consumer" + suffix + ".swift")).read_text()
                manifest = json.loads(next(output.rglob("*.json")).read_text())
                self.assertNotIn("Consumer." + namespace, swift)
                for requirement in manifest["runtimeRequirements"]["io"]:
                    self.assertIn('"' + requirement["requirementID"] + '"', swift)
                for view_id in (manifest["runtimeRequirements"].get("ui") or {}).get("viewIDs", []):
                    self.assertIn('"' + view_id + '"', swift)
                for store_id in manifest["runtimeRequirements"]["dataIsolation"]["ownedStoreIDs"]:
                    self.assertIn('"' + store_id + '"', swift)
                self.assertEqual(inventory["module_id"], module_id)

    def test_display_name_escapes_strings_without_changing_type_identity(self):
        display_name = 'My "Native" App \\(owned) 🦉'
        inventory = self.generate("app", "Consumer", "org.example.consumer", None, True,
                                  "--app-name", display_name)
        output = Path(inventory["output"])
        manifest = json.loads(next(output.rglob("*.json")).read_text())
        self.assertEqual(manifest["displayName"], display_name + " App Module")
        swift = (output / "AppModule/ConsumerAppModule.swift").read_text()
        self.assertIn(json.dumps(display_name + " App Module", ensure_ascii=False), swift)
        self.assertEqual(inventory["entry_point"], "ConsumerAppModule")

    def test_generator_rejects_invalid_names_and_identifiers_without_writes(self):
        for name in ("", "class", "9App", "My App", "A/B", "_", "A" * 81):
            with self.subTest(name=name):
                self.generate(name=name, success=False)
                self.assertFalse((self.root / "consumer sources").exists())
        for module_id in ("", "single", "org..app", "org.example._app", "forsetti.app", "com.yourcompany.app", "com.forsetti.app", "org.example/app"):
            with self.subTest(module_id=module_id):
                self.generate(module_id=module_id, success=False)
                self.assertFalse((self.root / "consumer sources").exists())

    def test_generator_rejects_unsupported_template_and_option(self):
        self.generate(template="unknown", success=False)
        self.generate("ui", "Consumer", "org.example.consumer", None, False, "--app-name", "App")
        self.generate("app", "Consumer", "org.example.consumer", None, False, "--app-name", "\nApp")

    def test_generator_rejects_any_existing_output_before_partial_writes(self):
        output = self.root / "consumer sources"
        output.mkdir()
        sentinel = output / "ContentView.swift"
        sentinel.write_text("consumer-owned content")
        self.generate(output=output, success=False)
        self.assertEqual(list(output.iterdir()), [sentinel])
        self.assertEqual(sentinel.read_text(), "consumer-owned content")

    def test_generator_preserves_unrelated_sources_and_adds_distinct_modules(self):
        output = self.root / "consumer sources"
        output.mkdir()
        sentinel = output / "Existing.swift"
        sentinel.write_text("existing app source")
        self.generate("ui", "Workspace", "org.example.workspace", output)
        self.generate("service", "Background", "org.example.background", output)
        self.assertEqual(sentinel.read_text(), "existing app source")
        self.assertEqual(len(list((output / "Resources/ForsettiManifests").glob("*.json"))), 2)

    def test_generator_rejects_duplicate_module_id_and_entrypoint(self):
        output = self.root / "consumer sources"
        self.generate("ui", "Workspace", "org.example.workspace", output)
        self.generate("service", "Background", "org.example.workspace", output, False)
        self.generate("manifest", "WorkspaceUIModule", "org.example.second", output)
        existing = output / "Resources/ForsettiManifests/Manual.json"
        existing.write_text(json.dumps({"moduleID": "org.example.third", "entryPoint": "BackgroundServiceModule"}))
        self.generate("service", "Background", "org.example.fourth", output, False)
        self.assertFalse((output / "BackgroundServiceModule.swift").exists())

    def test_generator_rejects_symlink_output_and_parent(self):
        actual = self.root / "outside"
        actual.mkdir()
        link = self.root / "linked"
        link.symlink_to(actual, target_is_directory=True)
        self.generate(output=link, success=False)
        self.generate(output=link / "child", success=False)
        output = self.root / "consumer sources"
        output.mkdir()
        (output / "Resources").symlink_to(actual, target_is_directory=True)
        self.generate(output=output, success=False)
        self.assertEqual(list(actual.iterdir()), [])

    def test_generator_rejects_unsafe_output_and_traversal(self):
        for output in ("", Path("/"), Path.home(), self.root / ".." / "elsewhere"):
            self.generate(output=output, success=False)

    def test_generator_rejects_modified_template_inventory_and_unsafe_paths(self):
        template = self.kit / "XcodeTemplates/Project Templates/Forsetti/Forsetti App.xctemplate"
        extra = template / "Unexpected.swift"
        extra.write_text("unexpected source")
        self.generate(success=False)
        extra.unlink()
        plist = template / "TemplateInfo.plist"
        with plist.open("rb") as stream:
            data = plistlib.load(stream)
        data["Definitions"]["ContentView.swift"]["Path"] = "../escape.swift"
        with plist.open("wb") as stream:
            plistlib.dump(data, stream)
        self.generate(success=False)
        self.assertFalse((self.root / "consumer sources").exists())

    def test_generator_rejects_symlink_template_payload(self):
        template = self.kit / "XcodeTemplates/Project Templates/Forsetti/Forsetti App.xctemplate"
        payload = template / "AppModule.swift"
        outside = self.root / "outside.swift"
        shutil.copy2(payload, outside)
        payload.unlink()
        payload.symlink_to(outside)
        self.generate(success=False)

    def test_repeated_install_and_uninstall_preserve_unrelated_templates(self):
        destination = self.root / "custom Xcode category with spaces"
        unrelated = destination / "Other.xctemplate"
        unrelated.mkdir(parents=True)
        sentinel = unrelated / "keep.txt"
        sentinel.write_text("unrelated template")
        self.run_script(SCRIPTS[0], "--destination", destination)
        stale = destination / "Forsetti App.xctemplate/Stale.swift"
        stale.write_text("stale template")
        self.run_script(SCRIPTS[0], "--destination", destination)
        self.assertFalse(stale.exists())
        for name, _, _ in TEMPLATES.values():
            installed = destination / name
            source = self.kit / "XcodeTemplates/Project Templates/Forsetti" / name
            self.assertTrue(installed.is_dir())
            for file in source.rglob("*"):
                if file.is_file():
                    self.assertEqual(hashlib.sha256(file.read_bytes()).digest(),
                                     hashlib.sha256((installed / file.relative_to(source)).read_bytes()).digest())
        self.run_script(SCRIPTS[1], "--destination", destination)
        self.run_script(SCRIPTS[1], "--destination", destination)
        self.assertEqual(list(destination.iterdir()), [unrelated])
        self.assertEqual(sentinel.read_text(), "unrelated template")

    def test_uninstall_removes_empty_category_and_missing_category_is_safe(self):
        destination = self.root / "clean category"
        self.run_script(SCRIPTS[0], "--destination", destination)
        self.run_script(SCRIPTS[1], "--destination", destination)
        self.assertFalse(destination.exists())
        self.run_script(SCRIPTS[1], "--destination", destination)

    def test_install_and_uninstall_reject_symlink_destination(self):
        actual = self.root / "outside"
        actual.mkdir()
        linked = self.root / "linked"
        linked.symlink_to(actual, target_is_directory=True)
        for script in SCRIPTS[:2]:
            self.run_script(script, "--destination", linked, success=False)
            self.run_script(script, "--destination", linked / "child", success=False)
        self.assertEqual(list(actual.iterdir()), [])

    def test_install_and_uninstall_reject_nested_symlinks_before_mutation(self):
        destination = self.root / "category"
        self.run_script(SCRIPTS[0], "--destination", destination)
        link = destination / "Forsetti Manifest.xctemplate/linked"
        link.symlink_to(self.root / "missing")
        for script in SCRIPTS[:2]:
            self.run_script(script, "--destination", destination, success=False)
            self.assertTrue((destination / "Forsetti App.xctemplate").is_dir())

    def test_install_and_uninstall_reject_files_and_unsafe_destinations(self):
        destination = self.root / "file"
        destination.write_text("owned")
        for script in SCRIPTS[:2]:
            for path in ("", destination, Path("/"), Path.home(), self.root / ".." / "other"):
                self.run_script(script, "--destination", path, success=False)
        self.assertEqual(destination.read_text(), "owned")

    def test_installer_rejects_extra_or_missing_payload_before_destination_creation(self):
        source = self.kit / "XcodeTemplates/Project Templates/Forsetti/Forsetti App.xctemplate"
        destination = self.root / "category"
        extra = source / "Unexpected.swift"
        extra.write_text("extra")
        self.run_script(SCRIPTS[0], "--destination", destination, success=False)
        self.assertFalse(destination.exists())
        extra.unlink()
        (source / "AppModule.swift").unlink()
        self.run_script(SCRIPTS[0], "--destination", destination, success=False)
        self.assertFalse(destination.exists())

    def test_tools_reject_template_source_ancestor_symlinks(self):
        templates = self.kit / "XcodeTemplates"
        actual = self.root / "outside templates"
        templates.rename(actual)
        templates.symlink_to(actual, target_is_directory=True)
        self.generate(success=False)
        self.run_script(SCRIPTS[0], "--destination", self.root / "category", success=False)


if __name__ == "__main__":
    unittest.main()
