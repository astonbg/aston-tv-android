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
