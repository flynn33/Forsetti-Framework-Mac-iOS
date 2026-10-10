#!/bin/bash
# Consumer verification; this tool is a development asset, never an app resource.
set -euo pipefail
exec /usr/bin/python3 - "$@" <<'PY'
import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

URL = "https://github.com/flynn33/Forsetti-Framework-Mac-iOS"
IDENTITY = "forsetti-framework-mac-ios"
PRODUCTS = {"ForsettiCore", "ForsettiPlatform", "ForsettiHostTemplate"}
CACHES = {".build", ".swiftpm", "DerivedData"}
MAINTENANCE = {
    "CONSUMPTION_POLICY.md", "MODULE_BOUNDARY_RULES.md", "IMPLEMENTATION_GUIDE.md",
    "EXECUTION_BRIEF.md", "REPOSITORY_RULES.md", "framework-policy.json",
    "implementation-policy.json", "sdk-manifest.json", "TemplateInfo.plist",
    "install-forsetti-xcode-template.sh", "uninstall-forsetti-xcode-template.sh",
    "generate-forsetti-scaffold.sh", "verify-forsetti-integration.sh",
    "verify-forsetti-guardrails.sh", "update-pr-version.py",
}
# Declarations identify implementation copies; references/imports are legitimate.
RUNTIME_TYPES = {
    "ForsettiRuntime", "ForsettiContext", "ForsettiModule", "ForsettiUIModule",
    "ForsettiAppModule", "ForsettiEntitlementProvider", "ForsettiServiceContainer",
    "ForsettiHostController", "ForsettiHostTemplateBootstrap", "ForsettiHostRootView",
    "ForsettiViewInjectionRegistry", "ForsettiVersion", "ForsettiStaticModuleRegistry",
    "ModuleManagerError", "ManifestLoaderError", "ModuleRegistryError",
    "CapabilityPolicyDecision", "ModuleRegistrationRecord", "UIContributions",
    "ModuleManifest", "ManifestTemplateVersion", "ModuleIORequirement",
}
# These paired implementation signatures survive file/directory/type renaming.
COPY_SIGNATURES = [
    ("private let manifestRootKeys", "validateRoleAndUIBoundary"),
    ("validateServiceRuntimeBoundary", "validateDefaultRoleDependency"),
    ("entitlementObservationTask", "startEntitlementObservation"),
    ("factories.keys.sorted()", "replacingExisting: Bool = false", "No module factory registered"),
    ("requiredDefaultRoles", "framework_mediated_shared", "ownedStoreIDs", "Codable"),
]
# Normalized-content fingerprints of the reviewed public runtime source inputs.
# These detect copies of generic helper types without reserving common consumer names.
# The all-runtime-files fixture guards this list when upstream implementation changes.
RUNTIME_HASHES = {
    "9ab631e2ba528337c95ba3c2fffa25a442b04b08e2edd51e4732094f8c92920f", # ForsettiLogger.swift
    "e11b97c13e6719a6cad134857c7c6c478c98183b2d1ca01848551a56606aa98c", # ForsettiEventBus.swift
    "50d9a92449b8146da2dbacbe9dac4d6c9d1e42fbabb18721022831d0dc7e4acc", # ForsettiVersion.swift
    "3cd62d4a398a8e10eb830c8a3230adf504c1dda32bf944d9a090ba6afb50dc48", # ModuleModels.swift
    "c49f178122f4d0f3270c1a469a7b5a64ab0e1ca03dc76add7af635f8f05ec53d", # SemVer.swift
    "e0f77bc40306d93d883155cae4f36b00abe7478525582ce229d7b8977663c0f7", # UIModels.swift
    "f4c7112e943326fbd89e2c5dfaf58ecd721722474cf8fd39f7224fee80f7e2b0", # ForsettiProtocols.swift
    "3c803ff89eb0b6e88da64ebb31f7bd3db966169e16532dfbf602e3055b7f5512", # ActivationStore.swift
    "64873be9d35c9d4978500d406abc46205b3b74c09d175fc0db9582370a24192c", # CapabilityPolicy.swift
    "7f4b54834f452c3cb92f92a182d1fa3afa4c7affbc2bde4829fc9ae8382c9d76", # CompatibilityChecker.swift
    "8164a6fdbb86241cdd9ccee95ffecb499f02a71815f62e30c4affdceb551c55b", # Core EntitlementProviders.swift
    "7b301140290835a4c533dc1926f98a7801d6594f3163efca738836eb6225f0bb", # ForsettiContext.swift
    "5627b95d93ad46fa73eb095936a3101fc2223f5437ba7ad0df63d6c1349bb3a8", # ForsettiRuntime.swift
    "d2ada2194ecdfda91b6297aca8245f1578aebbae70b755555179288f50d90b5b", # ForsettiStaticModuleRegistry.swift
    "047f97e97a00865ab27500234e68fab4236fd22386f3ea1f0a2b75019d4db5d7", # ManifestLoader.swift
    "b1a46e351f1be6e699ab3ca8c5728ed52312cf6197585d9d1300b589ba299120", # ModuleManager+UIValidation.swift
    "4a903510bcb831822728eab43354d86c5d5b408aaa9a296c360417ee69be12d0", # ModuleManager.swift
    "c336153a6c1d2f46ae7cd0a199f7ac747cd984c2052453ccab02cbce22d6a504", # ModuleRegistrationStore.swift
    "85c8062951921028ae38ed151361b4b4e63bf6ee85884a3fe7d3058adf9df1f4", # ModuleRegistry.swift
    "5922cf868b7a048c4a7e3c39d22584badb632d51929c2b1827fce13cfbc44373", # ForsettiServices.swift
    "4f0220dd8a5978d85770b363c6c1fa0e8bed1651f36294303c76a4fd5e6c4dc4", # UISurfaceManager.swift
    "08be30edbdba7f3edcbdc46d90c5b04c581ee63d6a97643f27b20d801eda0a6c", # ForsettiHostController.swift
    "730b3a79bb1b01c7c16650a6e199ac560eb9f708b978540c7bae9734f2717e1a", # ForsettiHostTemplateBootstrap.swift
    "999cc5eef12c1c646ba9a16edc668a0e4ddd4fc36aa3de8b248672403cd16c87", # ForsettiHostCatalogs.swift
    "c4d99aab3c872b9d858cd8e6fe2d7e254991ce4d53b8c85aff9155217dfda239", # ForsettiHostModuleItem.swift
    "d30712b5c7f2943e9ca2e84557a1475efb04b9c4c99237eb36d6a73772b7cd98", # ForsettiHostOverlayRouter.swift
    "cc380cb78a6cbec8b4f4f68d2da19053ed6eab9e1b2be503841696fee85f23c3", # ForsettiViewInjectionRegistry.swift
    "b48375a7a1ce23c4e92494be29d55300acf78af471b74bcaea7e310b22f39cc8", # ForsettiHostRootView.swift
    "0afc55040c4f07de98b986e88cfede2a820d3c0f325e01c30160c37d7e194876", # ForsettiModuleContributionsView.swift
    "8393ae2691f7a568a2d48ffdb5852c998e7f9fe61ba9e8befa1ea16614c52aa4", # ForsettiSettingsSheet.swift
    "b6ddc2f83657a7ae63ae2b4d1b350d579cb6d517df153d0a7673bfc0e9e8128c", # GuideInfoButton.swift
    "999f41656317b37c327a80a1f1051ef384c1942fef23376a9049dcb6cd7e1f00", # ModuleAvailabilityBadge.swift
    "2fa67eb1375a491e2222a742a4ec9f929155e3d65ea932a58988c44bd74d497a", # Platform EntitlementProviders.swift
    "76c93b5ea973cb23289e38c6805125444001fdd7272f57e898f545819933d757", # PlatformServices.swift
}

