#!/usr/bin/env python3
"""Developer-only native Apple smoke harness for an extracted Forsetti SDK."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

PRODUCTS = ("ForsettiCore", "ForsettiPlatform", "ForsettiHostTemplate")
RUNTIME_URL = "https://github.com/flynn33/Forsetti-Framework-Mac-iOS"
VARIANTS = {
    "single": {"name": "SDKSingle", "moduleID": "org.example.sdksmoke.single"},
    "multi": {"name": "SDKMulti", "moduleID": "org.example.sdksmoke.multi",
              "uiName": "SDKWorkspace", "uiID": "org.example.sdksmoke.workspace",
              "serviceName": "SDKBackground", "serviceID": "org.example.sdksmoke.background"},
    "rejection": {"name": "SDKRejected", "moduleID": "org.example.sdksmoke.rejected"},
}
CHECK_NAMES = ("generated-source", "clean-consumer", "macos-runtime", "ios-simulator-runtime",
               "multimodule-runtime", "rejection-runtime", "ios-device-build", "integration-boundary")


class SmokeError(ValueError):
    pass


def presentation_wait(value):
    try:
        seconds = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("--presentation-wait must be a finite nonnegative number of seconds") from error
    if not math.isfinite(seconds) or seconds < 0:
        raise argparse.ArgumentTypeError("--presentation-wait must be a finite nonnegative number of seconds")
    return seconds


def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def execute(arguments, cwd=None):
    result = subprocess.run(list(map(str, arguments)), cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        raise SmokeError(f"Command failed ({result.returncode}): {arguments}: {result.stderr.strip()}")
    return result.stdout


def replace_required(path, old, new):
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SmokeError(f"Expected generated scaffold text is missing in {path}: {old}")
    path.write_text(text.replace(old, new), encoding="utf-8")


def object_id(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def openstep(value, level=0):
    """Serialize the ordinary dictionaries/lists used by native .pbxproj files."""
    indent = "\t" * level
    if isinstance(value, dict):
        entries = ["\t" * (level + 1) + json.dumps(str(key)) + " = " + openstep(child, level + 1) + ";"
                   for key, child in value.items()]
        return "{\n" + "\n".join(entries) + "\n" + indent + "}"
    if isinstance(value, (list, tuple)):
        entries = ["\t" * (level + 1) + openstep(child, level + 1) + "," for child in value]
        return "(\n" + "\n".join(entries) + "\n" + indent + ")"
    return json.dumps(str(value), ensure_ascii=False)


def project_graph(name, bundle_id, source_files, runtime_url, runtime_commit):
    if runtime_url != RUNTIME_URL or not re.fullmatch(r"[0-9a-f]{40}", runtime_commit):
        raise SmokeError("Project must use the approved remote URL and a complete immutable revision")
    sources = sorted(source_files)
    if not sources or any(not file.endswith(".swift") or Path(file).is_absolute() or ".." in Path(file).parts for file in sources):
        raise SmokeError("Project source membership must name relative app-owned Swift files")
    objects = {}

    def add(key, isa, **fields):
        identifier = object_id(key)
        if identifier in objects:
            raise SmokeError(f"Duplicate project object: {key}")
        objects[identifier] = {"isa": isa, **fields}
        return identifier

    source_refs, source_builds = [], []
    for path in sources:
        ref = add("source:" + path, "PBXFileReference", lastKnownFileType="sourcecode.swift", path="App/" + path, sourceTree="<group>")
        source_refs.append(ref)
        source_builds.append(add("source-build:" + path, "PBXBuildFile", fileRef=ref))
    manifests = add("manifests", "PBXFileReference", lastKnownFileType="folder", path="App/Resources/ForsettiManifests", sourceTree="<group>")
    manifest_build = add("manifests-build", "PBXBuildFile", fileRef=manifests)
    product = add("application", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0,
                  path=name + ".app", sourceTree="BUILT_PRODUCTS_DIR")
    products_group = add("products-group", "PBXGroup", children=[product], name="Products", sourceTree="<group>")
    main_group = add("main-group", "PBXGroup", children=source_refs + [manifests, products_group], sourceTree="<group>")
    remote = add("remote-package", "XCRemoteSwiftPackageReference", repositoryURL=runtime_url,
                 requirement={"kind": "revision", "revision": runtime_commit})
    package_products, frameworks = [], []
    for product_name in PRODUCTS:
        dependency = add("package:" + product_name, "XCSwiftPackageProductDependency", package=remote, productName=product_name)
        package_products.append(dependency)
        frameworks.append(add("framework:" + product_name, "PBXBuildFile", productRef=dependency))
    source_phase = add("sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=source_builds, runOnlyForDeploymentPostprocessing=0)
    framework_phase = add("frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=frameworks, runOnlyForDeploymentPostprocessing=0)
    resource_phase = add("resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=[manifest_build], runOnlyForDeploymentPostprocessing=0)
    project_configs, target_configs = [], []
    for configuration in ("Debug", "Release"):
        common = {"CLANG_ENABLE_MODULES": "YES", "SWIFT_VERSION": "5.0", "MACOSX_DEPLOYMENT_TARGET": "14.0",
                  "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "CODE_SIGNING_ALLOWED": "NO", "CODE_SIGNING_REQUIRED": "NO",
                  "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if configuration == "Debug" else "-O"}
        if configuration == "Debug":
            common["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG $(inherited)"
        project_configs.append(add("project-config:" + configuration, "XCBuildConfiguration", buildSettings=common, name=configuration))
        target_settings = {"PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": bundle_id,
                           "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_KEY_CFBundleDisplayName": name,
                           "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.developer-tools",
                           "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
                           "INFOPLIST_KEY_UILaunchScreen_Generation": "YES", "CURRENT_PROJECT_VERSION": "1",
                           "MARKETING_VERSION": "1.0.0", "SUPPORTED_PLATFORMS": "macosx iphoneos iphonesimulator",
                           "SDKROOT": "auto", "SUPPORTS_MACCATALYST": "NO", "TARGETED_DEVICE_FAMILY": "1,2",
                           "ENABLE_APP_SANDBOX": "NO", "CODE_SIGN_IDENTITY": "", "CODE_SIGNING_ALLOWED": "NO",
                           "CODE_SIGNING_REQUIRED": "NO", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../Frameworks"]}
        target_configs.append(add("target-config:" + configuration, "XCBuildConfiguration", buildSettings=target_settings, name=configuration))
    project_config_list = add("project-config-list", "XCConfigurationList", buildConfigurations=project_configs,
                              defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")
    target_config_list = add("target-config-list", "XCConfigurationList", buildConfigurations=target_configs,
                             defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")
    target = add("app-target", "PBXNativeTarget", buildConfigurationList=target_config_list,
                 buildPhases=[source_phase, framework_phase, resource_phase], buildRules=[], dependencies=[], name=name,
                 packageProductDependencies=package_products, productName=name, productReference=product,
                 productType="com.apple.product-type.application")
    project = add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES"},
                  buildConfigurationList=project_config_list, compatibilityVersion="Xcode 14.0", developmentRegion="en",
                  hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main_group, productRefGroup=products_group,
                  packageReferences=[remote], projectDirPath="", projectRoot="", targets=[target])
    return {"archiveVersion": "1", "classes": {}, "objectVersion": "60", "objects": objects, "rootObject": project}, target


def write_project(directory, name, bundle_id, source_files, runtime_url, runtime_commit):
    graph, target = project_graph(name, bundle_id, source_files, runtime_url, runtime_commit)
    project = directory / (name + ".xcodeproj")
    schemes = project / "xcshareddata/xcschemes"
    schemes.mkdir(parents=True)
    path = project / "project.pbxproj"
    path.write_text("// !$*UTF8*$!\n" + openstep(graph) + "\n", encoding="utf-8")
    execute(["plutil", "-lint", path])
    scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")

    def reference(parent):
        ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=target,
                      BuildableName=name + ".app", BlueprintName=name, ReferencedContainer="container:" + name + ".xcodeproj")

    build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(build, "BuildActionEntries")
    entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES",
                          buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")
    reference(entry)
    launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", launchStyle="0", useCustomWorkingDirectory="NO")
    reference(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"))
    ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    ET.indent(scheme)
    ET.ElementTree(scheme).write(schemes / (name + ".xcscheme"), encoding="utf-8", xml_declaration=True)
    return project


def probe_source(name, variant):
    return '''import Foundation
import SwiftUI
import ForsettiCore
import ForsettiHostTemplate

@MainActor
enum ForsettiSDKSmokeProbe {
    static var registeredEntryPoints: [String] = []
    static var renderedViewID: String?
    private static var recorded = false

    static func capture(_ bootstrap: NAMEForsettiBootstrap) async {
        guard !recorded else { return }
        await bootstrap.bootForProduction()
        for _ in 0..<600 {
            switch bootstrap.productionState {
            case .failed:
                await write(bootstrap)
                return
            case .ready where renderedViewID != nil:
                await write(bootstrap)
                return
            default:
                do { try await Task.sleep(nanoseconds: 50_000_000) }
                catch { await write(bootstrap); return }
            }
        }
        await write(bootstrap)
    }

    private static func write(_ bootstrap: NAMEForsettiBootstrap) async {
        guard !recorded else { return }
        recorded = true
        let state: String
        switch bootstrap.productionState {
        case .idle: state = "idle"
        case .booting: state = "booting"
        case .ready: state = "ready"
        case .failed: state = "failed"
        }
        #if os(macOS)
        let platformName = "macOS"
        let receiptURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FORSETTI_SMOKE_REPORT"] ?? "")
        #else
        let platformName = "iOS"
        let receiptURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("forsetti-sdk-smoke.json")
        #endif
        let resourceNames = (Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "ForsettiManifests") ?? [])
            .map(\\.lastPathComponent).sorted()
        let receipt: [String: Any] = [
            "variant": "VARIANT", "platform": platformName,
            "processID": ProcessInfo.processInfo.processIdentifier,
            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
            "bootState": state, "isBooted": bootstrap.controller.isBooted,
            "discoveredModuleIDs": bootstrap.controller.runtime.moduleManager.discoveredManifests.map(\\.moduleID).sorted(),
            "registeredEntryPoints": registeredEntryPoints.sorted(),
            "activeUIModuleID": bootstrap.controller.activeUIModuleID as Any? ?? NSNull(),
            "enabledServiceModuleIDs": bootstrap.controller.enabledServiceModuleIDs.sorted(),
            "error": bootstrap.controller.errorMessage as Any? ?? NSNull(),
            "renderedViewID": renderedViewID as Any? ?? NSNull(),
            "resourceManifestFiles": resourceNames, "bundlePath": Bundle.main.bundleURL.path
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: receiptURL, options: .atomic)
        } catch {
            print("SDK smoke receipt write failed: \\(error)")
        }
    }
}
'''.replace("NAME", name).replace("VARIANT", variant)


def prepare_consumer(sdk, workdir, variant, runtime_commit):
    spec = VARIANTS[variant]
    name = spec["name"]
    directory = workdir / "Consumers" / variant
    if directory.exists():
        raise SmokeError(f"Consumer directory already exists; use a fresh --workdir: {directory}")
    sources = directory / "App"
    generator = sdk / "Scripts/generate-forsetti-scaffold.sh"
    inventories = []

    def generate(template, module_name, module_id):
        inventory = json.loads(execute([generator, "--template", template, "--name", module_name,
                                       "--module-id", module_id, "--output", sources], cwd=workdir))
        inventories.append(inventory)

    generate("app", name, spec["moduleID"])
    replace_required(sources / (name + "DeploymentMode.swift"), "= .development", "= .production")
    bootstrap = sources / (name + "ForsettiBootstrap.swift")
    content = sources / "ContentView.swift"
    view = sources / "AppModule" / (name + "AppModuleView.swift")
    view_id = "single-module-ui"
    if variant == "multi":
        generate("ui", spec["uiName"], spec["uiID"])
        generate("service", spec["serviceName"], spec["serviceID"])
        # These are only files just generated into this new consumer directory.
        (sources / "AppModule" / (name + "AppModule.swift")).unlink()
        view.unlink()
        (sources / "AppModule").rmdir()
        (sources / "Resources/ForsettiManifests" / (name + "AppModuleManifest.json")).unlink()
        registry = sources / (name + "ModuleRegistry.swift")
        old_registration = f"        try registry.register(entryPoint: {name}AppModule.Constants.entryPoint) {{\n            {name}AppModule()\n        }}"
        new_registration = "\n".join(f"        try registry.register(entryPoint: {module}.Constants.entryPoint) {{\n            {module}()\n        }}"
                                     for module in (spec["uiName"] + "UIModule", spec["serviceName"] + "ServiceModule"))
        replace_required(registry, old_registration, new_registration)
        replace_required(bootstrap, name + "AppModule", spec["uiName"] + "UIModule")
        replace_required(bootstrap, ".Constants.primaryViewID", ".Constants.workspaceViewID")
        replace_required(bootstrap, f"moduleIDs: [{spec['uiName']}UIModule.Constants.moduleID]",
                         f"moduleIDs: [{spec['uiName']}UIModule.Constants.moduleID, {spec['serviceName']}ServiceModule.Constants.moduleID]")
        replace_required(content, name + "AppModuleView", spec["uiName"] + "UIModuleView")
        view = sources / (spec["uiName"] + "UIModuleView.swift")
        view_id = "dedicated-ui-module"
    if variant == "rejection":
        manifest = sources / "Resources/ForsettiManifests" / (name + "AppModuleManifest.json")
        value = json.loads(manifest.read_text())
        value["schemaVersion"] = "999.0"
        save_json(manifest, value)

    replace_required(bootstrap, "        controller = ForsettiHostTemplateBootstrap.makeController(",
                     "        ForsettiSDKSmokeProbe.registeredEntryPoints = registry.registeredEntryPoints\n\n        controller = ForsettiHostTemplateBootstrap.makeController(")
    replace_required(content, "        }\n        #else\n        MissingForsettiProductsView()",
                     "        }\n        .task { await ForsettiSDKSmokeProbe.capture(bootstrap) }\n        #else\n        MissingForsettiProductsView()")
    replace_required(view, "\n    }\n}\n\n#Preview {",
                     f'\n        .onAppear {{ ForsettiSDKSmokeProbe.renderedViewID = "{view_id}" }}\n        .accessibilityIdentifier("forsetti-sdk-smoke-{view_id}")\n    }}\n}}\n\n#Preview {{')
    (sources / "SDKSmokeProbe.swift").write_text(probe_source(name, variant), encoding="utf-8")
    swift_files = sorted(file.relative_to(sources).as_posix() for file in sources.rglob("*.swift"))
    manifests = sorted(file.relative_to(sources).as_posix() for file in sources.rglob("*.json"))
    bundle_id = "org.example.forsetti.sdk-smoke." + variant
    metadata = json.loads((sdk / "sdk-manifest.json").read_text())
    project = write_project(directory, name, bundle_id, swift_files, metadata["runtime"]["url"], runtime_commit)
    (directory / ".gitignore").write_text(".DS_Store\nxcuserdata/\n.build/\nDerivedData/\n", encoding="utf-8")
    execute(["git", "init", "-q", directory])
    execute(["git", "add", "App", project.name, ".gitignore"], cwd=directory)
    tracked = execute(["git", "ls-files"], cwd=directory).splitlines()
    return {"variant": variant, "name": name, "bundleID": bundle_id, "directory": str(directory),
            "project": str(project), "sources": swift_files, "manifests": manifests, "trackedFiles": tracked,
            "generatorInventories": inventories, "runtimeCommit": runtime_commit}


class Runner:
    def __init__(self, workdir):
        self.workdir = workdir
        self.commands = []
        self.failure_check = "generated-source"

    def run(self, arguments, label, cwd=None, env=None, timeout=1200, capture_details=None):
        log = self.workdir / "Logs" / (label + ".log")
        log.parent.mkdir(parents=True, exist_ok=True)
        command = list(map(str, arguments))
        print(f"==> {label}", flush=True)
        record = {"label": label, "command": command, "cwd": str(cwd or self.workdir), "log": str(log)}
        if capture_details is not None:
            record["capture"] = capture_details
        self.commands.append(record)
        try:
            with log.open("w", encoding="utf-8") as stream:
                process = subprocess.run(command, cwd=cwd or self.workdir, env=env, stdout=stream,
                                         stderr=subprocess.STDOUT, timeout=timeout)
            record["exitCode"] = process.returncode
            if process.returncode:
                raise SmokeError(f"{label} failed ({process.returncode}); see {log}")
            return log.read_text(encoding="utf-8", errors="replace")
        finally:
            save_json(self.workdir / "commands.json", self.commands)


def validate_receipt(receipt, variant, platform_name):
    spec = VARIANTS[variant]
    if receipt.get("variant") != variant or receipt.get("platform") != platform_name:
        raise SmokeError(f"Receipt variant/platform mismatch: {receipt}")
    expected_entries = [spec["name"] + "AppModule"]
    if variant == "multi":
        expected_entries = [spec["uiName"] + "UIModule", spec["serviceName"] + "ServiceModule"]
    if receipt.get("registeredEntryPoints") != sorted(expected_entries):
        raise SmokeError(f"Actual registry factories differ: {receipt.get('registeredEntryPoints')}")
    if variant == "rejection":
        if receipt.get("bootState") != "failed" or receipt.get("isBooted") or receipt.get("activeUIModuleID") is not None or receipt.get("renderedViewID") is not None:
            raise SmokeError(f"Invalid manifest bypassed rejection/production rendering gate: {receipt}")
        if "schemaVersion" not in (receipt.get("error") or ""):
            raise SmokeError(f"Rejection receipt does not name the invalid manifest schema: {receipt}")
        return
    expected_ui = spec["uiID"] if variant == "multi" else spec["moduleID"]
    expected_modules = sorted([spec["uiID"], spec["serviceID"]]) if variant == "multi" else [spec["moduleID"]]
    expected_services = [spec["serviceID"]] if variant == "multi" else []
    expected_view = "dedicated-ui-module" if variant == "multi" else "single-module-ui"
    if (receipt.get("bootState") != "ready" or not receipt.get("isBooted") or receipt.get("error") is not None
            or receipt.get("discoveredModuleIDs") != expected_modules or receipt.get("activeUIModuleID") != expected_ui
            or receipt.get("enabledServiceModuleIDs") != expected_services or receipt.get("renderedViewID") != expected_view
            or len(receipt.get("resourceManifestFiles", [])) != len(expected_modules)):
        raise SmokeError(f"Runtime/discovery/activation/rendering receipt failed: {receipt}")


def await_receipt(path, process=None, seconds=45):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if path.is_file():
            return json.loads(path.read_text())
        if process is not None and process.poll() is not None:
            raise SmokeError(f"Consumer exited ({process.returncode}) before writing {path}")
        time.sleep(0.1)
    raise SmokeError(f"Timed out waiting for actual app receipt: {path}")


def resolved_commit(consumer, expected):
    resolved = list(Path(consumer["project"]).rglob("Package.resolved"))
    if len(resolved) != 1:
        raise SmokeError(f"Expected one app-owned Package.resolved; found {resolved}")
    value = json.loads(resolved[0].read_text())
    pins = value.get("pins", value.get("object", {}).get("pins", []))
    if len(pins) != 1 or pins[0].get("state", {}).get("revision") != expected:
        raise SmokeError(f"Resolved runtime differs from immutable requested revision: {pins}")
    pin = pins[0]
    if (pin.get("location") or pin.get("repositoryURL")) != RUNTIME_URL:
        raise SmokeError(f"Resolved runtime URL differs: {pin}")
    execute(["git", "add", str(resolved[0].relative_to(Path(consumer["directory"])))], cwd=consumer["directory"])
    return {"path": str(resolved[0]), "pin": pin}


def build_consumer(runner, consumer, platform_name, runtime_commit):
    runner.failure_check = "ios-device-build" if platform_name == "device" else "generated-source"
    derived = runner.workdir / "DerivedData" / consumer["variant"]
    arguments = ["xcodebuild", "-project", consumer["project"], "-scheme", consumer["name"],
                 "-configuration", "Release" if platform_name == "device" else "Debug", "-derivedDataPath", derived,
                 "-clonedSourcePackagesDirPath", runner.workdir / "SourcePackages", "-packageCachePath", runner.workdir / "PackageCache",
                 "-disablePackageRepositoryCache", "-skipPackageUpdates", "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO"]
    destination = {"macos": "platform=macOS,arch=" + platform.machine(), "simulator": "generic/platform=iOS Simulator", "device": "generic/platform=iOS"}[platform_name]
    arguments += ["-destination", destination]
    if platform_name != "device":
        arguments += ["ARCHS=" + platform.machine(), "ONLY_ACTIVE_ARCH=YES"]
    arguments += ["build"]
    runner.run(arguments, consumer["variant"] + "-" + platform_name + "-build", cwd=consumer["directory"])
    resolved = resolved_commit(consumer, runtime_commit)
    checkout_root = runner.workdir / "SourcePackages/checkouts"
    checkouts = list(checkout_root.iterdir()) if checkout_root.is_dir() else []
    if len(checkouts) != 1 or not checkouts[0].is_dir():
        raise SmokeError(f"Expected one package-manager-managed remote checkout: {checkouts}")
    actual_revision = execute(["git", "rev-parse", "HEAD"], cwd=checkouts[0]).strip()
    checkout_changes = execute(["git", "status", "--porcelain", "--untracked-files=all"], cwd=checkouts[0]).strip()
    if actual_revision != runtime_commit or checkout_changes:
        raise SmokeError(f"Runtime checkout is not the exact unmodified resolved revision: {actual_revision}, changes={checkout_changes}")
    resolved["managedCheckout"] = str(checkouts[0])
    resolved["actualCheckoutCommit"] = actual_revision
    product_directory = {"macos": "Debug", "simulator": "Debug-iphonesimulator", "device": "Release-iphoneos"}[platform_name]
    bundle = derived / "Build/Products" / product_directory / (consumer["name"] + ".app")
    if not bundle.is_dir():
        raise SmokeError(f"Successful build did not produce expected application: {bundle}")
    manifest_folder = bundle / ("Contents/Resources/ForsettiManifests" if platform_name == "macos" else "ForsettiManifests")
    expected_names = sorted(Path(path).name for path in consumer["manifests"])
    if not manifest_folder.is_dir() or sorted(file.name for file in manifest_folder.iterdir()) != expected_names:
        raise SmokeError(f"Built manifest folder/membership differs: {manifest_folder}")
    runner.failure_check = "integration-boundary"
    runner.run([runner.sdk / "Scripts/verify-forsetti-integration.sh", "--project", consumer["directory"],
                "--runtime-commit", runtime_commit, "--bundle", bundle, "--json"],
               consumer["variant"] + "-" + platform_name + "-integration", cwd=consumer["directory"])
    return {"bundle": str(bundle), "resolvedRuntime": resolved, "manifestFolder": str(manifest_folder)}


def run_macos(runner, consumer, build):
    runner.failure_check = {"single": "macos-runtime", "multi": "multimodule-runtime", "rejection": "rejection-runtime"}[consumer["variant"]]
    receipt_path = runner.workdir / "Receipts" / (consumer["variant"] + "-macos.json")
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    executable = Path(build["bundle"]) / "Contents/MacOS" / consumer["name"]
    log = runner.workdir / "Logs" / (consumer["variant"] + "-macos-run.log")
    environment = os.environ.copy()
    environment["FORSETTI_SMOKE_REPORT"] = str(receipt_path)
    with log.open("w") as stream:
        process = subprocess.Popen([str(executable)], cwd=consumer["directory"], env=environment,
                                   stdout=stream, stderr=subprocess.STDOUT)
        record = {"label": consumer["variant"] + "-macos-launch", "command": [str(executable)],
                  "cwd": consumer["directory"], "log": str(log), "processID": process.pid,
                  "environment": {"FORSETTI_SMOKE_REPORT": str(receipt_path)}}
        runner.commands.append(record)
        try:
            receipt = await_receipt(receipt_path, process)
            validate_receipt(receipt, consumer["variant"], "macOS")
            if receipt["processID"] != process.pid:
                raise SmokeError("macOS receipt was not produced by the launched consumer process")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=10)
            record["exitCodeAfterOwnedProcessTermination"] = process.returncode
            save_json(runner.workdir / "commands.json", runner.commands)
    return {"receipt": str(receipt_path), "log": str(log), "observed": receipt}


def run_simulator(runner, consumer, build, simulator, device_set):
    runner.failure_check = {"single": "ios-simulator-runtime", "multi": "multimodule-runtime", "rejection": "rejection-runtime"}[consumer["variant"]]
    simctl = ["xcrun", "simctl", "--set", device_set]
    label = consumer["variant"] + "-ios"
    runner.run(simctl + ["install", simulator, build["bundle"]], label + "-install")
    data_container = Path(runner.run(simctl + ["get_app_container", simulator, consumer["bundleID"], "data"], label + "-container").strip())
    receipt_path = data_container / "Documents/forsetti-sdk-smoke.json"
    if receipt_path.exists():
        receipt_path.unlink()
    environment = os.environ.copy()
    launch_log = runner.run(simctl + ["launch", "--terminate-running-process", simulator, consumer["bundleID"]], label + "-launch", env=environment)
    match = re.search(r":\s*(\d+)\s*$", launch_log.strip())
    try:
        if not match:
            raise SmokeError(f"Simulator launch did not report the actual consumer process ID: {launch_log}")
        receipt = await_receipt(receipt_path)
        validate_receipt(receipt, consumer["variant"], "iOS")
        if receipt["processID"] != int(match.group(1)):
            raise SmokeError("iOS receipt was not produced by the launched consumer process")
        retained = runner.workdir / "Receipts" / (consumer["variant"] + "-ios.json")
        save_json(retained, receipt)
        screenshot = runner.workdir / "Screenshots" / (consumer["variant"] + "-ios.png")
        screenshot.parent.mkdir(parents=True, exist_ok=True)
        # The observed launch trace put module view appearance before the
        # simulator presentation transition completed. Review captured pixels.
        time.sleep(runner.presentation_wait)
        runner.run(simctl + ["io", simulator, "screenshot", screenshot], label + "-screenshot",
                   capture_details={"presentationWaitSeconds": runner.presentation_wait, "visualReview": "required"})
    finally:
        runner.run(simctl + ["terminate", simulator, consumer["bundleID"]], label + "-terminate")
    return {"receipt": str(retained), "simulatorContainer": str(data_container), "screenshot": str(screenshot), "observed": receipt}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", required=True, type=Path, help="extracted curated SDK directory")
    parser.add_argument("--workdir", required=True, type=Path, help="fresh work directory outside the framework checkout")
    parser.add_argument("--runtime-commit", required=True, help="qualified, remotely published immutable runtime SHA")
    parser.add_argument("--simulator", required=True, help="dedicated iOS Simulator UUID")
    parser.add_argument("--device-set", required=True, type=Path, help="dedicated custom simulator device-set directory")
    parser.add_argument("--report", type=Path, help="verification JSON; defaults to WORKDIR/consumer-verification.json")
    parser.add_argument("--presentation-wait", type=presentation_wait, default=5.0,
                        help="finite nonnegative seconds to wait before simulator screenshots (default: 5); visually review screenshots")
    parser.add_argument("--prepare-only", action="store_true", help="generate/validate projects without resolving or building the remote dependency")
    args = parser.parse_args()
    sdk, workdir, device_set = args.sdk.expanduser().resolve(), args.workdir.expanduser().resolve(), args.device_set.expanduser().resolve()
    repository = Path(__file__).resolve().parents[1]
    if workdir == repository or repository in workdir.parents or workdir == sdk or sdk in workdir.parents:
        parser.error("--workdir must be outside the framework checkout and extracted SDK")
    if not re.fullmatch(r"[a-f0-9]{40}", args.runtime_commit):
        parser.error("--runtime-commit must be a complete lowercase commit SHA")
    metadata = json.loads((sdk / "sdk-manifest.json").read_text())
    if metadata["runtime"]["commit"] != args.runtime_commit or metadata["runtime"]["url"] != RUNTIME_URL:
        parser.error("runtime arguments must match the extracted SDK's recorded remote dependency")
    if {product["name"] for product in metadata["products"]} != set(PRODUCTS):
        parser.error("SDK product inventory must match the three approved public products")
    for tool in ("git", "plutil", "xcodebuild", "xcrun"):
        if shutil.which(tool) is None:
            parser.error(f"required native tool is unavailable: {tool}")
    workdir.mkdir(parents=True, exist_ok=True)
    report_path = args.report.expanduser().resolve() if args.report else workdir / "consumer-verification.json"
    report = {"schemaVersion": 1, "version": metadata["sdk"]["version"], "sourceCommit": metadata["source"]["commit"],
              "runtimeCommit": args.runtime_commit, "sdk": str(sdk), "workdir": str(workdir), "testedEnvironments": [],
              "checks": [{"name": name, "status": "not-run", "details": "Native consumer verification has not reached this check."} for name in CHECK_NAMES],
              "consumers": {}, "limitations": ["Unsigned iOS device compilation is not signed device installation or physical-device acceptance.",
                                                  "The app-owned smoke probe observes real runtime fields and view appearance; it does not replace governance or exercise every application interaction."]}
    runner = Runner(workdir)
    runner.sdk = sdk
    runner.presentation_wait = args.presentation_wait
    def passed(name, details):
        next(check for check in report["checks"] if check["name"] == name).update(status="passed", details=details)
    try:
        report["testedEnvironments"].append({"name": "Native Apple consumer verification", "hostOS": platform.platform(),
                                            "architecture": platform.machine(), "xcode": execute(["xcodebuild", "-version"]).strip(),
                                            "swift": execute(["xcrun", "swift", "--version"]).strip(), "simulator": args.simulator,
                                            "deviceSet": str(device_set), "presentationWaitSeconds": args.presentation_wait})
        for variant in VARIANTS:
            report["consumers"][variant] = prepare_consumer(sdk, workdir, variant, args.runtime_commit)
        save_json(workdir / "consumer-projects.json", report["consumers"])
        if args.prepare_only:
            report["preparationOnly"] = True
            print(f"Generated three independent consumer projects. Native builds/runs were not requested; report: {report_path}")
            return 0
        simulator_state = json.loads(runner.run(["xcrun", "simctl", "--set", device_set, "list", "devices", "--json"], "simulator-inventory"))
        matches = [device for devices in simulator_state["devices"].values() for device in devices if device["udid"] == args.simulator]
        if len(matches) != 1 or not matches[0].get("isAvailable", False):
            raise SmokeError("Supplied simulator is unavailable in the dedicated custom device set")
        if matches[0]["state"] != "Booted":
            runner.run(["xcrun", "simctl", "--set", device_set, "boot", args.simulator], "simulator-boot")
        runner.run(["xcrun", "simctl", "--set", device_set, "bootstatus", args.simulator, "-b"], "simulator-bootstatus", timeout=240)
        report["testedEnvironments"][0]["simulatorDevice"] = matches[0]
        for variant, consumer in report["consumers"].items():
            consumer["builds"], consumer["runs"] = {}, {}
            for build_platform, runtime_platform in (("macos", "macOS"), ("simulator", "iOS")):
                build = build_consumer(runner, consumer, build_platform, args.runtime_commit)
                consumer["builds"][build_platform] = build
                consumer["runs"][runtime_platform] = (run_macos(runner, consumer, build) if build_platform == "macos" else
                                                       run_simulator(runner, consumer, build, args.simulator, device_set))
                save_json(report_path, report)
        passed("generated-source", "All extracted-template Swift sources and consumer adaptations compiled for macOS and iOS Simulator.")
        passed("clean-consumer", "Three independent Git-tracked app projects resolved the exact SDK-declared remote runtime revision; no local package override or framework source copy supplies application content.")
        passed("macos-runtime", "The generated production single-module app discovered, registered, activated, and displayed its app-owned UI on macOS; retained process-identified receipt.")
        passed("ios-simulator-runtime", "The generated production single-module app installed, launched, discovered, registered, activated, and displayed its app-owned UI on the dedicated iOS Simulator; retained receipt and native screenshot.")
        passed("multimodule-runtime", "Generated dedicated UI plus service modules both discovered and activated on macOS/iOS Simulator; the UI view appeared and exactly one UI module was selected.")
        passed("rejection-runtime", "Invalid manifest schema failed normal runtime boot on macOS/iOS Simulator; active UI and rendered-module view remained absent.")
        for variant, consumer in report["consumers"].items():
            consumer["builds"]["device"] = build_consumer(runner, consumer, "device", args.runtime_commit)
        passed("ios-device-build", "All three independent consumer configurations compiled for generic iOS devices with signing disabled; physical installation was not performed.")
        passed("integration-boundary", "The extracted consumer integration verifier passed tracked-source, package-pin, target/resource membership and built-bundle checks for all macOS, simulator and device variants.")
        print(f"All native consumer checks passed; report: {report_path}")
        return 0
    except (SmokeError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        report["failure"] = str(error)
        next(check for check in report["checks"] if check["name"] == runner.failure_check).update(status="failed", details=str(error))
        print(f"Error: {error}", file=sys.stderr)
        return 1
    finally:
        save_json(report_path, report)


if __name__ == "__main__":
    sys.exit(main())
