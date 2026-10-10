"""Shared development-only validation for the curated Forsetti SDK archive."""

import hashlib
import json
import os
import plistlib
import re
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urlsplit


RUNTIME_URL = "https://github.com/flynn33/Forsetti-Framework-Mac-iOS"
PRODUCTS = [
    {"name": "ForsettiCore", "target": "ForsettiCore", "dependencies": []},
    {"name": "ForsettiPlatform", "target": "ForsettiPlatform", "dependencies": ["ForsettiCore"]},
    {"name": "ForsettiHostTemplate", "target": "ForsettiHostTemplate", "dependencies": ["ForsettiCore", "ForsettiPlatform"]},
]
TEMPLATE_ROOT = "XcodeTemplates/Project Templates/Forsetti"
TEMPLATE_NAMES = (
    "Forsetti App.xctemplate", "Forsetti UI Module.xctemplate",
    "Forsetti Service Module.xctemplate", "Forsetti Manifest.xctemplate",
)
DOC_PATHS = (
    "README.md", "AGENTS.md", "Release-Notes.md", "Documentation/Getting-Started.md",
    "Documentation/Public-API.md", "Documentation/Module-Authoring.md",
    "Documentation/Compatibility.md", "Documentation/Source-References.md",
)
DOC_SOURCE_PATHS = {path: "SDK/" + ("Consumer-Instructions.md" if path == "AGENTS.md" else path) for path in DOC_PATHS}
CANONICAL_PATHS = ("CONSUMPTION_POLICY.md", "MODULE_BOUNDARY_RULES.md", "LICENSE")
SCRIPT_PATHS = tuple("Scripts/" + name for name in (
    "install-forsetti-xcode-template.sh", "uninstall-forsetti-xcode-template.sh",
    "generate-forsetti-scaffold.sh", "verify-forsetti-integration.sh",
))
RELEASE_CHECKS = (
    "payload", "tools", "generated-source", "clean-consumer", "macos-runtime",
    "ios-simulator-runtime", "multimodule-runtime", "rejection-runtime",
    "ios-device-build", "integration-boundary", "getting-started", "relevant-tests", "lint",
)
REQUIREMENTS = {
    "platforms": {"iOS": "17.0", "macOS": "14.0"},
    "swiftToolsVersion": "5.10",
    "developmentTools": {
        "bash": "Bash",
        "python": "Python 3.9 or newer",
        "xcode": "Apple Xcode with compatible iOS/macOS SDKs; actual versions recorded under verification",
    },
}
SEMVER = re.compile(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\Z")
SHA = re.compile(r"[a-f0-9]{40}\Z")


class SDKError(ValueError):
    pass


def run(*args, cwd=None):
    result = subprocess.run(args, cwd=cwd, capture_output=True, check=False)
    if result.returncode:
        raise SDKError(f"Command failed: {' '.join(map(str, args))}: {result.stderr.decode(errors='replace').strip()}")
    return result.stdout


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical_json(value):
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode()


def safe_path(path):
    if not isinstance(path, str) or not path or "\\" in path or "\x00" in path:
        raise SDKError(f"Invalid payload path: {path!r}")
    parts = path.split("/")
    if any(part in ("", ".", "..") for part in parts) or PurePosixPath(path).is_absolute():
        raise SDKError(f"Escaping or noncanonical payload path: {path!r}")
    return path


def load_json(data):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise SDKError(f"Duplicate JSON key: {key}")
            result[key] = value
        return result
    try:
        return json.loads(data, object_pairs_hook=pairs)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SDKError(f"Invalid JSON: {error}") from error


class SourceTree:
    """Read release inputs from one Git tree; working bytes require explicit development mode."""

    def __init__(self, repo, source_ref="HEAD", development=False):
        self.repo = Path(repo).resolve()
        self.ref = source_ref
        self.commit = run("git", "rev-parse", "--verify", source_ref + "^{commit}", cwd=self.repo).decode().strip()
        self.dirty = bool(run("git", "status", "--porcelain", "--untracked-files=all", cwd=self.repo))
        self.development = development
        if self.dirty and not development:
            raise SDKError("Release packaging requires a clean source worktree; use --development for an explicit candidate")
        self.entries = {}
        for record in run("git", "ls-tree", "-r", "-z", self.commit, cwd=self.repo).split(b"\x00"):
            if record:
                header, path = record.split(b"\t", 1)
                mode, kind, object_id = header.decode().split()
                self.entries[path.decode()] = (mode, kind, object_id)

    def paths(self, prefix=""):
        if not self.development:
            return sorted(path for path in self.entries if path.startswith(prefix))
        start = self.repo / prefix
        if start.is_symlink():
            raise SDKError(f"Symlink input is forbidden: {prefix}")
        if start.is_file():
            return [prefix]
        result = []
        for root, directories, files in os.walk(start, followlinks=False):
            for name in directories + files:
                path = Path(root) / name
                if path.is_symlink():
                    raise SDKError(f"Symlink input is forbidden: {path.relative_to(self.repo)}")
            result.extend((Path(root) / name).relative_to(self.repo).as_posix() for name in files)
        return sorted(result)

    def exists(self, path):
        return (self.repo / path).exists() if self.development else path in self.entries

    def read(self, path):
        safe_path(path)
        if self.development:
            absolute = self.repo / path
            if absolute.is_symlink() or any(parent.is_symlink() for parent in absolute.parents if parent != self.repo.parent):
                raise SDKError(f"Symlink input is forbidden: {path}")
            if not absolute.is_file():
                raise SDKError(f"Required source input is missing: {path}")
            return absolute.read_bytes()
        entry = self.entries.get(path)
        if not entry:
            raise SDKError(f"Required source input is missing at {self.commit}: {path}")
        mode, kind, object_id = entry
        if kind != "blob" or mode not in ("100644", "100755"):
            raise SDKError(f"Source input is not a regular file: {path} ({mode}, {kind})")
        return run("git", "cat-file", "blob", object_id, cwd=self.repo)


def validate_package(package_bytes):
    """Let the installed SwiftPM parse the selected manifest, rather than guessing Swift syntax."""
    with tempfile.TemporaryDirectory(prefix="forsetti-sdk-package-") as directory:
        Path(directory, "Package.swift").write_bytes(package_bytes)
        manifest = load_json(run("swift", "package", "dump-package", "--package-path", directory))
    products = [{"name": value["name"], "targets": value["targets"], "type": value["type"]} for value in manifest["products"]]
    expected = [{"name": item["name"], "targets": [item["target"]], "type": {"library": ["automatic"]}} for item in PRODUCTS]
    if manifest["name"] != "ForsettiFramework" or products != expected or manifest.get("dependencies"):
        raise SDKError("Package.swift product/dependency contract differs from the reviewed SDK allowlist")
    targets = {value["name"]: value for value in manifest["targets"]}
    for product in PRODUCTS:
        if product["target"] not in targets:
            raise SDKError(f"Package.swift is missing the approved target {product['target']}")
        dependencies = []
        for dependency in targets[product["target"]]["dependencies"]:
            by_name = dependency.get("byName")
            if not by_name:
                raise SDKError(f"Unreviewed dependency for {product['name']}")
            dependencies.append(by_name[0])
        if dependencies != product["dependencies"]:
            raise SDKError(f"Package.swift dependencies differ for {product['name']}")
    platforms = {item["platformName"]: item["version"] for item in manifest["platforms"]}
    if platforms != {"ios": "17.0", "macos": "14.0"} or manifest["toolsVersion"]["_version"] != "5.10.0":
        raise SDKError("Package.swift platform/toolchain requirements changed and require review")
    return REQUIREMENTS


def validate_version(tree):
    version = tree.read("version.txt").decode().strip()
    if not SEMVER.fullmatch(version):
        raise SDKError("version.txt must contain one release SemVer")
    swift = tree.read("Sources/ForsettiCore/ForsettiVersion.swift").decode()
    fields = []
    for field in ("major", "minor", "patch"):
        matches = re.findall(rf"{field}:\s*(\d+)\s*,?\s*// x-release-please-{field}", swift)
        if len(matches) != 1:
            raise SDKError(f"Missing or ambiguous runtime {field} version marker")
        fields.append(matches[0])
    marker = f"**Current Version: {version}** <!-- x-release-please-version -->"
    release_state = load_json(tree.read(".release-please-manifest.json"))
    if ".".join(fields) != version or marker not in tree.read("README.md").decode() or release_state.get(".") != version:
        raise SDKError("Runtime, README, version.txt, and release-state versions must agree")
    return version


def verified_runtime(tree, runtime_ref):
    if not SHA.fullmatch(runtime_ref) and not re.fullmatch(r"(?:refs/tags/)?v?\d+\.\d+\.\d+", runtime_ref):
        raise SDKError("--runtime-ref must be a complete commit SHA or immutable version tag")
    ref = runtime_ref if SHA.fullmatch(runtime_ref) or runtime_ref.startswith("refs/tags/") else "refs/tags/" + runtime_ref
    try:
        with tempfile.TemporaryDirectory(prefix="forsetti-runtime-") as directory:
            run("git", "init", "--quiet", directory)
            run("git", "fetch", "--quiet", "--no-tags", "--depth=1", RUNTIME_URL, ref, cwd=directory)
            commit = run("git", "rev-parse", "FETCH_HEAD^{commit}", cwd=directory).decode().strip()
            runtime_tree = SourceTree(directory, commit)
            version = validate_version(runtime_tree)
            requirements = validate_package(runtime_tree.read("Package.swift"))
        if SHA.fullmatch(runtime_ref) and commit != runtime_ref:
            raise SDKError("Remote resolved commit does not match the requested SHA")
        return {"packageName": "ForsettiFramework", "url": RUNTIME_URL, "ref": runtime_ref, "commit": commit, "remoteVerified": True}, version, requirements
    except SDKError:
        if not tree.development:
            raise
        runtime_tree = SourceTree(tree.repo, runtime_ref, development=runtime_ref == tree.commit)
        return {"packageName": "ForsettiFramework", "url": RUNTIME_URL, "ref": runtime_ref, "commit": runtime_tree.commit, "remoteVerified": False}, validate_version(runtime_tree), validate_package(runtime_tree.read("Package.swift"))


def template_record(path, read, paths):
    info_path = path + "/TemplateInfo.plist"
    try:
        info = plistlib.loads(read(info_path))
    except (plistlib.InvalidFileException, ValueError) as error:
        raise SDKError(f"Invalid template definition: {info_path}: {error}") from error
    if not isinstance(info, dict):
        raise SDKError(f"Template definition must be a dictionary: {info_path}")
    definitions = info.get("Definitions", {})
    nodes = info.get("Nodes", [])
    if not definitions or set(nodes) != set(definitions) or len(nodes) != len(set(nodes)):
        raise SDKError(f"Template nodes/definitions are inconsistent: {path}")
    expected = {info_path}
    for output, definition in definitions.items():
        safe_path(output)
        payload = safe_path(definition.get("Path", ""))
        if not payload.endswith((".swift", ".json")):
            raise SDKError(f"Unreviewed template payload type: {path}/{payload}")
        expected.add(path + "/" + payload)
    if set(paths) != expected:
        raise SDKError(f"Missing or unexpected template files: {path}: {sorted(set(paths) ^ expected)}")
    for file in sorted(expected):
        read(file)
    return {"path": path, "files": sorted(expected), "outputs": sorted(definitions)}


def collect_payload(tree, version, runtime):
    tokens = {"SDK_VERSION": version, "SOURCE_COMMIT": tree.commit, "RUNTIME_REF": runtime["ref"],
              "RUNTIME_COMMIT": runtime["commit"], "RUNTIME_URL": runtime["url"]}
    payload = {}
    for destination in DOC_PATHS:
        text = tree.read(DOC_SOURCE_PATHS[destination]).decode()
        for token, value in tokens.items():
            text = text.replace("@" + token + "@", value)
        if re.search(r"@[A-Z_]+@", text):
            raise SDKError(f"Unresolved documentation substitution: {destination}")
        payload[destination] = text.encode()
    canonical = list(CANONICAL_PATHS) + (["NOTICE"] if tree.exists("NOTICE") else [])
    for path in canonical + list(SCRIPT_PATHS):
        payload[path] = tree.read(path)
    template_files = tree.paths(TEMPLATE_ROOT + "/")
    templates = []
    expected_templates = set()
    for name in TEMPLATE_NAMES:
        path = TEMPLATE_ROOT + "/" + name
        record = template_record(path, tree.read, [file for file in template_files if file.startswith(path + "/")])
        templates.append(record)
        expected_templates.update(record["files"])
    if set(template_files) != expected_templates:
        raise SDKError(f"Unexpected template content: {sorted(set(template_files) - expected_templates)}")
    for path in sorted(expected_templates):
        payload[path] = tree.read(path)
    return payload, templates, canonical


def verification_report(path, version, source_commit, runtime_commit):
    if path is None:
        return {"testedEnvironments": [], "checks": []}
    report = load_json(Path(path).read_bytes())
    if not isinstance(report, dict):
        raise SDKError("Verification report must be a JSON object")
    for name, expected in (("version", version), ("sourceCommit", source_commit), ("runtimeCommit", runtime_commit)):
        if name in report and report[name] != expected:
            raise SDKError(f"Verification report {name} does not match packaged inputs")
    return validate_verification(report)


def validate_verification(report):
    if not isinstance(report, dict):
        raise SDKError("SDK verification metadata must be a JSON object")
    environments = report.get("testedEnvironments", [])
    checks = report.get("checks", [])
    if not isinstance(environments, list) or not isinstance(checks, list):
        raise SDKError("Verification report requires testedEnvironments and checks arrays")
    names = set()
    for check in checks:
        if not isinstance(check, dict) or not isinstance(check.get("name"), str) or not check["name"] or check.get("status") not in ("passed", "failed", "not-run") or not isinstance(check.get("details"), str) or not check["details"]:
            raise SDKError("Every verification check requires name, status, and concrete details")
        if check["name"] in names:
            raise SDKError(f"Duplicate verification check: {check['name']}")
        names.add(check["name"])
    for environment in environments:
        if not isinstance(environment, dict) or not isinstance(environment.get("name"), str) or not environment["name"]:
            raise SDKError("Every tested environment requires its actual name")
    return {"testedEnvironments": environments, "checks": checks}


def build_payload(tree, runtime, runtime_version, requirements, report=None):
    version = validate_version(tree)
    source_requirements = validate_package(tree.read("Package.swift"))
    if version != runtime_version or source_requirements != requirements:
        raise SDKError("SDK source and resolved runtime version/requirements must agree")
    payload, templates, canonical = collect_payload(tree, version, runtime)
    verification = verification_report(report, version, tree.commit, runtime["commit"])
    passed = {check["name"] for check in verification["checks"] if check["status"] == "passed"}
    status = "unverified-candidate"
    failed = any(check["status"] == "failed" for check in verification["checks"])
    if set(RELEASE_CHECKS) <= passed and not failed and verification["testedEnvironments"] and runtime["remoteVerified"]:
        status = "release"
    if tree.development:
        status = "development-candidate"
    inventory = [{"path": path, "sha256": digest(payload[path]), "mode": "0755" if path in SCRIPT_PATHS else "0644"} for path in sorted(payload)]
    manifest = {
        "schemaVersion": 1,
        "sdk": {"name": "Forsetti SDK for macOS and iOS", "version": version, "releaseStatus": status},
        "source": {"commit": tree.commit, "ref": tree.ref, "dirty": tree.dirty},
        "runtime": runtime, "products": PRODUCTS, "templates": templates,
        "provenance": {"canonicalFiles": [{"sourcePath": path, "sdkPath": path, "sha256": digest(payload[path])} for path in canonical]},
        "inventory": inventory, "inventoryExcludes": ["sdk-manifest.json"],
        "requirements": requirements, "verification": verification,
    }
    payload["sdk-manifest.json"] = canonical_json(manifest)
    validate_payload(payload, {path: "0755" if path in SCRIPT_PATHS else "0644" for path in payload}, tree)
    return payload, manifest


def validate_links(payload, manifest):
    references = payload["Documentation/Source-References.md"].decode()
    upstream_prefix = RUNTIME_URL + "/blob/" + manifest["source"]["commit"] + "/"
    canonical = {entry["sdkPath"] for entry in manifest["provenance"]["canonicalFiles"]}
    for path, data in payload.items():
        if not path.endswith(".md"):
            continue
        text = data.decode()
        if re.search(r"@[A-Z_]+@", text):
            raise SDKError(f"Unresolved documentation placeholder in {path}")
        for match in re.finditer(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+[^)]*)?\)", text):
            target = match.group(1).strip("<>")
            parsed = urlsplit(target)
            if parsed.scheme or target.startswith("#"):
                continue
            decoded = unquote(parsed.path)
            joined = os.path.normpath(str(PurePosixPath(path).parent / decoded)).replace(os.sep, "/")
            if joined in payload:
                continue
            if path in canonical and upstream_prefix + joined in references:
                continue
            raise SDKError(f"Broken SDK-local documentation link: {path} -> {target}")
    if upstream_prefix + "Package.swift" not in references:
        raise SDKError("Source-References.md must map the policy's Package.swift reference to its immutable source URL")


