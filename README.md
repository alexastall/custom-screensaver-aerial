<div align="center">
<img src="assets/icon130.png" alt="Aerial webOS logo" width="200">
<br><h1>Aerial webOS screensaver (fork of <a href="https://github.com/webosbrew/custom-screensaver">custom-screensaver</a>)</h1>
   
<a href="https://github.com/aabytt/custom-screensaver-aerial/releases/latest"><img src="https://img.shields.io/github/v/release/aabytt/custom-screensaver-aerial?style=flat-square" alt="Latest release"/></a>
<a href="https://github.com/aabytt/custom-screensaver-aerial/releases"><img src="https://img.shields.io/github/downloads/aabytt/custom-screensaver-aerial/total?style=flat-square" alt="Downloads"/></a>


</div>


* [190+ aerial videos](https://aabytt.github.io/aerial-preview/) from different sources.
* 40+ locales for OSD
* Source type selection (FullHD/4k SDR or Dolby Vision)
* Requires root and Homebrew channel
* Compatible with webOS 5 (2020), webOS 6 (2021), webOS 22 (2022), webOS 23 (2023)
* **Experimental webOS 4.x** support (see below)

Disclaimer
---------------
- App replaces original webOS screensaver. Use at your own risk. 

Features
--------

* Autostart registration
* Temporary apply
* Launch screensaver immediately for testing (applies QML first, then launches)

Installation
------------
This should be downloadable in Homebrew Channel. Otherwise, there's an `ipk` in
GitHub releases to the right. You are on your own here.

### webOS 4.x notes (experimental)

Tested on LG 65UM7400PLB (webOS 4.10, ~1.5 GB RAM). Upstream targets webOS 5+.

Recommended settings on webOS 4 (this set):

1. Source video type: **4k Dolby Vision (HEVC)** (default from 1.0.15) — fall back to FullHD H.264 if streams fail
2. Enable **Autostart** (or Temporary Apply after each reboot)
3. Use **Test run (apply + launch)** to verify; leave active HDMI inputs when testing

Why Test failed on older builds before 1.0.13:

* Test only called `turnOnScreenSaver` and did **not** apply the aerial QML first
* Some webOS builds need an explicit `applicationManager/launch` of `com.webos.app.screensaver`
* QML race: playback started before playlist JSON finished loading
* `globalVars` is missing in some screensaver qml-runner contexts

4K / Dolby Vision / high-bitrate HEVC streams may fail or stall on low-RAM webOS 4 sets. Prefer H.264 FullHD, and keep “fall back to lower quality” enabled.

**Black screen but debug timecode moves:** the stream is playing on the hardware
plane, but something is covering it or another input owns the plane.

* Leave **HDMI / Live TV** (unplug or switch away from devices like Roku) when testing.
* This fork uses a transparent window + CARD window type so the plane can show
  when webOS 4 does not implement QML punch-through.

Build
-----

```bash
npm install
npm run build
npm run package   # produces org.aabytt.webos.custom-screensaver-aerial_*_all.ipk
```

Install the IPK via Homebrew Channel (Dev Mode / root install).

Donate
------------
Looking for more sources or cool new features? Your support would mean the world!
* [YooMoney](https://yoomoney.ru/to/4100115685800097)

Screenshots
------------
   ![Main](https://github.com/aabytt/custom-screensaver-aerial/assets/84480313/77daf2da-b528-41ba-8377-fff70e6e1fd3)
   ![Screenshot](https://github.com/aabytt/custom-screensaver-aerial/assets/84480313/166f43e7-a3cf-4035-975a-931f282f5655)
   ![Settings](https://github.com/aabytt/custom-screensaver-aerial/assets/84480313/1b7f281b-efdc-4eed-b0f2-b06f4bd5929a)
