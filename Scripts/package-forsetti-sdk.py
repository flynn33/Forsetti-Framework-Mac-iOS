#!/usr/bin/env python3
"""Assemble a versioned SDK from explicit authoritative inputs."""

import argparse
import sys
from pathlib import Path

from forsetti_sdk import SDKError, SourceTree, archive_bytes, build_payload, digest, verified_runtime


def main():
    repo = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=repo / "output/sdk", help="Ignored artifact directory (default: repository output/sdk)")
    parser.add_argument("--source-ref", default="HEAD", help="Selected source Git revision")
    parser.add_argument("--runtime-ref", required=True, help="Full immutable commit SHA or version tag, verified remotely")
    parser.add_argument("--verification-report", type=Path, help="JSON describing actual environments and checks")
    parser.add_argument("--development", action="store_true", help="Explicit candidate using working inputs; never a release")
    args = parser.parse_args()
    try:
        output = args.output.resolve()
        if output.is_relative_to(repo):
            relative = output.relative_to(repo)
            from forsetti_sdk import run
            try:
                result = run("git", "check-ignore", str(relative / "Forsetti-SDK-placeholder.zip"), cwd=repo)
            except SDKError as error:
                raise SDKError("Packaging output within the repository must be Git-ignored") from error
            if not result:
                raise SDKError("Packaging output within the repository must be Git-ignored")
        tree = SourceTree(repo, args.source_ref, args.development)
        runtime, runtime_version, requirements = verified_runtime(tree, args.runtime_ref)
        payload, manifest = build_payload(tree, runtime, runtime_version, requirements, args.verification_report)
        archive_name = "Forsetti-SDK-" + manifest["sdk"]["version"] + ".zip"
        data = archive_bytes(payload, manifest["sdk"]["version"])
        checksum = f"{digest(data)}  {archive_name}\n".encode()
        archive_path, checksum_path = output / archive_name, output / "SHA256SUMS"
        for path, contents in ((archive_path, data), (checksum_path, checksum)):
            if path.exists() and path.read_bytes() != contents:
                raise SDKError(f"Refusing to replace different existing release artifacts: {path}; use a fresh output directory")
        output.mkdir(parents=True, exist_ok=True)
        for path, contents in ((archive_path, data), (checksum_path, checksum)):
            if not path.exists():
                with path.open("xb") as destination:
                    destination.write(contents)
        print(f"{manifest['sdk']['releaseStatus']}: {archive_path}")
        print(f"SHA-256: {digest(data)}")
        print(f"source: {tree.commit}; runtime: {runtime['ref']} -> {runtime['commit']}")
        return 0
    except (SDKError, OSError, UnicodeDecodeError) as error:
        print(f"SDK packaging failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