parser = argparse.ArgumentParser(description="Inspect independent consumer files, target membership, dependency pins, and optional built bundles. Requires system Python 3; Swift/Xcode tools are used when their project formats are present.")
parser.add_argument("--project", required=True, type=Path)
parser.add_argument("--bundle", action="append", default=[], type=Path, help="Built app/resource bundle; repeat for multiple owning bundles")
parser.add_argument("--runtime-ref", help="Expected exact runtime version tag/revision")
parser.add_argument("--runtime-commit", help="Expected full resolved runtime commit")
parser.add_argument("--json", nargs="?", const="-", metavar="PATH", help="Print JSON, or save it to PATH")
args = parser.parse_args()
project = args.project.expanduser().resolve()
if not project.is_dir():
    parser.error("--project must name an existing consumer directory")
if args.runtime_commit and not re.fullmatch(r"[0-9a-fA-F]{40}", args.runtime_commit):
    parser.error("--runtime-commit must be a full 40-character commit")
report = {
    "schemaVersion": 1, "ok": False, "project": str(project),
    "violations": [], "warnings": [],
    "checks": {"contentMode": None, "trackedFiles": 0, "selectedProducts": [],
               "dependencies": [], "targets": [], "resolvedPins": [], "bundles": [], "mirrorConfigurations": []},
    "limitations": [
        "Implementation signatures detect known copies, including renamed files/types; they cannot prove the absence of arbitrary rewritten framework code.",
        "SwiftPM membership comes from swift package dump-package; Xcode membership comes from its serialized project. Conditional manifests, build scripts, generated files and custom build settings require build review.",
        "Static resource membership does not prove which Bundle the application passes to ManifestLoader. Verify discovery/activation at runtime using the actual owning bundle.",
        "This check does not execute runtime governance, verify activation, inspect executable binary implementations, or establish platform compatibility.",
        "Recorded refs/commits are compared to supplied expectations; this verifier does not query the remote or certify that managed dependency checkout contents were never modified.",
    ],
}

def issue(code, path, message, warning=False):
    record = {"code": code, "path": str(path), "message": message}
    bucket = report["warnings" if warning else "violations"]
    if record not in bucket:
        bucket.append(record)