def validate_payload(payload, modes, source_tree=None):
    if "sdk-manifest.json" not in payload:
        raise SDKError("Required sdk-manifest.json is missing")
    manifest = load_json(payload["sdk-manifest.json"])
    try:
        version = manifest["sdk"]["version"]
        if manifest["schemaVersion"] != 1 or not SEMVER.fullmatch(version) or manifest["sdk"]["name"] != "Forsetti SDK for macOS and iOS":
            raise SDKError("Unsupported SDK metadata schema/name/version")
        if not SHA.fullmatch(manifest["source"]["commit"]) or not SHA.fullmatch(manifest["runtime"]["commit"]):
            raise SDKError("SDK source/runtime commits must be full immutable SHAs")
        if type(manifest["source"]["dirty"]) is not bool or type(manifest["runtime"]["remoteVerified"]) is not bool:
            raise SDKError("SDK source dirty and runtime remoteVerified metadata must be boolean")
        if manifest["runtime"]["url"] != RUNTIME_URL or manifest["runtime"]["packageName"] != "ForsettiFramework":
            raise SDKError("SDK runtime package identity differs from the approved dependency")
        runtime_ref = manifest["runtime"]["ref"]
        if not SHA.fullmatch(runtime_ref) and not re.fullmatch(r"(?:refs/tags/)?v?" + re.escape(version), runtime_ref):
            raise SDKError("Runtime reference must be a full SHA or a version-aligned release tag")
        if SHA.fullmatch(runtime_ref) and runtime_ref != manifest["runtime"]["commit"]:
            raise SDKError("Runtime SHA reference/resolved commit mismatch")
        if manifest["products"] != PRODUCTS:
            raise SDKError("SDK products/dependencies differ from the approved allowlist")
        if manifest["requirements"] != REQUIREMENTS:
            raise SDKError("SDK platform/toolchain requirements require review")
        status = manifest["sdk"]["releaseStatus"]
        if status not in ("release", "unverified-candidate", "development-candidate"):
            raise SDKError("Invalid SDK release status")
        verification = validate_verification(manifest["verification"])
        if status == "release":
            passed = {check["name"] for check in verification["checks"] if check["status"] == "passed"}
            failed = any(check["status"] == "failed" for check in verification["checks"])
            if manifest["source"]["dirty"] or not manifest["runtime"]["remoteVerified"] or not set(RELEASE_CHECKS) <= passed or failed or not verification["testedEnvironments"]:
                raise SDKError("Release SDK lacks clean verified runtime and required environment/check evidence")
        if status == "unverified-candidate" and manifest["source"]["dirty"]:
            raise SDKError("Dirty source must be marked development-candidate")
        expected = set(DOC_PATHS + CANONICAL_PATHS + SCRIPT_PATHS) | {"sdk-manifest.json"}
        if "NOTICE" in payload:
            expected.add("NOTICE")
        templates = []
        for name in TEMPLATE_NAMES:
            path = TEMPLATE_ROOT + "/" + name
            record = template_record(path, lambda file: payload[file], [file for file in payload if file.startswith(path + "/")])
            templates.append(record)
            expected.update(record["files"])
        if templates != manifest["templates"]:
            raise SDKError("Template metadata does not match packaged definitions")
        if set(payload) != expected:
            raise SDKError(f"Missing or unexpected SDK payload: {sorted(set(payload) ^ expected)}")
        for path in expected:
            safe_path(path)
            expected_mode = "0755" if path in SCRIPT_PATHS else "0644"
            if modes[path] != expected_mode:
                raise SDKError(f"Wrong payload permissions: {path}: expected {expected_mode}")
        if manifest["inventoryExcludes"] != ["sdk-manifest.json"]:
            raise SDKError("Manifest hash inventory must exclude only its own metadata file")
        inventory = [{"path": path, "sha256": digest(payload[path]), "mode": modes[path]} for path in sorted(expected - {"sdk-manifest.json"})]
        if inventory != manifest["inventory"]:
            raise SDKError("SDK included-file inventory or hashes differ from the actual payload")
        canonical = list(CANONICAL_PATHS) + (["NOTICE"] if "NOTICE" in payload else [])
        provenance = [{"sourcePath": path, "sdkPath": path, "sha256": digest(payload[path])} for path in canonical]
        if manifest["provenance"]["canonicalFiles"] != provenance:
            raise SDKError("Canonical policy/license provenance differs from the packaged bytes")
        validate_links(payload, manifest)
        if source_tree is not None:
            if source_tree.commit != manifest["source"]["commit"] or validate_version(source_tree) != version:
                raise SDKError("Source repository does not match SDK source/version metadata")
            validate_package(source_tree.read("Package.swift"))
            authoritative, authoritative_templates, _ = collect_payload(source_tree, version, manifest["runtime"])
            for path, data in authoritative.items():
                if payload[path] != data:
                    raise SDKError(f"Packaged file differs from its recorded source input: {path}")
            if authoritative_templates != manifest["templates"]:
                raise SDKError("Template source provenance differs")
    except (KeyError, TypeError, AttributeError) as error:
        raise SDKError(f"Missing or invalid SDK metadata/payload field: {error}") from error
    return manifest


