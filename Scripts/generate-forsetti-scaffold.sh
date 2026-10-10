#!/usr/bin/env bash
set -euo pipefail

# Payloads and output paths come from the approved Xcode template definition.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 - "$SCRIPT_DIR/.." "$@" <<'PY'
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import sys

TEMPLATES = {
    "app": ("Forsetti App.xctemplate", "app-module", "AppModule"),
    "ui": ("Forsetti UI Module.xctemplate", "ui-module", "UIModule"),
    "service": ("Forsetti Service Module.xctemplate", "service-module", "ServiceModule"),
    "manifest": ("Forsetti Manifest.xctemplate", "module", "Module"),
}
KEYWORDS = set("associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private precedencegroup protocol public rethrows static struct subscript typealias var break case continue default defer do else fallthrough for guard if in repeat return switch where while as Any catch false is nil super self Self throw throws true try await actor nonisolated some any _".split())


def checked_path(raw):
    if not raw.strip():
        raise ValueError("output must not be empty")
    expanded = Path(os.path.expanduser(raw))
    if ".." in expanded.parts:
        raise ValueError("output must not contain '..' components")
    path = Path(os.path.abspath(expanded))
    for parent in (path, *path.parents):
        if parent.is_symlink():
            if str(parent) in ("/tmp", "/var") and str(parent.resolve()) == "/private" + str(parent):
                continue
            raise ValueError(f"output contains a symbolic link: {parent}")
        if parent.exists() and not parent.is_dir():
            raise ValueError(f"output ancestor is not a directory: {parent}")
    path = path.resolve()
    if path in {Path("/"), Path.home().resolve(), Path("/Users"), Path("/Library"),
                Path("/System"), Path("/Applications"), Path("/private"),
                Path("/private/tmp"), Path("/private/var")}:
        raise ValueError(f"unsafe output directory: {path}")
    return path


