# Aston TV mobile: inspection and shared backlog

Inspection date: 2026-11-22. This is a repository snapshot, not a claim of on-device validation.

## Baseline
main at 92ad2271b61c7931d7bb8efacd4cb5d77bda993d contains four app targets:

| Target | Implementation observed | Build workflow |
| --- | --- | --- |
| app/ | Java Android WebView wrapper; 4.1.1 | build-apk.yml |
| mobile71/ | Kotlin Android WebView at /tv6/; 7.1.0; min SDK 26 | build-mobile71.yml |
| ios/ | SwiftUI controls with WKWebView | build-ios.yml |
| ios-mobile5/ | SwiftUI/AVPlayer and gateway API client | build-mobile5-ios.yml |

The uploaded 8.0.0 APK is not mapped to a source commit. Do not assume any listed target built that binary. “Android 8.1” in the prior chat is not a verified app version or minimum OS decision.

Existing codex/iphone-recovery at 0307216534b00d79dcc4f5097bd92223a269d43c was 23 commits ahead and 11 behind main. It adds gateway code/session tests, Android GatewayClient and PlaybackTest, iOS playback/contract/UI tests and a mobile Android workflow. Preserve and inspect this work before choosing the canonical native targets.

main/mobile71 already handles fullSensor, immersive flags, custom video views and fit()/resize after rotation. The user's fullscreen complaint remains unverified on physical hardware.

The original TV6 HTML/CSS/JS and LG visual references are not in main. Prior chat references tv6-for-server(1).zip and an 8.0.0 APK; availability in one chat does not make these shared repository inputs. Inventory/sanitize relevant assets before importing them; do not commit private settings or camera images.

## Build findings
- Root Android run [45021150151](https://github.com/astonbg/aston-tv-android/actions/runs/45021150151) succeeded for 252e3b435a2896b6432b8e5424178145e94eed19. This does not validate Mobile 7.1 or device behavior.
- Mobile 7.1 run [45021150097](https://github.com/astonbg/aston-tv-android/actions/runs/45021150097) failed in SDK setup: package 'tools' not found. Compile/upload were skipped.
- build-apk.yml currently commits generated APKs to main with contents:write. Issue #6 must remove this source of concurrent pushes.
- No Android/iOS builds or live device/camera tests were run by this documentation setup.

## Work order and suggested owners
| Issue | Work | Proposed writer | Dependency |
| --- | --- | --- | --- |
| [#1](https://github.com/astonbg/aston-tv-android/issues/1) | Reconcile existing work and choose baseline | ChatGPT/Codex | First platform task |
| [#6](https://github.com/astonbg/aston-tv-android/issues/6) | Reliable APK/PR checks; stop CI source pushes | ChatGPT/Codex | Coordinate baseline and workflow ownership |
| [#3](https://github.com/astonbg/aston-tv-android/issues/3) | TV 7.1 design and touch UX specification | Claude Code | Reference inventory can start immediately |
| [#2](https://github.com/astonbg/aston-tv-android/issues/2) | Fullscreen landscape regression | ChatGPT/Codex | #1; coordinate UX with #3 |
| [#4](https://github.com/astonbg/aston-tv-android/issues/4) | Native Android/iOS parity plan and evidence | Separately claimed platform slices | #1 and #3 |
| [#5](https://github.com/astonbg/aston-tv-android/issues/5) | Gateway/API and Dahua tests | ChatGPT/Codex | Inventory now; executable tests after #1 |

All issues start UNCLAIMED. A suggested role is not an active Claude session. Issue claims and PR handoffs carry ownership; this static table is not a lock.

## Completion gates
Every feature needs a scoped PR, meaningful tests, independent review and evidence tied to its commit. First prove the correct APK builds and installs, then verify fullscreen and playback on a phone. Track iOS parity independently, including Apple signing. Obtain authentic design references before claiming exact TV 7.1 fidelity. See testing.md for the acceptance matrix.
