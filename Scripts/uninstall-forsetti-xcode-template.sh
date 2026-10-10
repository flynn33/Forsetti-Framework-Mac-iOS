#!/usr/bin/env bash
set -euo pipefail

# Removes only the four approved template names; unrelated templates survive.
exec python3 - "$@" <<'PY'
import argparse
import os
from pathlib import Path
import shutil
import sys

TEMPLATES = (
    "Forsetti App.xctemplate",
    "Forsetti UI Module.xctemplate",
    "Forsetti Service Module.xctemplate",
    "Forsetti Manifest.xctemplate",
)


def destination_path(raw):
    if not raw.strip():
        raise ValueError("destination must not be empty")
    expanded = Path(os.path.expanduser(raw))
    if ".." in expanded.parts:
        raise ValueError("destination must not contain '..' components")
    path = Path(os.path.abspath(expanded))
    for part in (path, *path.parents):
        if part.is_symlink():
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


def main():
    parser = argparse.ArgumentParser(description="Uninstall only the four approved Forsetti Xcode templates.")
    parser.add_argument("--destination", default=str(Path.home() / "Library/Developer/Xcode/Templates/Project Templates/Forsetti"),
                        help="Forsetti template category directory used for installation")
    destination = destination_path(parser.parse_args().destination)
    targets = []
    for name in TEMPLATES:
        target = destination / name
        if target.is_symlink():
            raise ValueError(f"refusing symbolic-link template: {target}")
        if not target.exists():
            continue
        if not target.is_dir():
            raise ValueError(f"template is not a directory: {target}")
        for child in target.rglob("*"):
            if child.is_symlink() or not (child.is_file() or child.is_dir()):
                raise ValueError(f"template contains a symbolic link or special file: {child}")
        targets.append(target)
    for target in targets:
        shutil.rmtree(target)
    if destination.is_dir() and not any(destination.iterdir()):
        destination.rmdir()
    print(f"Removed {len(targets)} Forsetti templates from {destination}")


try:
    main()
except (OSError, ValueError) as error:
    print(f"Error: {error}", file=sys.stderr)
    sys.exit(1)
PY