def main():
    root = Path(sys.argv[1]).resolve()
    parser = argparse.ArgumentParser(description="Generate app-owned Swift and manifests from an approved Forsetti template. Writes a JSON inventory to stdout.")
    parser.add_argument("--template", required=True, choices=TEMPLATES)
    parser.add_argument("--name", required=True, help="Swift type/file prefix: ASCII identifier, excluding Swift keywords")
    parser.add_argument("--module-id", required=True, help="app-owned reverse-DNS module identity")
    parser.add_argument("--output", required=True, help="consumer output directory; existing generated files are never overwritten")
    parser.add_argument("--app-name", help="optional app display name, only for the app template")
    args = parser.parse_args(sys.argv[2:])
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,79}", args.name) or args.name in KEYWORDS:
        raise ValueError("--name must be a Swift-safe ASCII identifier of at most 80 characters and cannot be a Swift keyword")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*(\.[A-Za-z][A-Za-z0-9-]*)+", args.module_id):
        raise ValueError("--module-id must use reverse-DNS segments")
    if args.module_id.startswith(("forsetti.", "com.yourcompany.", "com.forsetti.")):
        raise ValueError("--module-id must be app-owned, not a reserved or sample Forsetti identity")
    if args.app_name is not None and args.template != "app":
        raise ValueError("--app-name is supported only by --template app")
    display_name = args.app_name if args.app_name is not None else args.name
    if not display_name.strip() or any(ord(character) < 32 or ord(character) == 127 for character in display_name):
        raise ValueError("display name must be nonblank and contain no control characters")

    output = checked_path(args.output)
    template_name, identity_suffix, type_suffix = TEMPLATES[args.template]
    template_path = root / "XcodeTemplates/Project Templates/Forsetti" / template_name
    for ancestor in (template_path, *template_path.parents):
        if ancestor == root:
            break
        if ancestor.is_symlink():
            raise ValueError(f"template source contains a symbolic link: {ancestor}")
    if template_path.is_symlink() or not template_path.is_dir():
        raise ValueError(f"template must be a real directory: {template_path}")
    for child in template_path.rglob("*"):
        if child.is_symlink() or not (child.is_file() or child.is_dir()):
            raise ValueError(f"template contains a symbolic link or special file: {child}")
    with (template_path / "TemplateInfo.plist").open("rb") as stream:
        definition = plistlib.load(stream)
    if not isinstance(definition, dict):
        raise ValueError("template definition must be a dictionary")
    nodes, definitions = definition.get("Nodes"), definition.get("Definitions")
    if not isinstance(nodes, list) or not isinstance(definitions, dict) or len(set(nodes)) != len(nodes) or set(nodes) != set(definitions):
        raise ValueError("template Nodes/Definitions must describe the same unique outputs")

    old_identity = "___PACKAGENAME:identifier___." + identity_suffix
    display_literal = json.dumps(display_name, ensure_ascii=False)[1:-1]

    def render(text):
        return (text.replace("com.yourcompany." + old_identity, args.module_id)
                .replace(old_identity, args.module_id)
                .replace("___PACKAGENAME:identifier___", args.name)
                .replace("___PACKAGENAME___", display_literal)
                .replace("___FILEHEADER___", "App-owned scaffold from the approved Forsetti template."))

    generated = {}
    source_files = []
    required = {"TemplateInfo.plist"}
    entry_point = args.name + type_suffix
    for node in nodes:
        if not isinstance(node, str) or not isinstance(definitions[node], dict):
            raise ValueError(f"invalid template node definition: {node}")
        payload = definitions[node].get("Path")
        if not isinstance(payload, str):
            raise ValueError(f"missing template payload path: {node}")
        source_relative = PurePosixPath(payload)
        destination_relative = PurePosixPath(render(node))
        for relative in (source_relative, destination_relative):
            if relative.is_absolute() or ".." in relative.parts or "\\" in str(relative) or relative.suffix not in (".swift", ".json"):
                raise ValueError(f"unsafe or unsupported scaffold path: {relative}")
        if destination_relative.as_posix() in generated:
            raise ValueError(f"duplicate generated output: {destination_relative}")
        required.add(source_relative.as_posix())
        source = template_path / source_relative
        text = render(source.read_text(encoding="utf-8"))
        if re.search(r"___[A-Z][A-Za-z0-9_:]*___", text) or "com.yourcompany." in text or "com.forsetti.iap." in text:
            raise ValueError(f"unresolved placeholder or sample identity in {source}")
        if source_relative.suffix == ".json":
            manifest = json.loads(text)
            if not isinstance(manifest, dict):
                raise ValueError(f"template manifest must be a JSON object: {source}")
            if manifest.get("moduleID") != args.module_id or manifest.get("entryPoint") != entry_point:
                raise ValueError(f"generated manifest identity mismatch: {destination_relative}")
            if manifest.get("iapProductID") is not None:
                raise ValueError(f"sample purchase identity in {destination_relative}")
            if destination_relative.parent.as_posix() != "Resources/ForsettiManifests":
                raise ValueError("manifest output must be under Resources/ForsettiManifests")
        generated[destination_relative.as_posix()] = text
        source_files.append(source.relative_to(root).as_posix())
    actual = {child.relative_to(template_path).as_posix() for child in template_path.rglob("*") if child.is_file()}
    if actual != required:
        raise ValueError(f"template payload mismatch: missing={sorted(required - actual)}, extra={sorted(actual - required)}")

    for relative in generated:
        target = output / relative
        checked_path(str(target.parent))
        if target.exists() or target.is_symlink():
            raise ValueError(f"refusing to overwrite existing output: {target}")
    manifests = output / "Resources/ForsettiManifests"
    if manifests.exists():
        for existing in manifests.glob("*.json"):
            if existing.is_symlink() or not existing.is_file():
                raise ValueError(f"unsafe existing manifest: {existing}")
            value = json.loads(existing.read_text(encoding="utf-8"))
            if not isinstance(value, dict):
                raise ValueError(f"existing manifest is not a JSON object: {existing}")
            if value.get("moduleID") == args.module_id or value.get("entryPoint") == entry_point:
                raise ValueError(f"module identity or entry point already exists in {existing}")

    created_files = []
    created_dirs = []
    try:
        for relative, text in generated.items():
            target = output / relative
            for parent in reversed((target.parent, *target.parent.parents)):
                if not parent.exists():
                    parent.mkdir()
                    created_dirs.append(parent)
            checked_path(str(target.parent))
            with target.open("x", encoding="utf-8", newline="\n") as stream:
                created_files.append(target)
                stream.write(text)
    except (OSError, ValueError):
        for target in reversed(created_files):
            target.unlink()
        for directory in reversed(created_dirs):
            directory.rmdir()
        raise
    print(json.dumps({"template": args.template, "module_id": args.module_id,
                      "entry_point": entry_point, "output": str(output),
                      "generated_files": sorted(generated), "source_files": sorted(source_files)}, indent=2))


try:
    main()
except (OSError, ValueError, KeyError, TypeError, plistlib.InvalidFileException) as error:
    print(f"Error: {error}", file=sys.stderr)
    sys.exit(1)
PY
