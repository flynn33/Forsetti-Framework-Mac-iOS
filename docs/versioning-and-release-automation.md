# Versioning and Release Automation

_Last updated: October 10, 2026_

Forsetti uses Semantic Versioning (`MAJOR.MINOR.PATCH`) for framework version numbers.
Version updates are intentionally reviewable because the runtime version participates in manifest compatibility checks.

## Version Sources

The current framework version is stored in three tracked surfaces:

| Surface | Purpose |
| --- | --- |
| `version.txt` | Plain text version used by version scripts. |
| `Sources/ForsettiCore/ForsettiVersion.swift` | Runtime value used by compatibility checks. |
| `README.md` | User-visible repository version marker. |

All three values must match. For SDK releases, `.release-please-manifest.json` is also aligned with that version and the assembled archive's metadata/root name. `release-please-config.json` is retained release configuration; neither file provides an active release workflow. See [SDK release maintenance](sdk/releasing.md).

## Removed PR Version Workflow

The `guardrails.yml`, `lint-pr.yml`, and `pr-version.yml` GitHub Actions workflows were removed on August 16, 2026 to stop runner spend (commits `31d362a`, `a732c38`, and `0097a42`).

Historically, the PR version workflow calculated a version from a same-repository PR's title/body and target-branch version, then pushed changed version files to the PR branch. That automation and its chore-version consistency check are no longer present.

## Retained Version Script

`Scripts/update-pr-version.py` remains available for explicit, manually reviewed use. It accepts `--base-version`, `--title`, and an optional `--body-file`, then updates the three version surfaces. It does not commit or push. Select the base version deliberately, inspect the resulting diff, and confirm all three values still match before committing.

### Script Bump Rules

| Supplied title/body signal | Bump | Example |
| --- | --- | --- |
| Breaking change marker on a non-`chore` type | Major | `feat!: replace manifest schema` |
| Feature | Minor | `feat: add module provider registry` |
| Fix, docs, refactor, test, CI, build, style, performance | Patch | `docs: expand lifecycle guide` |
| Repository chore | None | `chore: rotate workflow labels` |

The script accepts `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `perf`, `ci`, `build`, and `style`. It checks `chore:` first, returns `skipped=true`, and leaves version files unchanged. It does not compare them with a target branch or enforce PR consistency. The bump rules describe script behavior only; opening a PR does not run it.

## Release Handoff

Framework maintainers must keep the version files aligned through local review and verification.
Release publication, changelog maintenance, tags, and GitHub releases are handled as separate post-merge release work.

## Local Validation

Run these commands before publishing version script or release configuration changes:

```bash
python3 -m py_compile Scripts/update-pr-version.py
swift test --parallel --enable-code-coverage
swiftlint lint --strict --config .swiftlint.yml
./Scripts/verify-forsetti-guardrails.sh
```

For a script-only smoke test:

```bash
tmpdir="$(mktemp -d)"
cp -R version.txt README.md Sources "$tmpdir/"
(
  cd "$tmpdir"
  python3 "$OLDPWD/Scripts/update-pr-version.py" \
    --base-version 0.1.0 \
    --title "docs: align documentation surfaces"
)
```

The copied files should update to `0.1.1`. A `chore:` title should report `skipped=true` and leave the copied version files unchanged.
