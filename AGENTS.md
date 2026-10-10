# Repository Instructions

Classify the task before editing. This checkout is the Forsetti framework-maintenance repository. An explicit upstream maintenance request may change its implementation, approved templates, tools, and documentation after reading `REPOSITORY_RULES.md`, `EXECUTION_BRIEF.md`, `MODULE_BOUNDARY_RULES.md`, `implementation-policy.json`, and `CONSUMPTION_POLICY.md`.

Consumer application work belongs in an independent application repository. Use the released Forsetti SDK developer kit and its pinned remote runtime dependency. Start with the kit's `CONSUMPTION_POLICY.md`, `AGENTS.md`, and `Documentation/Getting-Started.md`. Do not copy this checkout into an app, recreate its internal targets, or patch package-manager caches. See [SDK/README.md](SDK/README.md) for the maintained consumer documentation source and [docs/sdk/releasing.md](docs/sdk/releasing.md) for maintainer packaging.

Preserve public product names and API boundaries. Keep canonical policies and templates authoritative in this repository; release packaging copies them from the recorded commit. SDK-specific documents live under `SDK/` and are development-kit assets, not shipping app resources.

Run the focused SDK tool tests, the existing repository guardrails, and relevant Apple-platform consumer checks before release. Keep compilation, actual runtime activation, simulator execution, and signed device installation as separate evidence. Record the tested source/runtime commits and unavailable checks. Publish only within the owner's authorization, preserve unrelated work, and verify local and remote refs after publication.
