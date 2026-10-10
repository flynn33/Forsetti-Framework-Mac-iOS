#!/usr/bin/env python3
"""Verify the extracted archive inventory, canonical provenance, and consumer links."""

import argparse
import sys
from pathlib import Path

from forsetti_sdk import SDKError, SourceTree, read_archive, validate_payload, verify_checksum


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--checksums", type=Path, help="External SHA256SUMS; defaults to archive directory")
    parser.add_argument("--source-repo", type=Path, help="Verify every packaged input against recorded Git source tree")
    args = parser.parse_args()
    try:
        verify_checksum(args.archive, args.checksums or args.archive.parent / "SHA256SUMS")
        payload, modes, manifest = read_archive(args.archive)
        if args.source_repo:
            if manifest["sdk"]["releaseStatus"] == "development-candidate":
                raise SDKError("Development working-byte provenance cannot be certified against a Git source commit")
            tree = SourceTree(args.source_repo, manifest["source"]["commit"])
            validate_payload(payload, modes, tree)
        print(f"Verified {len(payload)} files: {args.archive}")
        print(f"SDK {manifest['sdk']['version']} ({manifest['sdk']['releaseStatus']}); runtime {manifest['runtime']['commit']}")
        print("Canonical source equality verified" if args.source_repo else "Canonical file hashes verified; source equality requires --source-repo")
        return 0
    except (SDKError, OSError, UnicodeDecodeError) as error:
        print(f"SDK verification failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
