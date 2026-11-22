# Mobile acceptance and evidence

This document defines required evidence; it does not claim these tests have run. Reuse recovery branch tests after baseline review.

| Area | Cases | Evidence |
| --- | --- | --- |
| Fullscreen | Portrait, left/right landscape, 5 rotations, Back, system bars, cutout, gesture/three-button navigation, rotation lock | Exact APK + package/version, OS/WebView, before/after screenshots, automated regression |
| Lifecycle | Background/resume, interruption, channel switch, process recreation where supported | No duplicate audio, selection/session preserved, explicit recovery behavior |
| TV functions | Categories, EPG, search, favorites, history, empty/loading/error | Android/iOS parity matrix and fixture tests |
| Pairing/API | Invalid/expired code, 401/403, timeout, malformed payload, restart, outage/reconnect | Deterministic contract/session test reports |
| Dahua cameras | Enabled/disabled/offline camera, broken thumbnail, live playback, expired URL, authenticated segments | Fixture decoder/playback test; separate approved real-camera smoke |
| Design | TV 7.1 references, portrait/landscape controls, text size, accessibility, safe areas | Annotated Android/iOS comparisons with reference provenance |
| Android artifact | Correct target, build, lint, real tests, signature, package/version, SHA-256, installation | Successful run URL + artifact name + commit; emulator/device launch |
| iOS artifact | Selected target build/tests, orientation, lifecycle, parity | macOS/Xcode version, simulator/device evidence; signing status explicit |

Use local media and mock gateway responses in CI. Never embed production cookies, pairing codes, camera credentials or private imagery in fixtures/logs. Live checks are opt-in with authorized test access. Distinguish reachable endpoint, downloaded playlist and actual decoded playback.

Do not count NO-SOURCE, skipped tests, compile-only runs or unsigned IPA packaging as completed functional tests. Report unavailable devices or missing credentials as untested/blocked.

## Evidence record
- Issue, branch and commit:
- App target / application ID / version:
- Commands and pass/fail/NO-SOURCE:
- Runner or device / OS / WebView or Xcode:
- Fixture coverage:
- Real gateway/camera checks actually run:
- Artifact / signature type / SHA-256:
- Screenshots or test reports (sanitized):
- Remaining failures and next owner:
