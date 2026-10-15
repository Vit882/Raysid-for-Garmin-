# Changelog

The build number is incremented with every build sent for testing (`build.sh`); the version (`APP_VERSION`) changes only with larger releases. Older entries were written retrospectively from development records; details on the latest builds are in the reports in `docs/`.

## 1.3

### Build 89 (2026-10-15)
- **Forerunner 70:** first build; layout checked in the simulator. The flashlight options are hidden (the watch has none).
- **Help:** the scroll arrows scale with the display and sit between the title and the text.

### Build 88 (2026-10-15)
- First public release on GitHub, for the fēnix 7X Pro.
- **Upload to Žhavá místa:** points are sent in larger portions so the website does not split a route into small pieces: everything waiting is sent once 500 points have gathered or a route ends, and the rest of a route still being recorded at least every 40 minutes. Each point keeps the time it was measured; when points are merged on a full watch, the merged point gets the time of the newer one.
- **Releases** are published automatically from `releases/v<version>/` by a GitHub workflow.
- **Display:** new option *Mapping screen times out* under *Backlight always on*. When on, the backlight on the Mapping screen times out as set on the watch, while the other screens stay lit.

## 1.2

### Build 87 (2026-10-15)
- Version 1.2, prepared for release with README screenshots; released as part of 1.3. Same features as build 86.

## 1.1

### Build 86 (2026-10-15)
- **Chart:** a line running into the scale labels no longer looks like a minus sign in front of the lowest value.

### Build 85 (2026-10-15)
- **Help:** the scroll-up arrow no longer overlaps the chapter title; the text starts a little lower.

### Build 84 (2026-10-15)
- Built against the official fēnix 7X Pro device definition from Garmin instead of a hand-written one. No functional changes.

### Build 83 (15 Oct 2026)
- **Target watch:** the build is now for the fēnix 7X Pro (id `fenix7xpro`), on which the app is tested. Previously it was compiled for the fēnix 7X. Features are unchanged; settings and unsent points are kept.
- Documentation and code comments translated to English; user guide now also in Polish.

### Build 82 (15 Oct 2026)
In-depth test of the whole UI, 40 bugs fixed. Details in [docs/ui-test-2026-10-15.md](docs/ui-test-2026-10-15.md). Main points:
- **Parser:** recovers immediately after a corrupted packet and reads data from the first notification after connecting.
- **Upload:** unsent points are not deleted on a website error such as 404; only batches rejected because of their content are discarded.
- **Alarms:**
  - The red flashlight blinks for the whole alarm, even with a 1:1 divider.
  - The alarm takes priority over clicks and warnings.
  - During OVL every enabled dose or cps alarm sounds.
  - Rapid rise computes the background based on time.
- **Mapping:** shows "waiting for Raysid" or "OVL" when points are not being saved. The "full" state survives an app restart.
- **Menu:**
  - Labels are refreshed after returning from a submenu.
  - Shorter texts fit on the round display.
  - The language is chosen according to the watch on first start.
- **Debug screen:** UP and DOWN do nothing.

### Build 81 (14 Oct 2026)
- **Storage:** new menu Žhavá místa > Storage: Not uploaded, When full (Stop recording, Merge at most 1×/2×/3×, Merge without limit) and Delete unsent.
- **Code review:** 26 bugs fixed, see [docs/code-review-2026-10-14.md](docs/code-review-2026-10-14.md). This includes automatic Bluetooth reconnection after 30 s, ping always at the front of the queue and gradual deletion of chunks.

### Build 79–80 (14 Oct 2026)
- Version 1.1.
- When storage is full, neighbouring points are merged and of each pair the point with the higher dose is kept.

## 1.0

### Build 76–78 (14 Oct 2026)
- **Alarm limits:** only below the Raysid overload (cps at most 5000, dose at most 999 µSv/h).
- **Divider:** fixed values as in the Raysid (1, 5, 10, 20, 50, 100, 250). At 1:1 only alarms remain on the watch.
- **Divider linking:** the watch and the Raysid can share one divider.
- **Full storage:** writing to storage is guarded, and when storage fills up recording stops without a crash.

### Build 59–75 (14 Oct 2026)
- **Overload (OVL):** separately for dose and cps. The Raysid reports it with a flag in packet 0x17; the app's own estimate serves as a fallback.
- **Debug log:** to `GARMIN/APPS/LOGS`.
- **New packets:** delimiter detection after a Raysid restart, Raysid button events (0x18) and reloading of settings.

### Up to build 58 (12–14 Oct 2026)
- **Basics:** connection to the Raysid, µSv/h and cps values, battery, chart, alarms (limits and rapid rise), clicks, vibration, flashlight, help in three languages and icon.
- **Raysid settings:** from the watch (sniffed commands): divider, clicks, alarms.
- **Averaging** of values by time or by number of measurements.
- **GPS mapping:** Mapping screen, pause, autostart, GPS quality and point spacing.
- **Žhavá místa:** upload to the website (endpoint `route-points`), API key entry and verification on the watch.
- **Connection:** Raysid history, "only chosen", preference when several units are present.
