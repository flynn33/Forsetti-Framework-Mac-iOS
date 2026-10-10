"""Native project preparation checks; these do not claim Apple app runtime evidence."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("consumer_harness", ROOT / "Scripts/test-forsetti-sdk-consumer.py")
HARNESS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HARNESS)
SHA = "a" * 40


class ConsumerHarnessTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="forsetti consumer harness ")
        self.addCleanup(temporary.cleanup)
        self.workdir = Path(temporary.name).resolve()
        self.sdk = self.workdir / "Extracted SDK"
        (self.sdk / "Scripts").mkdir(parents=True)
        shutil.copy2(ROOT / "Scripts/generate-forsetti-scaffold.sh", self.sdk / "Scripts")
        shutil.copytree(ROOT / "XcodeTemplates", self.sdk / "XcodeTemplates")
        (self.sdk / "sdk-manifest.json").write_text(json.dumps({
            "sdk": {"version": "0.6.0"}, "source": {"commit": SHA},
            "runtime": {"url": HARNESS.RUNTIME_URL, "commit": SHA},
            "products": [{"name": name} for name in HARNESS.PRODUCTS],
        }))

    def prepare(self, variant):
        return HARNESS.prepare_consumer(self.sdk, self.workdir, variant, SHA)

    def graph(self, consumer):
        result = subprocess.run(["plutil", "-convert", "json", "-o", "-",
                                 str(Path(consumer["project"]) / "project.pbxproj")],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_single_project_membership_and_exact_remote_dependency(self):
        consumer = self.prepare("single")
        graph = self.graph(consumer)
        objects = graph["objects"]
        packages = [value for value in objects.values() if value["isa"] == "XCRemoteSwiftPackageReference"]
        self.assertEqual(len(packages), 1)
        self.assertEqual(packages[0]["repositoryURL"], HARNESS.RUNTIME_URL)
        self.assertEqual(packages[0]["requirement"], {"kind": "revision", "revision": SHA})
        self.assertFalse(any(value["isa"] == "XCLocalSwiftPackageReference" for value in objects.values()))
        selected = [value["productName"] for value in objects.values() if value["isa"] == "XCSwiftPackageProductDependency"]
        self.assertEqual(set(selected), set(HARNESS.PRODUCTS))
        sources = next(value for value in objects.values() if value["isa"] == "PBXSourcesBuildPhase")
        members = sorted(objects[objects[file]["fileRef"]]["path"] for file in sources["files"])
        self.assertEqual(members, sorted("App/" + path for path in consumer["sources"]))
        resources = next(value for value in objects.values() if value["isa"] == "PBXResourcesBuildPhase")
        self.assertEqual(len(resources["files"]), 1)
        reference = objects[objects[resources["files"][0]]["fileRef"]]
        self.assertEqual(reference["lastKnownFileType"], "folder")
        self.assertEqual(reference["path"], "App/Resources/ForsettiManifests")
        tracked = subprocess.check_output(["git", "ls-files"], cwd=consumer["directory"], text=True).splitlines()
        self.assertEqual(tracked, consumer["trackedFiles"])
        self.assertTrue(all(not file.startswith(("Sources/", "Scripts/", "XcodeTemplates/")) for file in tracked))
        self.assertTrue(any(file.endswith(".xcscheme") for file in tracked))

    def test_single_instrumentation_observes_production_gate_and_view_appearance(self):
        consumer = self.prepare("single")
        app = Path(consumer["directory"]) / "App"
        deployment = (app / "SDKSingleDeploymentMode.swift").read_text()
        bootstrap = (app / "SDKSingleForsettiBootstrap.swift").read_text()
        content = (app / "ContentView.swift").read_text()
        view = (app / "AppModule/SDKSingleAppModuleView.swift").read_text()
        probe = (app / "SDKSmokeProbe.swift").read_text()
        self.assertIn("= .production", deployment)
        self.assertIn("ForsettiEntitlementProviderFactory.makeDefault()", bootstrap)
        self.assertIn("registry.registeredEntryPoints", bootstrap)
        self.assertIn("if controller.activeUIModuleID == SDKSingleAppModule.Constants.moduleID", bootstrap)
        self.assertIn(".task { await ForsettiSDKSmokeProbe.capture(bootstrap) }", content)
        self.assertIn('ForsettiSDKSmokeProbe.renderedViewID = "single-module-ui"', view)
        self.assertIn("await bootstrap.bootForProduction()", probe)
        self.assertIn("bootstrap.controller.runtime.moduleManager.discoveredManifests.map(\\.moduleID)", probe)
        self.assertIn("case .ready where renderedViewID != nil:", probe)
        self.assertNotIn("productionState = .ready", probe)
        self.assertNotIn("StaticEntitlementProvider", bootstrap + probe)

    def test_multimodule_adapts_only_generated_sources_and_keeps_one_ui_module(self):
        consumer = self.prepare("multi")
        app = Path(consumer["directory"]) / "App"
        self.assertFalse((app / "AppModule").exists())
        manifests = [json.loads(file.read_text()) for file in (app / "Resources/ForsettiManifests").glob("*.json")]
        self.assertEqual(sorted(value["moduleType"] for value in manifests), ["service", "ui"])
        self.assertEqual(sorted(value["moduleID"] for value in manifests), ["org.example.sdksmoke.background", "org.example.sdksmoke.workspace"])
        registry = (app / "SDKMultiModuleRegistry.swift").read_text()
        bootstrap = (app / "SDKMultiForsettiBootstrap.swift").read_text()
        content = (app / "ContentView.swift").read_text()
        self.assertIn("SDKWorkspaceUIModule.Constants.entryPoint", registry)
        self.assertIn("SDKBackgroundServiceModule.Constants.entryPoint", registry)
        self.assertIn("moduleIDs: [SDKWorkspaceUIModule.Constants.moduleID, SDKBackgroundServiceModule.Constants.moduleID]", bootstrap)
        self.assertIn("if controller.activeUIModuleID == SDKWorkspaceUIModule.Constants.moduleID", bootstrap)
        self.assertIn("SDKWorkspaceUIModuleView()", content)
        self.assertNotIn("SDKMultiAppModule", registry + bootstrap + content)
        self.graph(consumer)

    def test_rejection_uses_invalid_resource_schema_with_production_gate_intact(self):
        consumer = self.prepare("rejection")
        app = Path(consumer["directory"]) / "App"
        resource = json.loads(next((app / "Resources/ForsettiManifests").glob("*.json")).read_text())
        module = (app / "AppModule/SDKRejectedAppModule.swift").read_text()
        self.assertEqual(resource["schemaVersion"], "999.0")
        self.assertIn("schemaVersion: ModuleManifest.currentSchemaVersion", module)
        self.assertIn("productionState = .failed", (app / "SDKRejectedForsettiBootstrap.swift").read_text())
        self.graph(consumer)

    def test_preparation_rejects_existing_consumer_without_overwrite(self):
        consumer = self.prepare("single")
        app = Path(consumer["directory"]) / "App"
        sentinel = app / "Keep.txt"
        sentinel.write_text("owned")
        with self.assertRaises(HARNESS.SmokeError):
            self.prepare("single")
        self.assertEqual(sentinel.read_text(), "owned")

    def test_all_generated_and_instrumented_swift_sources_parse_with_native_compiler(self):
        for variant in HARNESS.VARIANTS:
            with self.subTest(variant=variant):
                consumer = self.prepare(variant)
                app = Path(consumer["directory"]) / "App"
                result = subprocess.run(["xcrun", "swiftc", "-frontend", "-parse", *map(str, app.rglob("*.swift"))],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_project_graph_rejects_local_urls_mutable_pins_and_path_escape(self):
        for url, revision, sources in (("/local/package", SHA, ["App.swift"]),
                                       (HARNESS.RUNTIME_URL, "main", ["App.swift"]),
                                       (HARNESS.RUNTIME_URL, SHA, ["../App.swift"])):
            with self.assertRaises(HARNESS.SmokeError):
                HARNESS.project_graph("App", "org.example.app", sources, url, revision)

    def test_presentation_wait_accepts_finite_nonnegative_values_and_cli_rejects_invalid_input(self):
        self.assertEqual(HARNESS.presentation_wait("0"), 0.0)
        self.assertEqual(HARNESS.presentation_wait("2.5"), 2.5)
        for value in ("-1", "nan", "inf", "-inf", "invalid"):
            with self.subTest(value=value):
                result = subprocess.run(["python3", str(ROOT / "Scripts/test-forsetti-sdk-consumer.py"),
                                         "--sdk", str(self.sdk), "--workdir", str(self.workdir),
                                         "--runtime-commit", SHA, "--simulator", "unused", "--device-set", "unused",
                                         "--presentation-wait=" + value], capture_output=True, text=True)
                self.assertEqual(result.returncode, 2)
                self.assertIn("finite nonnegative", result.stderr)
                self.assertFalse((self.workdir / "Consumers").exists())

    def valid_receipt(self, variant, platform="macOS"):
        spec = HARNESS.VARIANTS[variant]
        value = {"variant": variant, "platform": platform, "registeredEntryPoints": [spec["name"] + "AppModule"],
                 "bootState": "ready", "isBooted": True, "error": None, "discoveredModuleIDs": [spec["moduleID"]],
                 "activeUIModuleID": spec["moduleID"], "enabledServiceModuleIDs": [], "renderedViewID": "single-module-ui",
                 "resourceManifestFiles": ["AppModuleManifest.json"]}
        if variant == "multi":
            value.update(registeredEntryPoints=sorted([spec["uiName"] + "UIModule", spec["serviceName"] + "ServiceModule"]),
                         discoveredModuleIDs=sorted([spec["uiID"], spec["serviceID"]]), activeUIModuleID=spec["uiID"],
                         enabledServiceModuleIDs=[spec["serviceID"]], renderedViewID="dedicated-ui-module",
                         resourceManifestFiles=["UIModuleManifest.json", "ServiceModuleManifest.json"])
        if variant == "rejection":
            value.update(bootState="failed", isBooted=False, error="Unsupported schemaVersion '999.0'.", discoveredModuleIDs=[],
                         activeUIModuleID=None, renderedViewID=None)
        return value

    def test_receipts_require_actual_discovery_activation_ui_and_service(self):
        for variant in HARNESS.VARIANTS:
            for platform in ("macOS", "iOS"):
                HARNESS.validate_receipt(self.valid_receipt(variant, platform), variant, platform)
        for key, bad_value in (("activeUIModuleID", None), ("renderedViewID", None), ("registeredEntryPoints", []),
                               ("discoveredModuleIDs", []), ("resourceManifestFiles", []), ("error", "activation denied")):
            value = self.valid_receipt("single")
            value[key] = bad_value
            with self.assertRaises(HARNESS.SmokeError, msg=key):
                HARNESS.validate_receipt(value, "single", "macOS")
        value = self.valid_receipt("multi")
        value["enabledServiceModuleIDs"] = []
        with self.assertRaises(HARNESS.SmokeError):
            HARNESS.validate_receipt(value, "multi", "macOS")

    def test_rejection_receipt_disallows_ready_or_rendered_module(self):
        for key, bad_value in (("bootState", "ready"), ("isBooted", True), ("activeUIModuleID", "org.example.sdksmoke.rejected"),
                               ("renderedViewID", "single-module-ui"), ("error", "unrelated error")):
            value = self.valid_receipt("rejection")
            value[key] = bad_value
            with self.assertRaises(HARNESS.SmokeError, msg=key):
                HARNESS.validate_receipt(value, "rejection", "macOS")


if __name__ == "__main__":
    unittest.main()
