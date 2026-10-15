# Sniffing Raysid settings (procedure for a btsnoop log)

Goal: find out how the Raysid reports its settings after connecting (divider, click sound, and whether the dose and cps alarms are enabled in the Raysid), so that the watch can read them.

## How it works

After connecting, the official app requests the settings bundle from the Raysid and the device sends it once. It arrives again on every new connection. If you change **only one thing** between connections each time, I compare the bundles and see which byte changed.

**One log is enough.** The snoop log continuously records everything since Bluetooth was turned on, so even twenty disconnections and connections fit into it. But **do not turn off** Bluetooth on the phone during the measurement. Each off and on starts a new file, the old one is renamed to `btsnoop_hci.log.last`, and an even older one is lost.

## Preparation

1. Leave the snoop log set to **Enabled**.
2. On the watch, **close the Raysid app** so that it does not connect to the dosimeter instead of the phone.
3. On the phone, turn Bluetooth off and on once (this starts a clean log). After that, do not turn Bluetooth off.
4. Have paper or a note ready. For each step, write down the **time from the phone** and what you did, e.g. `14:12 – step 3 – divider 1:10`. Hour and minute are enough, seconds are not needed. Keeping the order from the table matters more; I recognize the steps in the log by the sequence of commands, and the time only helps me if something was repeated or skipped.

## One step = one change and a new connection

For each row of the table below:

1. In the official app, **change one item**, wait 5 s.
2. **Disconnect** (with the button in the app; if you cannot find it, turn off the Raysid with its button). Wait 10 s.
3. **Connect again** (or turn the Raysid on). Wait 15 s for values to start arriving.
4. Write down the time and what you changed.

First, make one connection without any change as the baseline and write down how everything is set (a screenshot of the SETS screen is enough).

## Measurement order

| # | Change | Why |
|---|---|---|
| 0 | nothing, just connect (baseline + SETS screenshot) | basis for comparison |
| 1 | divider 1:1 | |
| 2 | divider 1:5 | |
| 3 | divider 1:10 | |
| 4 | divider 1:20 | |
| 5 | divider 1:50 | |
| 6 | divider 1:100 | |
| 7 | divider 1:250 | seven values = certainty about which byte it is |
| 8 | Sound Clicks off | |
| 9 | Sound Clicks on | |
| 10 | Dose rate alarm off | |
| 11 | Dose rate alarm on | |
| 12 | CPS alarm off | |
| 13 | CPS alarm on | |

Do not change "Enable Clicks" or other SETS items: Enable Clicks is clicking in the phone, not in the Raysid.

## Sending

1. Run `adb bugreport raysid2.zip` as last time.
2. Extract the log: `unzip -j raysid2.zip 'FS/data/misc/bluetooth/logs/btsnoop_hci.log*'`
3. Send me `btsnoop_hci.log` (and `.last`, if it was created) and your notes with times.
4. You can then turn the snoop log off.

## Notes

- The log also contains traffic of other Bluetooth devices (for example notifications to another watch). I read only the communication with the Raysid. If that bothers you, disconnect the other devices for the duration of the measurement.
- If something goes wrong during the measurement (the connection drops, the order gets mixed up), no problem. Just note it with the time and continue with the next step.
