# Aston TV: shared agent instructions

Read CONTRIBUTING.md before editing. Use docs/mobile-roadmap.md for the inspected baseline, issue order and known gaps. CLAUDE.md points to these same rules; keep policy here rather than duplicating it.

## Product
Deliver Aston TV on Android and iPhone with the LG webOS/TV 7.1 visual identity, touch-friendly navigation, reliable fullscreen landscape, channels/EPG/favorites/history/search, pairing/settings and Dahua cameras. Native Android/iOS parity is a goal, not a verified current capability. Do not rename a build to 8.1 solely because a prior chat used that name.

## Repository map
- app/: root Java Android wrapper, application ID eu.astonserver.astontv.android.premium411 on the inspected main.
- mobile71/: separate Kotlin Android WebView project loading https://tv.astonserver.eu/tv6/.
- ios/: SwiftUI controls around WKWebView.
- ios-mobile5/: SwiftUI/AVPlayer client with gateway API calls.
- .github/workflows/: independent build targets; building one does not validate the others.
- codex/iphone-recovery: existing divergent branch with platform, gateway and test work. Inspect it through issue #1; never overwrite it.
- TV6 server HTML/CSS/JS and original LG references are not in the inspected main tree.

## Coordination
1. Read open issues, PRs and current remote heads. Claim one issue with session identity, exact branch, base SHA and owned files before changing them.
2. Use one writer per branch and a separate checkout/worktree for each agent. Names: codex/<issue>-<topic> or claude/<issue>-<topic>.
3. Never push directly to main, force-push, reset another session's work, or edit another writer's branch. Reviewers leave findings; authors apply changes.
4. Overlapping files require a handoff or sequential PRs. A rejected push means fetch and inspect, never force.
5. PRs target main unless the issue explicitly names a dependency branch. Only the named human integrator merges after review and relevant checks.
6. Issue claims are a coordination convention, not an atomic lock. Re-read claims before the first edit; simultaneous claims must be resolved before implementation.
7. Existing CI still pushes APKs to main until issue #6 is implemented. Documentation does not enforce branch protection or disable that job. Do not merge this setup without resolving that known workflow risk in the integration plan.

## Engineering
Preserve playback/session state through orientation and lifecycle changes. Do not weaken TLS, origin validation or credential handling to make playback pass. Keep secrets, pairing codes, cookies, private camera imagery and signing material out of commits and public logs. Use local fixtures for repeatable tests.
Keep visual, API and platform changes small and separately reviewable. Native migration requires an explicit baseline decision and feature matrix; do not create another competing app target by default.

## Verification and delivery
Use the target-specific commands in CONTRIBUTING.md and scenarios in docs/testing.md. Report exact commands, SHA, device/runtime and actual results. An empty test task is not passing coverage. A successful compile is not proof that real channels/cameras work. Distinguish unsigned iOS, debug Android and production-signed artifacts.
End with issue/PR links, changes, verified results, remaining blockers and a handoff. Never claim another AI reviewed or ran work unless its actual response is available.
