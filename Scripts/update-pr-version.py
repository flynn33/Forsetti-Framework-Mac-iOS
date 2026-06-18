#!/usr/bin/env python3
import argparse
import os
import re
from pathlib import Path


HEADER_PATTERN = re.compile(
    r"^(?P<type>[a-z]+)(?:\([^)]+\))?(?P<breaking>!)?:\s*(?P<subject>.+)$"
)
VERSION_PATTERN = re.compile(r"^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)$")
SUPPORTED_TYPES = {
    "feat",
    "fix",
    "docs",
    "chore",
    "refactor",
    "test",
    "perf",
    "ci",
    "build",
    "style",
}


def parse_args():
    parser = argparse.ArgumentParser(
        description="Update Forsetti version files for a pull request."
    )
    parser.add_argument("--base-version", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--body-file")
    return parser.parse_args()


def parse_version(value):
    match = VERSION_PATTERN.match(value.strip())
    if not match:
        raise ValueError(f"Unsupported version format: {value}")
    return tuple(int(match.group(part)) for part in ("major", "minor", "patch"))


def next_version(base_version, bump):
    major, minor, patch = parse_version(base_version)
    if bump == "major":
        return f"{major + 1}.0.0"
    if bump == "minor":
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def read_body(path):
    if not path:
        return ""
    return Path(path).read_text(encoding="utf-8")


def classify(title, body):
    match = HEADER_PATTERN.match(title.strip())
    if not match:
        raise ValueError(
            "Pull request title must use conventional format, for example: feat: add module workflow"
        )

    pr_type = match.group("type")
    if pr_type not in SUPPORTED_TYPES:
        supported = ", ".join(sorted(SUPPORTED_TYPES))
        raise ValueError(f"Unsupported pull request type '{pr_type}'. Supported types: {supported}")

    if pr_type == "chore":
        return "skip", pr_type

    breaking = match.group("breaking") == "!" or re.search(
        r"(?m)^BREAKING[ -]CHANGE:\s+.+", body
    )
    if breaking:
        return "major", pr_type
    if pr_type == "feat":
        return "minor", pr_type
    return "patch", pr_type


def replace_once(path, pattern, replacement):
    file_path = Path(path)
    text = file_path.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise ValueError(f"Expected exactly one replacement in {path}")
    file_path.write_text(updated, encoding="utf-8")


def update_files(version):
    major, minor, patch = parse_version(version)

    Path("version.txt").write_text(f"{version}\n", encoding="utf-8")

    replace_once(
        "README.md",
        r"\*\*Current Version: [0-9]+\.[0-9]+\.[0-9]+\*\* <!-- x-release-please-version -->",
        f"**Current Version: {version}** <!-- x-release-please-version -->",
    )
    replace_once(
        "Sources/ForsettiCore/ForsettiVersion.swift",
        r"major: [0-9]+, // x-release-please-major",
        f"major: {major}, // x-release-please-major",
    )
    replace_once(
        "Sources/ForsettiCore/ForsettiVersion.swift",
        r"minor: [0-9]+, // x-release-please-minor",
        f"minor: {minor}, // x-release-please-minor",
    )
    replace_once(
        "Sources/ForsettiCore/ForsettiVersion.swift",
        r"patch: [0-9]+  // x-release-please-patch",
        f"patch: {patch}  // x-release-please-patch",
    )


def write_output(name, value):
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as output_file:
            output_file.write(f"{name}={value}\n")
    print(f"{name}={value}")


def main():
    args = parse_args()
    body = read_body(args.body_file)
    bump, pr_type = classify(args.title, body)

    write_output("type", pr_type)
    if bump == "skip":
        write_output("skipped", "true")
        return

    version = next_version(args.base_version, bump)
    update_files(version)
    write_output("skipped", "false")
    write_output("bump", bump)
    write_output("version", version)


if __name__ == "__main__":
    main()
