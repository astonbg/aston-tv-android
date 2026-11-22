# Aston TV Premium Android 4.0.2

Android wrapper for the existing Aston TV Premium gateway.

- Local: http://10.10.10.179:8424/
- Remote: https://tv.astonserver.eu/ (may serve an older gateway version)
- Android phone, tablet and Android TV (WebView)
- Local pairing, Plex, EPG, channels and cameras are provided by the backend.
- No passwords or API keys are included.

## Build
GitHub Actions workflow **Build Android APK** builds app-debug.apk, signed with Android's debug key. Download from workflow run artifacts.

**Not a production-signed release.** Playback and camera support depends on the actual gateway, Android WebView and device capabilities.

## Shared mobile development
Start with [CONTRIBUTING.md](CONTRIBUTING.md), [AGENTS.md](AGENTS.md) and [CLAUDE.md](CLAUDE.md). The [mobile roadmap](docs/mobile-roadmap.md) distinguishes the app targets and existing recovery branch. Use [testing criteria](docs/testing.md) and [agent handoffs](docs/agent-handoff.md) for evidence and ownership.

The heading above describes the historical root wrapper; it is not the version of every Android/iOS target. See the roadmap before building or naming a release.
