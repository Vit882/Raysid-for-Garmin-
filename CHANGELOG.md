# Changelog

The build number is incremented with every build sent for testing (`build.sh`); the version (`APP_VERSION`) changes only with larger releases. Older entries were written retrospectively from development records; details on the latest builds are in the reports in `docs/`.

## 1.1

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
