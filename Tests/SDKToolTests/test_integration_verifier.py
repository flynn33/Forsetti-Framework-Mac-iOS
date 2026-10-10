"""Consumer boundary fixtures exercise tracked files and declared target membership."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
VERIFIER = ROOT / "Scripts/verify-forsetti-integration.sh"
RUNTIME_URL = "https://github.com/flynn33/Forsetti-Framework-Mac-iOS"
COMMIT = "a" * 40
PACKAGE = '''// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "Consumer", platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [.package(url: "https://github.com/flynn33/Forsetti-Framework-Mac-iOS", exact: "1.0.0")],
    targets: [.executableTarget(name: "Consumer", dependencies: [
        .product(name: "ForsettiCore", package: "Forsetti-Framework-Mac-iOS"),
        .product(name: "ForsettiPlatform", package: "Forsetti-Framework-Mac-iOS"),
        .product(name: "ForsettiHostTemplate", package: "Forsetti-Framework-Mac-iOS")
    ], resources: [.copy("Resources/ForsettiManifests")])])
'''
MANIFEST = {
    "schemaVersion": "1.1", "manifestTemplateVersion": "1.1",
    "moduleID": "com.owner.consumer.app-module", "entryPoint": "ConsumerAppModule",
    "displayName": "Consumer", "moduleType": "app",
}


@unittest.skipUnless(shutil.which("swift") and shutil.which("git"), "Swift and Git required for declared-membership fixtures")
class IntegrationVerifierTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="Forsetti consumer verifier ")
        self.addCleanup(self.temporary.cleanup)
        self.project = Path(self.temporary.name) / "Independent App"
        self.project.mkdir()
        self.write("Package.swift", PACKAGE)
        self.write("Sources/Consumer/main.swift", "import Foundation\nimport SwiftUI\nimport ForsettiCore\nimport ForsettiPlatform\nimport ForsettiHostTemplate\nstruct ConsumerAppModule: ForsettiAppModule {}\n")
        self.write("Sources/Consumer/Resources/ForsettiManifests/Consumer.json", json.dumps(MANIFEST))
        self.write("Package.resolved", json.dumps({"version": 3, "pins": [{"identity": "forsetti-framework-mac-ios", "kind": "remoteSourceControl", "location": RUNTIME_URL, "state": {"revision": COMMIT, "version": "1.0.0"}}]}))
        self.write(".gitignore", ".build/\n.swiftpm/\nDerivedData/\n")
        self.write("LICENSE", "Required Forsetti license notice\n")
        self.write("NOTICE", "ForsettiFramework and ForsettiModulesExample appear in an attribution notice, not application code.\n")
        self.command("git", "init", "-q")
        self.command("git", "add", "--all")

    def command(self, *command):
        return subprocess.run(command, cwd=self.project, check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def write(self, relative, text):
        path = self.project / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def track(self, *paths):
        self.command("git", "add", "--force", "--", *paths)

    def verify(self, *arguments, expectations=True):
        expected = ["--runtime-ref", "v1.0.0", "--runtime-commit", COMMIT] if expectations else []
        result = subprocess.run([str(VERIFIER), "--project", str(self.project), *expected, "--json", *arguments], cwd="/", text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertIn(result.returncode, (0, 1), result.stderr + result.stdout)
        report = json.loads(result.stdout)
        self.assertEqual(report["ok"], result.returncode == 0)
        return report

    def assertViolation(self, code, report):
        self.assertIn(code, [entry["code"] for entry in report["violations"]], json.dumps(report, indent=2))

    def test_public_imports_notices_and_untracked_managed_caches_pass(self):
        for directory in (".build/checkouts/renamed", ".swiftpm/cache", "DerivedData/SourcePackages/checkouts/renamed"):
            self.write(directory + "/Renamed.swift", "public final class ForsettiRuntime {}\n")
        report = self.verify()
        self.assertTrue(report["ok"], json.dumps(report, indent=2))
        self.assertEqual(report["checks"]["contentMode"], "git-tracked-working-files")
        self.assertEqual(report["checks"]["selectedProducts"], ["ForsettiCore", "ForsettiHostTemplate", "ForsettiPlatform"])
        self.assertEqual(len(report["checks"]["targets"]), 1)
        self.assertEqual(report["checks"]["targets"][0]["manifests"][0]["moduleID"], MANIFEST["moduleID"])

    def test_renamed_runtime_file_detected_by_declaration(self):
        self.write("Sources/Consumer/Utilities/Things.swift", "import Foundation\npublic final class ForsettiRuntime {}\n")
        self.track("Sources/Consumer/Utilities/Things.swift")
        self.assertViolation("runtime-implementation-copy", self.verify())

    def test_comments_and_diagnostic_strings_do_not_become_imports_or_declarations(self):
        self.write("Sources/Consumer/Diagnostics.swift", '// import ForsettiFramework\n// public final class ForsettiRuntime {}\nlet diagnostic = "import ForsettiModulesExample; ExampleModuleResources; class ForsettiRuntime"\n')
        self.track("Sources/Consumer/Diagnostics.swift")
        report = self.verify()
        self.assertTrue(report["ok"], json.dumps(report, indent=2))

    def test_renamed_runtime_type_detected_by_implementation_content(self):
        original = (ROOT / "Sources/ForsettiCore/Runtime/ManifestLoader.swift").read_text()
        self.write("Sources/Consumer/Utilities/Things.swift", original.replace("ManifestLoader", "ConsumerLoader"))
        self.track("Sources/Consumer/Utilities/Things.swift")
        self.assertViolation("runtime-implementation-copy", self.verify())

    def test_every_public_runtime_source_copy_detected_with_renamed_paths(self):
        paths = []
        for product in ("ForsettiCore", "ForsettiPlatform", "ForsettiHostTemplate"):
            paths.extend((ROOT / "Sources" / product).rglob("*.swift"))
        destinations = set()
        for index, path in enumerate(sorted(paths)):
            destination = "Sources/Consumer/Utilities/Unit{}.swift".format(index)
            self.write(destination, path.read_text())
            destinations.add(destination)
        self.track("Sources/Consumer/Utilities")
        report = self.verify()
        detected = {entry["path"] for entry in report["violations"] if entry["code"] == "runtime-implementation-copy"}
        self.assertFalse(destinations - detected, "Undetected copied runtime files: " + str(destinations - detected))

    def test_common_app_owned_type_names_are_not_reserved(self):
        self.write("Sources/Consumer/Utilities.swift", "struct SemVer { let display: String }\nenum Platform { case example }\nstruct ActivationState {}\n")
        self.track("Sources/Consumer/Utilities.swift")
        self.assertTrue(self.verify()["ok"])

    def test_internal_examples_and_umbrella_import_rejected(self):
        for text, code in (("import ForsettiModulesExample\n", "unsupported-import"), ("import ForsettiFramework\n", "unsupported-import"), ("let bundle = ExampleModuleResources.bundle\n", "internal-example")):
            with self.subTest(text=text):
                self.write("Sources/Consumer/Bad.swift", text)
                self.track("Sources/Consumer/Bad.swift")
                self.assertViolation(code, self.verify())

    def test_internal_example_manifest_rejected(self):
        value = dict(MANIFEST, moduleID="com.forsetti.module.example-ui", iapProductID="com.forsetti.iap.example-ui")
        self.write("Sources/Consumer/Resources/ForsettiManifests/Consumer.json", json.dumps(value))
        self.assertViolation("sample-identity", self.verify())

    def test_tracked_cache_rejected_even_if_ignored(self):
        self.write(".build/checkouts/renamed/Utility.swift", "public final class ForsettiRuntime {}")
        self.track(".build/checkouts/renamed/Utility.swift")
        report = self.verify()
        self.assertViolation("tracked-cache", report)
        self.assertViolation("runtime-implementation-copy", report)

    def test_vendored_local_dependency_with_renamed_folder_rejected(self):
        self.write("Vendor/Utility/Package.swift", '// swift-tools-version: 5.10\nimport PackageDescription\nlet package = Package(name: "ForsettiFramework", products: [.library(name: "ForsettiCore", targets: ["Core"])], targets: [.target(name: "Core")])')
        self.write("Vendor/Utility/Sources/Core/File.swift", "public final class ForsettiRuntime {}")
        self.write("Package.swift", PACKAGE.replace('.package(url: "' + RUNTIME_URL + '", exact: "1.0.0")', '.package(path: "Vendor/Utility")').replace('package: "Forsetti-Framework-Mac-iOS"', 'package: "Utility"'))
        self.track("Vendor", "Package.swift")
        self.assertViolation("vendored-local-runtime", self.verify())

    def test_app_owned_local_module_with_remote_core_dependency_is_allowed(self):
        local_manifest = '''// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "LocalService", products: [.library(name: "LocalService", targets: ["LocalService"])],
    dependencies: [.package(url: "https://github.com/flynn33/Forsetti-Framework-Mac-iOS", exact: "1.0.0")],
    targets: [.target(name: "LocalService", dependencies: [.product(name: "ForsettiCore", package: "Forsetti-Framework-Mac-iOS")])])
'''
        self.write("OwnedModules/LocalService/Package.swift", local_manifest)
        self.write("OwnedModules/LocalService/Sources/LocalService/Service.swift", "import ForsettiCore\nfinal class LocalService {}\n")
        self.write("Package.swift", PACKAGE.replace('dependencies: [.package(url:', 'dependencies: [.package(path: "OwnedModules/LocalService"), .package(url:', 1).replace('targets: [.executableTarget(name: "Consumer", dependencies: [', 'targets: [.executableTarget(name: "Consumer", dependencies: [.product(name: "LocalService", package: "LocalService"),', 1))
        self.track("OwnedModules", "Package.swift")
        report = self.verify()
        self.assertTrue(report["ok"], json.dumps(report, indent=2))

    def test_fully_renamed_local_runtime_package_detected_by_source_content(self):
        self.write("Vendor/Utility/Package.swift", '// swift-tools-version: 5.10\nimport PackageDescription\nlet package = Package(name: "Utility", products: [.library(name: "Utility", targets: ["Utility"])], targets: [.target(name: "Utility")])')
        self.write("Vendor/Utility/Sources/Utility/Values.swift", (ROOT / "Sources/ForsettiCore/Model/SemVer.swift").read_text())
        self.write("Package.swift", PACKAGE.replace('dependencies: [.package(url:', 'dependencies: [.package(path: "Vendor/Utility"), .package(url:', 1))
        self.track("Vendor", "Package.swift")
        self.assertViolation("vendored-local-runtime", self.verify())

    def test_unsupported_product_from_remote_runtime_rejected(self):
        self.write("Package.swift", PACKAGE.replace('name: "ForsettiCore",', 'name: "ForsettiModulesExample",'))
        self.assertViolation("unsupported-product", self.verify())

    def test_mutable_runtime_and_resolved_commit_mismatch_rejected(self):
        self.write("Package.swift", PACKAGE.replace('exact: "1.0.0"', 'branch: "main"'))
        self.write("Package.resolved", json.dumps({"version": 3, "pins": [{"identity": "forsetti-framework-mac-ios", "location": RUNTIME_URL, "state": {"revision": "b" * 40, "branch": "main"}}]}))
        report = self.verify()
        self.assertViolation("mutable-runtime-reference", report)
        self.assertViolation("mutable-resolved-reference", report)
        self.assertViolation("resolved-commit-mismatch", report)

    def test_declared_full_revision_must_match_pin_and_expected_commit_without_ref_argument(self):
        self.write("Package.swift", PACKAGE.replace('exact: "1.0.0"', 'revision: "' + "b" * 40 + '"'))
        report = self.verify("--runtime-commit", COMMIT, expectations=False)
        self.assertViolation("declared-commit-mismatch", report)
        self.assertViolation("declared-resolved-commit-mismatch", report)
        self.write("Package.swift", PACKAGE.replace('exact: "1.0.0"', 'revision: "' + COMMIT + '"'))
        self.assertTrue(self.verify("--runtime-commit", COMMIT, expectations=False)["ok"])

    def test_declared_full_revision_and_exact_version_checked_against_resolution_without_expectations(self):
        self.write("Package.swift", PACKAGE.replace('exact: "1.0.0"', 'revision: "' + "b" * 40 + '"'))
        self.assertViolation("declared-resolved-commit-mismatch", self.verify(expectations=False))
        self.write("Package.swift", PACKAGE.replace('exact: "1.0.0"', 'exact: "2.0.0"'))
        self.assertViolation("declared-resolved-version-mismatch", self.verify(expectations=False))

    def test_untracked_resolution_metadata_is_still_inspected(self):
        self.command("git", "rm", "--cached", "Package.resolved")
        report = self.verify()
        self.assertTrue(report["ok"], json.dumps(report, indent=2))
        self.assertEqual(report["checks"]["resolvedPins"][0]["state"]["revision"], COMMIT)

    def test_local_forsetti_mirror_override_rejected_even_if_untracked(self):
        self.write(".swiftpm/configuration/mirrors.json", json.dumps({"version": 1, "object": [{"original": RUNTIME_URL, "mirror": "file:///tmp/renamed-runtime"}]}))
        self.assertViolation("runtime-mirror-override", self.verify())

    def test_import_requires_owning_target_product(self):
        self.write("Package.swift", PACKAGE.replace('        .product(name: "ForsettiPlatform", package: "Forsetti-Framework-Mac-iOS"),\n', ""))
        self.assertViolation("missing-target-product", self.verify())

    def test_manifest_must_be_declared_resource(self):
        self.write("Package.swift", PACKAGE.replace(', resources: [.copy("Resources/ForsettiManifests")]', ""))
        self.assertViolation("manifest-resource-membership", self.verify())

    def test_forbidden_resource_membership_detects_untracked_files(self):
        self.write("Sources/Consumer/Resources/ForsettiManifests/TemplateInfo.plist", "<plist/>")
        self.assertViolation("development-asset", self.verify())

    def test_source_membership_detects_untracked_runtime_copy(self):
        self.write("Sources/Consumer/Hidden.swift", "public final class ForsettiHostController {}")
        self.assertViolation("runtime-implementation-copy", self.verify())

    def test_escaping_tracked_symlink_rejected(self):
        external = Path(self.temporary.name) / "Outside.swift"
        external.write_text("public final class ForsettiRuntime {}")
        (self.project / "Linked.swift").symlink_to(external)
        self.track("Linked.swift")
        self.assertViolation("escaping-path", self.verify())

    def test_built_resources_inspected_and_missing_manifests_rejected(self):
        bundle = Path(self.temporary.name) / "Built Consumer.app"
        resource = bundle / "Contents/Resources/ForsettiManifests/Consumer.json"
        resource.parent.mkdir(parents=True)
        resource.write_text(json.dumps(MANIFEST))
        report = self.verify("--bundle", str(bundle))
        self.assertTrue(report["ok"], json.dumps(report, indent=2))
        (bundle / "Contents/Resources/TemplateInfo.plist").write_text("<plist/>")
        self.assertViolation("development-asset", self.verify("--bundle", str(bundle)))
        (bundle / "Contents/Resources/TemplateInfo.plist").unlink()
        resource.unlink()
        self.assertViolation("missing-built-manifest", self.verify("--bundle", str(bundle)))

    def test_stale_built_manifest_fields_rejected_even_when_module_id_matches(self):
        bundle = Path(self.temporary.name) / "Built Consumer.app"
        resource = bundle / "Contents/Resources/ForsettiManifests/Consumer.json"
        resource.parent.mkdir(parents=True)
        changes = [
            {"entryPoint": "WrongEntryPoint"},
            {"capabilitiesRequested": ["secure_storage"]},
            {"runtimeRequirements": {"io": [], "dataIsolation": {"requiredDefaultRoles": ["shared_database"]}}},
        ]
        for change in changes:
            with self.subTest(change=change):
                resource.write_text(json.dumps(dict(MANIFEST, **change)))
                self.assertViolation("built-manifest-content-mismatch", self.verify("--bundle", str(bundle)))
        resource.write_text(json.dumps(MANIFEST, indent=4, sort_keys=True))
        self.assertTrue(self.verify("--bundle", str(bundle))["ok"])

    def test_extra_stale_manifest_cannot_hide_behind_another_correct_owning_bundle(self):
        bundle = Path(self.temporary.name) / "Built Consumer.app"
        good = bundle / "Contents/Resources/ForsettiManifests/Consumer.json"
        stale = bundle / "Contents/Resources/Module.bundle/ForsettiManifests/Consumer.json"
        for resource in (good, stale):
            resource.parent.mkdir(parents=True, exist_ok=True)
        good.write_text(json.dumps(MANIFEST))
        stale.write_text(json.dumps(dict(MANIFEST, entryPoint="StaleEntryPoint")))
        self.assertViolation("built-manifest-content-mismatch", self.verify("--bundle", str(bundle)))

    def test_built_bundle_escaping_symlink_rejected(self):
        bundle = Path(self.temporary.name) / "Consumer.app"
        bundle.mkdir()
        external = Path(self.temporary.name) / "External.txt"
        external.write_text("not an app resource")
        (bundle / "Escaped.txt").symlink_to(external)
        self.assertViolation("escaping-path", self.verify("--bundle", str(bundle)))

    def test_template_assets_and_maintenance_documents_rejected(self):
        self.write("Renamed/TemplateInfo.plist", "<plist/>")
        self.write("Support/framework-policy.json", "{}")
        self.track("Renamed", "Support")
        self.assertViolation("development-asset", self.verify())

    def test_gitlink_cannot_supply_runtime(self):
        self.write(".gitmodules", '[submodule "Renamed"]\n\tpath = Vendor/Renamed\n\turl = ' + RUNTIME_URL + '\n')
        self.track(".gitmodules")
        self.command("git", "update-index", "--add", "--cacheinfo", "160000," + COMMIT + ",Vendor/Renamed")
        self.assertViolation("submodule-membership", self.verify())

    def test_unrelated_uninitialized_gitlink_requires_review_without_false_runtime_violation(self):
        self.write(".gitmodules", '[submodule "MyForsettiAppModule"]\n\tpath = Vendor/MyForsettiAppModule\n\turl = https://github.com/owner/MyForsettiAppModule\n')
        self.track(".gitmodules")
        self.command("git", "update-index", "--add", "--cacheinfo", "160000," + COMMIT + ",Vendor/MyForsettiAppModule")
        report = self.verify()
        self.assertTrue(report["ok"], json.dumps(report, indent=2))
        self.assertIn("uninspected-gitlink", [entry["code"] for entry in report["warnings"]])

    def test_json_report_saved_independently_of_working_directory(self):
        destination = Path(self.temporary.name) / "Report with spaces.json"
        result = subprocess.run([str(VERIFIER), "--project", str(self.project), "--json", str(destination)], cwd="/", text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertTrue(json.loads(destination.read_text())["ok"])

    def test_invalid_project_is_cli_error(self):
        result = subprocess.run([str(VERIFIER), "--project", str(self.project / "Missing")], text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)

    @unittest.skipUnless(shutil.which("plutil"), "Native plutil required for Xcode project fixture")
    def test_xcode_explicit_target_membership_inspected(self):
        self.command("git", "rm", "--cached", "Package.swift")
        (self.project / "Package.swift").unlink()
        source = "Sources/Consumer/main.swift"
        resources = "Sources/Consumer/Resources/ForsettiManifests"
        pbx = '''{
            archiveVersion = 1; objectVersion = 56; rootObject = PROJECT;
            objects = {
                PROJECT = { isa = PBXProject; mainGroup = GROUP; targets = (TARGET); packageReferences = (REMOTE); };
                GROUP = { isa = PBXGroup; children = (SOURCE, RESOURCE); sourceTree = "<group>"; };
                SOURCE = { isa = PBXFileReference; path = "%s"; sourceTree = SOURCE_ROOT; };
                RESOURCE = { isa = PBXFileReference; path = "%s"; sourceTree = SOURCE_ROOT; lastKnownFileType = folder; };
                SOURCEBUILD = { isa = PBXBuildFile; fileRef = SOURCE; };
                RESOURCEBUILD = { isa = PBXBuildFile; fileRef = RESOURCE; };
                SOURCES = { isa = PBXSourcesBuildPhase; files = (SOURCEBUILD); };
                RESOURCES = { isa = PBXResourcesBuildPhase; files = (RESOURCEBUILD); };
                REMOTE = { isa = XCRemoteSwiftPackageReference; repositoryURL = "%s"; requirement = { kind = exactVersion; version = 1.0.0; }; };
                CORE = { isa = XCSwiftPackageProductDependency; package = REMOTE; productName = ForsettiCore; };
                PLATFORM = { isa = XCSwiftPackageProductDependency; package = REMOTE; productName = ForsettiPlatform; };
                HOST = { isa = XCSwiftPackageProductDependency; package = REMOTE; productName = ForsettiHostTemplate; };
                TARGET = { isa = PBXNativeTarget; name = Consumer; buildPhases = (SOURCES, RESOURCES); packageProductDependencies = (CORE, PLATFORM, HOST); };
            };
        }''' % (source, resources, RUNTIME_URL)
        path = self.write("Consumer.xcodeproj/project.pbxproj", pbx)
        self.track("Consumer.xcodeproj")
        report = self.verify()
        self.assertTrue(report["ok"], json.dumps(report, indent=2))
        self.assertEqual(report["checks"]["targets"][0]["sources"], [source])
        path.write_text(pbx.replace("files = (RESOURCEBUILD)", "files = ()"))
        self.assertViolation("manifest-resource-membership", self.verify())


if __name__ == "__main__":
    unittest.main()