def run(command, cwd=None):
    return subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def relative(path):
    try:
        return str(path.relative_to(project))
    except ValueError:
        return str(path)

def beneath(path, root):
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except (ValueError, RuntimeError, OSError):
        return False

def swift_code(text):
    # Preserve string contents for identity checks; ignore comments for declarations/imports.
    pattern = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/', re.S)
    return pattern.sub(lambda m: " " if m.group(0).startswith(("//", "/*")) else m.group(0), text)

def read_text(path):
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return None
    except OSError as exc:
        issue("unreadable-file", relative(path), str(exc))
        return None

def inspect(path, owner_root=project, bundle=False, membership=False):
    label = str(path) if bundle else relative(path)
    if not beneath(path, owner_root):
        issue("escaping-path", label, "A tracked or declared source/resource path escapes its project/bundle; use app-owned files within that root.")
        return
    parts = path.relative_to(owner_root).parts
    if not bundle and any(part in CACHES for part in parts):
        issue("tracked-cache" if not membership else "cache-membership", label, "Managed caches may remain untracked, but must not be tracked or become target sources/resources.")
    if any(part.endswith(".xctemplate") or part == "XcodeTemplates" for part in parts) or path.name in MAINTENANCE or ".forsetti" in parts:
        issue("development-asset", label, "Remove SDK template metadata/tools or Forsetti maintenance assets from consumer tracked files and app targets/bundles. Keep the kit outside the consumer tree; retain required LICENSE/NOTICE files.")
    if any(part in PRODUCTS or part == "ForsettiModulesExample" for part in parts):
        issue("framework-tree", label, "This path recreates a framework implementation/internal example tree; depend on public remote products instead.")
    if "wiki" in path.name.lower() and path.suffix.lower() in {".zip", ".tar", ".gz"}:
        issue("wiki-archive", label, "Framework wiki archives are development references, not consumer assets.")
    if not path.is_file():
        if membership and not path.exists():
            issue("missing-member", label, "Declared source/resource does not exist.")
        return
    if path.suffix.lower() not in {".swift", ".json", ".md", ".sh", ".py", ".plist", ".pbxproj"}:
        return
    text = read_text(path)
    if text is None:
        return
    if path.suffix.lower() == ".swift":
        code = swift_code(text)
        tokens = re.sub(r'"(?:\\.|[^"\\])*"', '""', code)
        forbidden_imports = re.findall(r"\bimport\s+(Forsetti\w+)", tokens)
        for name in forbidden_imports:
            if name not in PRODUCTS:
                issue("unsupported-import", label, "Import {} is not a public Forsetti product; select only {}.".format(name, ", ".join(sorted(PRODUCTS))))
        declarations = set(re.findall(r"\b(?:class|struct|enum|actor|protocol)\s+(\w+)", tokens))
        copied = sorted(declarations & RUNTIME_TYPES)
        fingerprint = hashlib.sha256(re.sub(r"\s+", "", code).encode()).hexdigest()
        if copied or fingerprint in RUNTIME_HASHES or any(all(fragment in code for fragment in signature) for signature in COPY_SIGNATURES):
            issue("runtime-implementation-copy", label, "Framework implementation declaration/content signature found{}; remove the copy and import the remote public library.".format(": " + ", ".join(copied) if copied else ""))
        if re.search(r"\b(?:ExampleModuleResources|ExampleModuleRegistry|ExampleServiceModule|ExampleUIModule)\b", tokens):
            issue("internal-example", label, "Internal example symbols/resources are not consumer products; use generated app-owned modules and their owning bundle.")
        if "___" in code or "com.yourcompany." in code:
            issue("unresolved-scaffold", label, "Resolve scaffold placeholders and sample identities before adding source to the consumer.")
        if re.search(r"com\.forsetti\.(?:module|iap)\.example", code):
            issue("sample-identity", label, "Replace internal sample identities with app-owned identities.")
    elif path.suffix.lower() == ".json":
        if re.search(r"com\.forsetti\.(?:module|iap)\.example|___|com\.yourcompany\.", text):
            issue("sample-identity", label, "Resolve template placeholders/internal sample identities in app-owned manifests.")
    elif path.suffix.lower() == ".md" and path.name not in {"LICENSE", "NOTICE", "AGENTS.md"}:
        if re.search(r"^# Forsetti (?:Framework(?: Developer Guide)?|SDK|Xcode Template|Consumption Policy)(?:\s|$)", text, re.M):
            issue("copied-guidance", label, "Keep Forsetti development documentation in the external SDK rather than tracked consumer sources/resources.")

def walk(root, ignore_caches=False):
    for current, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d != ".git" and not (ignore_caches and d in CACHES))
        for directory in list(dirs):
            entry = Path(current) / directory
            if entry.is_symlink():
                yield entry
                dirs.remove(directory)
        for name in sorted(files):
            yield Path(current) / name

