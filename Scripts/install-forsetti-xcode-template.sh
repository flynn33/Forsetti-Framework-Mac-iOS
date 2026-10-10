#!/usr/bin/env bash
set -euo pipefail

# Installs the four approved templates from a checkout or extracted SDK.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 - "$SCRIPT_DIR/.." "$@" <<'PY'
import argparse
import os
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import sys
import tempfile

TEMPLATES = (
    "Forsetti App.xctemplate",
    "Forsetti UI Module.xctemplate",
    "Forsetti Service Module.xctemplate",
    "Forsetti Manifest.xctemplate",
)


def safe_destination(raw):
    if not raw.strip():
        raise ValueError("destination must not be empty")
    expanded = Path(os.path.expanduser(raw))
    if ".." in expanded.parts:
        raise ValueError("destination must not contain '..' components")
    path = Path(os.path.abspath(expanded))
    for part in (path, *path.parents):
        if part.is_symlink():
            # These are macOS system aliases, not user-controlled redirects.
            if str(part) in ("/tmp", "/var") and str(part.resolve()) == "/private" + str(part):
                continue
            raise ValueError(f"destination contains a symbolic link: {part}")
        if part.exists() and not part.is_dir():
            raise ValueError(f"destination ancestor is not a directory: {part}")
    path = path.resolve()
    if path in {Path("/"), Path.home().resolve(), Path("/Users"), Path("/Library"),
                Path("/System"), Path("/Applications"), Path("/private"),
                Path("/private/tmp"), Path("/private/var")}:
        raise ValueError(f"unsafe template destination: {path}")
    return path


def validate_tree(path):
    if path.is_symlink() or not path.is_dir():
        raise ValueError(f"template path must be a real directory: {path}")
    for child in path.rglob("*"):
        if child.is_symlink() or not (child.is_file() or child.is_dir()):
            raise ValueError(f"template contains a symbolic link or special file: {child}")


def validate_source(path):
    validate_tree(path)
    with (path / "TemplateInfo.plist").open("rb") as stream:
        definition = plistlib.load(stream)
    if not isinstance(definition, dict):
        raise ValueError(f"template definition must be a dictionary: {path}")
    nodes = definition.get("Nodes")
    definitions = definition.get("Definitions")
    if not isinstance(nodes, list) or not isinstance(definitions, dict) or len(set(nodes)) != len(nodes) or set(nodes) != set(definitions):
        raise ValueError(f"invalid template Nodes/Definitions: {path}")
    required = {"TemplateInfo.plist"}
    for node in nodes:
        if not isinstance(node, str) or not isinstance(definitions[node], dict):
            raise ValueError(f"invalid template node definition: {node}")
        output = PurePosixPath(node)
        if output.is_absolute() or ".." in output.parts or "\\" in node or output.suffix not in (".swift", ".json"):
            raise ValueError(f"unsafe or unsupported template output: {node}")
        payload = definitions[node].get("Path")
        if not isinstance(payload, str):
            raise ValueError(f"missing template payload path: {node}")
        relative = PurePosixPath(payload)
        if relative.is_absolute() or ".." in relative.parts or "\\" in payload or relative.suffix not in (".swift", ".json"):
            raise ValueError(f"unsafe or unsupported template payload: {payload}")
        required.add(relative.as_posix())
    actual = {child.relative_to(path).as_posix() for child in path.rglob("*") if child.is_file()}
    if required != actual:
        raise ValueError(f"template payload mismatch in {path}: missing={sorted(required - actual)}, extra={sorted(actual - required)}")
    allowed_dirs = {parent.as_posix() for file in required for parent in PurePosixPath(file).parents if parent.as_posix() != "."}
    actual_dirs = {child.relative_to(path).as_posix() for child in path.rglob("*") if child.is_dir()}
    if actual_dirs != allowed_dirs:
        raise ValueError(f"template has unexpected directories: {sorted(actual_dirs - allowed_dirs)}")


def main():
    root = Path(sys.argv[1]).resolve()
    parser = argparse.ArgumentParser(description="Install only the four approved Forsetti Xcode templates.")
    parser.add_argument("--destination", default=str(Path.home() / "Library/Developer/Xcode/Templates/Project Templates/Forsetti"),
                        help="Forsetti template category directory (the templates are its direct children)")
    args = parser.parse_args(sys.argv[2:])
    destination = safe_destination(args.destination)
    sources = root / "XcodeTemplates/Project Templates/Forsetti"
    for ancestor in (sources, *sources.parents):
        if ancestor == root:
            break
        if ancestor.is_symlink():
            raise ValueError(f"template source contains a symbolic link: {ancestor}")
    for name in TEMPLATES:
        validate_source(sources / name)
        target = destination / name
        if target.exists() or target.is_symlink():
            validate_tree(target)

    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".forsetti-install-", dir=destination) as staging_name:
        staging = Path(staging_name)
        for name in TEMPLATES:
            shutil.copytree(sources / name, staging / name)
        for index, name in enumerate(TEMPLATES):
            target = destination / name
            backup = staging / f"previous-{index}"
            if target.exists():
                target.rename(backup)
            try:
                (staging / name).rename(target)
            except OSError:
                if backup.exists():
                    backup.rename(target)
                raise
    print(f"Installed Forsetti templates in {destination}")
    for name in TEMPLATES:
        print(f"  {name}")
    print("Quit and relaunch Xcode to refresh its template catalog.")


try:
    main()
except (OSError, ValueError, KeyError, TypeError, plistlib.InvalidFileException) as error:
    print(f"Error: {error}", file=sys.stderr)
    sys.exit(1)
PY
