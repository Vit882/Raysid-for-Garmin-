First public release of Raysid for Garmin, a Connect IQ watch app for the Raysid BLE dosimeter.

## Download

| Watch | File |
|---|---|
| Garmin fēnix 7X Pro (Solar / Sapphire Solar), Connect IQ id `fenix7xpro` | `Raysid-1.3-b89-fenix7xpro.prg` |
| Garmin Forerunner 70, Connect IQ id `fr70` (checked in the simulator only) | `Raysid-1.3-b89-fr70.prg` |

Download the file for your watch model only. Install by copying the `.prg` into `GARMIN/APPS` on the watch over USB, see the [user guide](docs/USER-GUIDE.md) ([Česky](docs/USER-GUIDE-CS.md), [Polski](docs/USER-GUIDE-PL.md)).

## What it does

- Live dose rate (µSv/h) and count rate (cps) from the Raysid over Bluetooth
- Alarms for dose rate, cps and a sudden rise, with sound, vibration and flashlight
- Clicks with an adjustable divider, Raysid settings from the watch
- Chart of the last 10 to 60 s with averaging
- GPS radiation mapping with upload to [Žhavá místa](https://zhavamista.cz) through the phone
- Backlight always on, optionally timing out on the Mapping screen
- Uploads in portions of 500 points so routes stay whole on the website
- Czech, English and Polish UI

Full history in [CHANGELOG.md](CHANGELOG.md).
