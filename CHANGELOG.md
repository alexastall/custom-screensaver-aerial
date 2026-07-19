# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.15] - 2026-07-19

### Changed
- Default source type is **4k Dolby Vision (HEVC)** (`url-4K-HDR`) for sets that support it.

## [1.0.14] - 2026-07-19

### Fixed
- **Black screen with advancing timecode** on webOS 4.x: video decoded but was hidden.
  - Transparent `WebOSWindow` (no opaque black fill).
  - Remove black fade overlay over the punch-through region.
  - Keep `Video` item at opacity 0 (output is on the hardware plane).
  - Use `_WEBOS_WINDOW_TYPE_CARD` so display/ACB attach correctly when
    `setWindowPunchThroughRectFunc` is missing.
- Document that an active HDMI input (e.g. Roku) can steal the video plane and
  produce the same black-screen-with-timecode symptom.

## [1.0.13] - 2026-07-19

### Fixed
- **Test run** now always applies the aerial QML bind-mount, then calls `turnOnScreenSaver`, and also launches `com.webos.app.screensaver` as a fallback (fixes Test doing nothing when Apply was not used first, and on some webOS builds).
- **webOS 4.x QML load race**: do not call `playRandomVideo()` before settings / playlist / locale JSON finish loading.
- **webOS 4.x `globalVars`**: notifications service uses hard-coded `com.webos.app.screensaver` appId (avoids `ReferenceError: globalVars is not defined`).
- Guard OSD/debug bindings when resources are not ready yet (avoids `TypeError` spam on startup).
- Safer playlist selection when all assets are marked viewed or preferred URL is missing.
- Optional XHR callback invocation (`typeof callback === "function"`).

### Changed
- Default source type is **FullHD (H264)** (`url-1080-H264`) for broader webOS 4 / low-RAM compatibility.
- Source picker lists H264 first; labels note webOS 4 recommendation.
- `playLowerQuality` falls back through 4K → 1080 HEVC → 1080 H264 when the preferred stream is missing.
- README documents experimental webOS 4 support and recommended settings.

### Tested
- LG **65UM7400PLB**, webOS TV **4.10.0** (K5LP, 1.5 GB RAM), rooted with Homebrew Channel.