def archive_bytes(payload, version):
    import io
    buffer = io.BytesIO()
    root = "Forsetti-SDK-" + version
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(payload):
            info = zipfile.ZipInfo(root + "/" + path, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            mode = 0o755 if path in SCRIPT_PATHS else 0o644
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, payload[path], compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    return buffer.getvalue()


def read_archive(path):
    payload, modes, roots = {}, {}, set()
    try:
        with zipfile.ZipFile(path) as archive:
            if sum(item.file_size for item in archive.infolist()) > 100 * 1024 * 1024:
                raise SDKError("SDK archive exceeds the reviewed payload size limit")
            for info in archive.infolist():
                safe_path(info.filename)
                if info.is_dir() or "/" not in info.filename:
                    raise SDKError(f"SDK ZIP must contain only files below one versioned root: {info.filename}")
                root, relative = info.filename.split("/", 1)
                roots.add(root)
                if relative in payload:
                    raise SDKError(f"Duplicate archive member: {info.filename}")
                mode = info.external_attr >> 16
                if stat.S_IFMT(mode) != stat.S_IFREG:
                    raise SDKError(f"Nonregular ZIP member (including symlink): {info.filename}")
                if info.date_time != (1980, 1, 1, 0, 0, 0):
                    raise SDKError(f"Nonreproducible ZIP timestamp: {info.filename}")
                payload[relative] = archive.read(info)
                modes[relative] = f"{stat.S_IMODE(mode):04o}"
    except (OSError, zipfile.BadZipFile, RuntimeError) as error:
        raise SDKError(f"Unable to read SDK archive: {error}") from error
    manifest = validate_payload(payload, modes)
    if roots != {"Forsetti-SDK-" + manifest["sdk"]["version"]}:
        raise SDKError("Archive root and SDK version disagree")
    return payload, modes, manifest


def verify_checksum(archive, checksums):
    lines = Path(checksums).read_text().splitlines()
    entries = []
    for line in lines:
        match = re.fullmatch(r"([a-f0-9]{64})  ([^/\\]+)", line)
        if not match:
            raise SDKError(f"Invalid SHA256SUMS entry: {line!r}")
        entries.append(match.groups())
    matches = [checksum for checksum, name in entries if name == Path(archive).name]
    if len(matches) != 1 or matches[0] != digest(Path(archive).read_bytes()):
        raise SDKError("External archive checksum is missing, duplicated, or incorrect")