def local_is_forsetti_gitlink(path):
    manifest = path / "Package.swift"
    if manifest.is_file() and re.search(r'\bPackage\s*\(\s*name\s*:\s*"ForsettiFramework"|\.(?:library|executable)\s*\(\s*name\s*:\s*"(?:ForsettiCore|ForsettiPlatform|ForsettiHostTemplate|ForsettiModulesExample)"', swift_code(manifest.read_text(errors="replace"))):
        return True
    if path.is_dir() and shutil.which("git"):
        origin = run(["git", "-C", str(path), "config", "--get", "remote.origin.url"])
        return origin.returncode == 0 and origin.stdout.strip().rstrip("/").removesuffix(".git").lower().endswith("flynn33/forsetti-framework-mac-ios")
    return False

git = run(["git", "-C", str(project), "rev-parse", "--show-toplevel"]) if shutil.which("git") else None
if git and git.returncode == 0:
    git_root = Path(git.stdout.strip()).resolve()
    prefix = project.relative_to(git_root)
    listing = subprocess.run(["git", "-C", str(git_root), "ls-files", "--stage", "-z", "--", str(prefix)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if listing.returncode:
        issue("git-inventory", project, listing.stderr.decode(errors="replace"))
        files = []
    else:
        files = []
        forsetti_submodules = set()
        gitmodules = project / ".gitmodules"
        if gitmodules.is_file():
            config = configparser.ConfigParser()
            try:
                config.read(gitmodules)
                for section in config.sections():
                    if config.get(section, "url", fallback="").rstrip("/").removesuffix(".git").lower().endswith("flynn33/forsetti-framework-mac-ios"):
                        forsetti_submodules.add(config.get(section, "path", fallback=""))
            except configparser.Error as exc:
                issue("unreadable-submodules", gitmodules, str(exc))
        for item in listing.stdout.split(b"\0"):
            if not item:
                continue
            header, name = item.split(b"\t", 1)
            path = git_root / os.fsdecode(name)
            mode = header.split()[0]
            if mode == b"160000":
                if relative(path) in forsetti_submodules or local_is_forsetti_gitlink(path):
                    issue("submodule-membership", relative(path), "Forsetti must use its declared remote package, never an application submodule. Remove the Forsetti submodule.")
                else:
                    issue("uninspected-gitlink", relative(path), "Unrelated/uninitialized submodule contents were not scanned; inspect its identity and content separately.", warning=True)
            else:
                files.append(path)
        report["checks"]["contentMode"] = "git-tracked-working-files"
        report["checks"]["trackedFiles"] = len(files)
else:
    files = list(walk(project, ignore_caches=True))
    report["checks"]["contentMode"] = "filesystem-with-managed-caches-excluded"
    issue("no-git-inventory", project, "No Git inventory is available; scanned current files outside managed caches. Run again after recording consumer files in Git.", warning=True)
for path in files:
    inspect(path)
project_metadata = set(files)
# Available project metadata may not yet be staged. Managed dependency caches remain excluded.
project_metadata.update(path for path in walk(project, ignore_caches=True) if path.name in {"project.pbxproj", "Package.resolved", "mirrors.json"})
mirrors = {path for path in project_metadata if path.name == "mirrors.json"}
mirrors.update({project / ".swiftpm/configuration/mirrors.json", Path.home() / ".swiftpm/configuration/mirrors.json"})
for mirror in sorted(path for path in mirrors if path.is_file()):
    try:
        configuration = json.loads(mirror.read_text())
    except (ValueError, OSError) as exc:
        issue("unreadable-mirror-configuration", mirror, str(exc))
        continue
    report["checks"]["mirrorConfigurations"].append(str(mirror))
    for mapping in configuration.get("object", []):
        if not isinstance(mapping, dict):
            continue
        original = str(mapping.get("original", ""))
        replacement = str(mapping.get("mirror", ""))
        if "forsetti" in original.lower() and replacement.rstrip("/").removesuffix(".git").lower() != URL.lower():
            issue("runtime-mirror-override", mirror, "The Forsetti runtime has a mirror override. Remove it for supported canonical remote integration; a local/alternate mirror may supply hidden runtime content.")

selected = set()
resource_members = set()
manifest_members = {}
target_imports = []
declared_requirements = []

def add_member(path, kind, target, root=project):
    inspect(path, owner_root=root, membership=True)
    entries = list(walk(path)) if path.is_dir() else [path]
    for entry in entries:
        inspect(entry, owner_root=root, membership=True)
        if kind == "resource":
            resource_members.add(entry.resolve())
            if entry.suffix.lower() == ".json" and entry.is_file():
                try:
                    data = json.loads(entry.read_text())
                except (ValueError, OSError):
                    if "ForsettiManifests" in entry.parts:
                        issue("invalid-manifest-json", relative(entry), "Declared manifest resource must contain valid JSON.")
                    continue
                if isinstance(data, dict) and {"moduleID", "entryPoint", "schemaVersion"} <= data.keys():
                    manifest_members[entry.resolve()] = data
                    target.setdefault("manifests", []).append({"path": relative(entry), "moduleID": data["moduleID"], "entryPoint": data["entryPoint"]})
                    if "ForsettiManifests" not in entry.parts:
                        issue("manifest-layout", relative(entry), "Place app-owned manifest source resources in ForsettiManifests. The runtime has a flattened-resource fallback, but verify its owning bundle explicitly.", warning=True)
        elif kind == "source" and entry.suffix == ".swift" and entry.is_file():
            code = swift_code(entry.read_text())
            tokens = re.sub(r'"(?:\\.|[^"\\])*"', '""', code)
            target_imports.append((entry, set(re.findall(r"\bimport\s+(Forsetti\w+)", tokens)), target))

def verify_ref(requirement, path):
    if not requirement:
        issue("missing-runtime-pin", path, "Declare an immutable exact runtime version or revision, and record the resolved commit.")
        return
    kind, value = requirement
    declared_requirements.append((kind, value, str(path)))
    if kind not in {"exact", "revision"} or (kind == "revision" and not re.fullmatch(r"[0-9a-fA-F]{40}|v?\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?", value)):
        issue("mutable-runtime-reference", path, "Forsetti must use an exact release version or full commit/release tag, rather than a branch or version range.")
    if args.runtime_ref and value.lstrip("v") != args.runtime_ref.lstrip("v"):
        issue("runtime-ref-mismatch", path, "Declared runtime reference {} differs from expected {}.".format(value, args.runtime_ref))
    if kind == "revision" and re.fullmatch(r"[0-9a-fA-F]{40}", value) and args.runtime_commit and value.lower() != args.runtime_commit.lower():
        issue("declared-commit-mismatch", path, "Declared full runtime revision does not match --runtime-commit.")

def dependency_requirement(value):
    if not isinstance(value, dict):
        return None
    for kind in ("exact", "revision", "branch", "range"):
        if kind in value:
            raw = value[kind]
            return kind, str(raw[0]) if isinstance(raw, list) and raw else str(raw)
    return None

def local_is_forsetti(path):
    manifest = path / "Package.swift"
    if manifest.is_file():
        if shutil.which("swift"):
            dumped = run(["swift", "package", "--package-path", str(path), "dump-package"])
            try:
                declaration = json.loads(dumped.stdout) if dumped.returncode == 0 else None
            except ValueError:
                declaration = None
            if declaration:
                if declaration.get("name") == "ForsettiFramework" or any(product.get("name") in PRODUCTS | {"ForsettiModulesExample"} for product in declaration.get("products", [])):
                    return True
                for target in declaration.get("targets", []):
                    target_root = path / target.get("path", ("Tests/" if target.get("type") == "test" else "Sources/") + target.get("name", ""))
                    for source in walk(target_root, ignore_caches=True):
                        if source.suffix != ".swift" or not source.is_file():
                            continue
                        code = swift_code(source.read_text(errors="replace"))
                        tokens = re.sub(r'"(?:\\.|[^"\\])*"', '""', code)
                        declarations = set(re.findall(r"\b(?:class|struct|enum|actor|protocol)\s+(\w+)", tokens))
                        fingerprint = hashlib.sha256(re.sub(r"\s+", "", code).encode()).hexdigest()
                        if declarations & RUNTIME_TYPES or fingerprint in RUNTIME_HASHES or any(all(fragment in code for fragment in signature) for signature in COPY_SIGNATURES):
                            return True
                return False
        text = swift_code(manifest.read_text(errors="replace"))
        return bool(re.search(r'\bPackage\s*\(\s*name\s*:\s*"ForsettiFramework"|\.(?:library|executable)\s*\(\s*name\s*:\s*"(?:ForsettiCore|ForsettiPlatform|ForsettiHostTemplate|ForsettiModulesExample)"', text))
    if (path / ".git").exists() and shutil.which("git"):
        origin = run(["git", "-C", str(path), "config", "--get", "remote.origin.url"])
        return origin.returncode == 0 and origin.stdout.strip().rstrip("/").removesuffix(".git").lower() == URL.lower()
    return False

package = project / "Package.swift"
if package.is_file() and beneath(package, project):
    if not shutil.which("swift"):
        issue("swift-membership-unavailable", package, "Swift is required to read actual package declarations; install the supported Apple toolchain and rerun.")
    else:
        dumped = run(["swift", "package", "--package-path", str(project), "dump-package"])
        try:
            manifest = json.loads(dumped.stdout) if dumped.returncode == 0 else None
        except ValueError:
            manifest = None
        if manifest is None:
            issue("swift-manifest-unreadable", package, "Cannot inspect package declarations: " + dumped.stderr.strip())
        else:
            identities = set()
            for dependency in manifest.get("dependencies", []):
                if "fileSystem" in dependency:
                    for value in dependency["fileSystem"]:
                        local = Path(value.get("path", ""))
                        if local_is_forsetti(local):
                            issue("vendored-local-runtime", package, "Replace local Forsetti .package(path:) with the declared remote pinned dependency: " + str(local))
                for value in dependency.get("sourceControl", []):
                    identity = value.get("identity", "")
                    locations = value.get("location", {}).get("remote", [])
                    location = locations[0].get("urlString", "") if locations and isinstance(locations[0], dict) else (locations[0] if locations else "")
                    if identity == IDENTITY or "forsetti" in location.lower():
                        identities.add(identity)
                        requirement = dependency_requirement(value.get("requirement"))
                        report["checks"]["dependencies"].append({"manifest": relative(package), "identity": identity, "url": location, "requirement": requirement})
                        if location.rstrip("/").removesuffix(".git").lower() != URL.lower():
                            issue("runtime-url", package, "Use the canonical runtime URL " + URL)
                        verify_ref(requirement, package)
            for declaration in manifest.get("targets", []):
                name = declaration.get("name", "")
                target = {"manifest": "Package.swift", "name": name, "products": [], "sources": [], "resources": [], "manifests": []}
                if name in PRODUCTS | {"ForsettiModulesExample", "ForsettiFramework"}:
                    issue("internal-target", package, "Consumer target {} recreates a framework/internal target; use app-owned targets and remote products.".format(name))
                for dependency in declaration.get("dependencies", []):
                    values = dependency.get("product") or dependency.get("byName") or dependency.get("target") or []
                    if not values:
                        continue
                    product_name = values[0]
                    package_name = values[1] if "product" in dependency and len(values) > 1 else None
                    if product_name in PRODUCTS:
                        selected.add(product_name)
                        target["products"].append(product_name)
                        if not identities or (package_name and package_name.lower() not in identities):
                            issue("public-product-source", package, "{} must come from the canonical remote Forsetti package, not a local/substitute target.".format(product_name))
                    elif str(product_name).startswith("Forsetti") or (package_name and package_name.lower() in identities):
                        issue("unsupported-product", package, "Target {} selects unsupported Forsetti product {}.".format(name, product_name))
                root = project / declaration.get("path", ("Tests/" if declaration.get("type") == "test" else "Sources/") + name)
                if not beneath(root, project):
                    issue("escaping-target", relative(root), "Consumer target path escapes the independent project.")
                    continue
                resources = declaration.get("resources", [])
                excluded = [root / item for item in declaration.get("exclude", [])]
                for resource in resources:
                    member = root / resource["path"]
                    target["resources"].append(relative(member))
                    add_member(member, "resource", target)
                    if "process" in resource.get("rule", {}):
                        issue("processed-resource-layout", relative(member), "SwiftPM processing may flatten manifest directories. Verify the actual resource bundle and pass that owning bundle to the loader.", warning=True)
                declared_sources = declaration.get("sources")
                source_paths = [root / item for item in declared_sources] if declared_sources is not None else [path for path in walk(root) if path.suffix == ".swift" and not any(beneath(path, item) for item in excluded)]
                for source in source_paths:
                    target["sources"].append(relative(source))
                    add_member(source, "source", target)
                report["checks"]["targets"].append(target)

def pbx_read(path):
    tool = shutil.which("plutil")
    if not tool:
        issue("xcode-membership-unavailable", path, "Native plutil is required to inspect Xcode source/resource membership; rerun on macOS.")
        return None
    converted = run([tool, "-convert", "json", "-o", "-", str(path)])
    try:
        return json.loads(converted.stdout) if converted.returncode == 0 else None
    except ValueError:
        return None

for pbx in sorted(path for path in project_metadata if path.name == "project.pbxproj"):
    data = pbx_read(pbx)
    if data is None:
        issue("xcode-project-unreadable", relative(pbx), "Could not inspect serialized Xcode project with plutil.")
        continue
    objects = data.get("objects", {})
    base = pbx.parent.parent
    parents = {child: key for key, value in objects.items() for child in value.get("children", [])}

    def object_path(key, seen=None):
        seen = set() if seen is None else seen
        if key in seen:
            return None
        seen.add(key)
        value = objects.get(key, {})
        path = value.get("path", "")
        tree = value.get("sourceTree", "<group>")
        if "$" in path or tree not in {"<group>", "SOURCE_ROOT", "<absolute>"}:
            return None
        if tree == "<absolute>":
            return Path(path)
        parent = object_path(parents[key], seen) if tree == "<group>" and key in parents else base
        return parent / path if parent else None

    runtime_packages = set()
    for key, value in objects.items():
        if value.get("isa") == "XCLocalSwiftPackageReference":
            local = base / value.get("relativePath", "")
            if local_is_forsetti(local):
                issue("vendored-local-runtime", relative(pbx), "Replace local Forsetti Xcode package reference with its remote pinned dependency: " + str(local))
        if value.get("isa") == "XCRemoteSwiftPackageReference" and "forsetti" in value.get("repositoryURL", "").lower():
            runtime_packages.add(key)
            location = value["repositoryURL"]
            requirement = value.get("requirement", {})
            kind = {"exactVersion": "exact", "revision": "revision", "branch": "branch"}.get(requirement.get("kind"), "range")
            ref = requirement.get("version") or requirement.get("revision") or requirement.get("branch") or ""
            report["checks"]["dependencies"].append({"manifest": relative(pbx), "url": location, "requirement": [kind, ref]})
            if location.rstrip("/").removesuffix(".git").lower() != URL.lower():
                issue("runtime-url", relative(pbx), "Use the canonical runtime URL " + URL)
            verify_ref((kind, ref), relative(pbx))
    for key, value in objects.items():
        if value.get("isa") != "PBXNativeTarget":
            continue
        name = value.get("name", key)
        target = {"manifest": relative(pbx), "name": name, "products": [], "sources": [], "resources": [], "manifests": []}
        if name in PRODUCTS | {"ForsettiModulesExample", "ForsettiFramework"}:
            issue("internal-target", relative(pbx), "Consumer must not recreate Forsetti target " + name)
        for dependency_key in value.get("packageProductDependencies", []):
            dependency = objects.get(dependency_key, {})
            product_name = dependency.get("productName", "")
            if product_name in PRODUCTS:
                selected.add(product_name)
                target["products"].append(product_name)
                if dependency.get("package") not in runtime_packages:
                    issue("public-product-source", relative(pbx), product_name + " must come from the canonical remote runtime package.")
            elif product_name.startswith("Forsetti") or dependency.get("package") in runtime_packages:
                issue("unsupported-product", relative(pbx), "Target {} selects unsupported Forsetti product {}.".format(name, product_name))
        if value.get("fileSystemSynchronizedGroups"):
            issue("xcode-synchronized-membership", relative(pbx), "Synchronized folder target membership requires Xcode/build inspection; this verifier handles explicit PBX source/resource phases.")
        for phase_key in value.get("buildPhases", []):
            phase = objects.get(phase_key, {})
            kind = {"PBXSourcesBuildPhase": "source", "PBXResourcesBuildPhase": "resource"}.get(phase.get("isa"))
            if not kind:
                if phase.get("isa") == "PBXShellScriptBuildPhase":
                    issue("xcode-build-script", relative(pbx), "Build script outputs require independent inspection and built-bundle verification.", warning=True)
                continue
            for build_key in phase.get("files", []):
                reference = objects.get(build_key, {}).get("fileRef")
                member = object_path(reference) if reference else None
                if member is None:
                    issue("unresolved-membership", relative(pbx), "Cannot resolve target {} {} file reference {}; inspect its build settings/path.".format(name, kind, reference))
                    continue
                target["sources" if kind == "source" else "resources"].append(relative(member))
                add_member(member, kind, target)
        report["checks"]["targets"].append(target)

for path, imports, target in target_imports:
    for product in imports & PRODUCTS:
        if product not in target["products"]:
            issue("missing-target-product", relative(path), "Target {} imports {} but does not directly declare that remote product dependency.".format(target["name"], product))
for path in files:
    if path.suffix == ".json" and path.is_file():
        try:
            value = json.loads(path.read_text())
        except (ValueError, OSError):
            continue
        if isinstance(value, dict) and {"schemaVersion", "moduleID", "entryPoint"} <= value.keys() and path.resolve() not in resource_members:
            issue("manifest-resource-membership", relative(path), "App-owned manifest JSON is not a declared target resource; add it to the target that owns its bundle.")

for resolved in sorted(path for path in project_metadata if path.name == "Package.resolved"):
    try:
        value = json.loads(resolved.read_text())
    except (ValueError, OSError) as exc:
        issue("invalid-resolution", relative(resolved), str(exc))
        continue
    pins = value.get("pins", value.get("object", {}).get("pins", []))
    for pin in pins:
        location = pin.get("location", pin.get("repositoryURL", ""))
        if pin.get("identity", "").lower() != IDENTITY and "forsetti" not in location.lower():
            continue
        state = pin.get("state", {})
        report["checks"]["resolvedPins"].append({"path": relative(resolved), "url": location, "state": state})
        if location.rstrip("/").removesuffix(".git").lower() != URL.lower():
            issue("resolved-runtime-url", relative(resolved), "The runtime pin must resolve the canonical remote package.")
        revision = state.get("revision", "")
        if not re.fullmatch(r"[0-9a-fA-F]{40}", revision):
            issue("missing-resolved-commit", relative(resolved), "Record the exact full runtime commit in Package.resolved.")
        if state.get("branch"):
            issue("mutable-resolved-reference", relative(resolved), "The resolved runtime follows a branch; pin an immutable release.")
        if args.runtime_commit and revision.lower() != args.runtime_commit.lower():
            issue("resolved-commit-mismatch", relative(resolved), "Resolved runtime commit does not match --runtime-commit.")
        version = state.get("version")
        if args.runtime_ref and version and version.lstrip("v") != args.runtime_ref.lstrip("v"):
            issue("resolved-version-mismatch", relative(resolved), "Resolved runtime version does not match --runtime-ref.")
        for kind, declared, declaration_path in declared_requirements:
            if kind == "revision" and re.fullmatch(r"[0-9a-fA-F]{40}", declared):
                if declared.lower() != revision.lower():
                    issue("declared-resolved-commit-mismatch", relative(resolved), "Recorded runtime commit {} differs from the full revision {} declared in {}. Resolve that declaration before building.".format(revision, declared, declaration_path))
            elif kind == "exact":
                if not version or declared.lstrip("v") != version.lstrip("v"):
                    issue("declared-resolved-version-mismatch", relative(resolved), "Recorded runtime version {} differs from exact version {} declared in {}. Resolve that declaration before building.".format(version, declared, declaration_path))
            elif kind == "revision" and version and declared.lstrip("v") != version.lstrip("v"):
                issue("declared-resolved-version-mismatch", relative(resolved), "Recorded runtime version differs from the declared release tag in " + declaration_path)

report["checks"]["selectedProducts"] = sorted(selected)
if not report["checks"]["targets"]:
    issue("no-target-membership", project, "No Package.swift or explicit Xcode target membership could be inspected; provide the independent app project.")
if not report["checks"]["dependencies"]:
    issue("missing-remote-runtime", project, "No canonical remote Forsetti runtime dependency was declared.")
if not report["checks"]["resolvedPins"]:
    issue("unresolved-runtime", project, "No recorded Forsetti Package.resolved pin was inspected; resolve the declared dependency and record its exact commit.")

found_ids = set()
built_manifests = {}
for supplied in args.bundle:
    bundle = supplied.expanduser().resolve()
    if not bundle.is_dir():
        issue("missing-built-bundle", bundle, "Supply an existing built app or resource bundle.")
        continue
    summary = {"path": str(bundle), "manifests": []}
    owning_ids = {}
    for path in walk(bundle):
        inspect(path, owner_root=bundle, bundle=True)
        if path.suffix.lower() != ".json" or not path.is_file() or not beneath(path, bundle):
            continue
        try:
            manifest = json.loads(path.read_text())
        except (ValueError, OSError):
            if "ForsettiManifests" in path.parts:
                issue("invalid-built-manifest", path, "Built manifest resource is not valid JSON.")
            continue
        if not isinstance(manifest, dict) or not {"schemaVersion", "moduleID", "entryPoint"} <= manifest.keys():
            continue
        module_id = manifest["moduleID"]
        owner = next((parent for parent in path.parents if parent.suffix in {".bundle", ".app", ".framework"}), bundle)
        owner_key = (str(owner), module_id)
        if owner_key in owning_ids:
            issue("duplicate-built-manifest", path, "Duplicate module ID within owning bundle: " + module_id)
        owning_ids[owner_key] = path
        found_ids.add(module_id)
        built_manifests.setdefault(module_id, []).append((path, manifest))
        summary["manifests"].append({"path": str(path.relative_to(bundle)), "owningBundle": str(owner), "moduleID": module_id})
        if "ForsettiManifests" not in path.parts:
            issue("flattened-built-manifest", path, "Manifest is flattened; ManifestLoader supports fallback for manifest-shaped JSON. Exercise discovery with this actual owning bundle.", warning=True)
    report["checks"]["bundles"].append(summary)
if args.bundle:
    for path, manifest in manifest_members.items():
        if manifest["moduleID"] not in found_ids:
            issue("missing-built-manifest", relative(path), "Declared module {} is absent from supplied built bundles; verify resource target membership and the actual owning bundle.".format(manifest["moduleID"]))
        elif not any(built == manifest for _, built in built_manifests[manifest["moduleID"]]):
            issue("built-manifest-content-mismatch", relative(path), "Built module {} has different manifest fields from its declared app-owned source resource; rebuild and inspect entry point, capabilities, requirements, and identity.".format(manifest["moduleID"]))
    for module_id, built_entries in built_manifests.items():
        declared = [manifest for manifest in manifest_members.values() if manifest["moduleID"] == module_id]
        for path, built in built_entries:
            if not declared:
                issue("undeclared-built-manifest", path, "Built module {} has no declared app-owned source resource in the inspected project.".format(module_id))
            elif built not in declared:
                issue("built-manifest-content-mismatch", path, "Built manifest fields differ from every declared source manifest for module {}. Do not ship stale or altered manifest resources.".format(module_id))
else:
    issue("bundle-inspection-unrun", project, "No --bundle supplied; shipping resources were not inspected.", warning=True)
report["ok"] = not report["violations"]
serialized = json.dumps(report, indent=2, sort_keys=True) + "\n"
if args.json == "-":
    sys.stdout.write(serialized)
else:
    if args.json:
        output = Path(args.json).expanduser()
        try:
            output.write_text(serialized)
        except OSError as exc:
            parser.error("cannot write JSON report: " + str(exc))
    print("Forsetti consumer verification: {} ({} violations, {} warnings)".format("PASS" if report["ok"] else "FAIL", len(report["violations"]), len(report["warnings"])))
    for item in report["violations"]:
        print("ERROR [{}] {}: {}".format(item["code"], item["path"], item["message"]))
    for item in report["warnings"]:
        print("WARNING [{}] {}: {}".format(item["code"], item["path"], item["message"]))
    print("Coverage limitations:")
    for limitation in report["limitations"]:
        print("- " + limitation)
sys.exit(0 if report["ok"] else 1)
PY
