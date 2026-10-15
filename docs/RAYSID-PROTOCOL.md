# Raysid protocol over Bluetooth LE

This document describes the communication between the watch and the Raysid dosimeter as implemented by the Raysid Garmin app, and adds what we found out ourselves by sniffing. It is meant for a developer or AI agent who picks up the project without any further context.

Code that implements the protocol:

| File | Contents |
|---|---|
| `source/RaysidProtocol.mc`, module `RaysidProtocol` | UUIDs, recognizing a Raysid in scan results, command frame, CRC, ping, settings commands, packet checksum, `unpackValue` |
| `source/RaysidProtocol.mc`, class `RaysidParser` | assembling packets from notifications, finding the delimiter, decoding (`feed`, `decode`) |
| `source/BleManager.mc`, class `BleManager` | scanning, pairing, enabling notifications, write queue, ping, reading settings, passing decoded values to `RaysidState` |

Notation: bytes are written in hex (`0x12` or just `12`). `p[i]` is the i-th byte of a received packet including the length byte, so `p[0]` is the length and `p[1]` the type.

## 1. Sources

**Official documentation:** https://raysid.com/api. It contains `API.md` (protocol description), `connect.py` (connecting) and `cps-doserate.py` (reading cps and dose rate). The code refers to it in the header of `RaysidProtocol.mc`. There is **no** copy of these files in the repository. Anyone who wants to check something against the original has to open the page themselves.

**Sniffing the official app:** the commands for Raysid settings (divider, clicks, alarms) and the layout of the settings packet `0x0a` are not in `API.md`. We found them on 14 Oct 2026 from a btsnoop log of the official Android app (the procedure is in chapter 10).

**Debug log from the watch:** packet types `0x18`, `0x22`, `0x21` and others, the delimiter between packets and the real data rate come from the logs the app writes when the debug screen is enabled (see `docs/BUILDING.md`, the chapter on logs).

Where `API.md` and the real device differ, the code follows the real device. Each such place is pointed out below.

## 2. GATT: service and characteristics

| Role | UUID | Function in code |
|---|---|---|
| Service | `49535343-fe7d-4ae5-8fa9-9fafd205e455` | `RaysidProtocol.serviceUuid()` |
| RX (Raysid → watch), notify | `49535343-1e4d-4bd9-ba61-23c647249616` | `RaysidProtocol.notifyCharUuid()` |
| TX (watch → Raysid), write | `49535343-8841-43f4-a8d4-ecbe34729bb3` | `RaysidProtocol.writeCharUuid()` |

These are the UUIDs of the Microchip (ISSC) transparent UART service; Raysid apparently uses it as a serial line.

Connect IQ requires the profile to be registered in advance. `RaysidProtocol.profile()` registers the service with both characteristics, and the RX one also with its CCCD descriptor. The registration is called by `BleManager.register()`. If it fails, `BleManager.restart()` tries again.

### Recognizing a Raysid in scan results

`RaysidProtocol.matches(r)` returns `true` when:

1. the device name contains `raysid`, case-insensitive (constant `NAME_PREFIX`; it is searched anywhere in the name, not only at the start), **or**
2. the advertisement contains the service UUID above.

Further selection among several Raysids is done by `BleManager.onScanResults()` and `BleManager.choose()`: found units are collected for `CHOOSE_MS` = 3 s, then one is chosen by preference (`pref` 0 = the selected one or the most recently used one from history, 1 = strongest RSSI). The selected unit (`pin`) is connected immediately; with the lock (`lock`) the others are ignored. A device without a name gets the name `Raysid`.

### After connecting

`BleManager.onConnectedStateChanged()` → `BleManager.subscribe()`:

1. write `01 00` to the CCCD of the RX characteristic (enables notifications),
2. the sequence `RaysidProtocol.initCommands()`, which is the same as `settingsCommands()` (chapter 5).

Connect IQ allows only one BLE request in progress, so all writes go through a queue (`BleManager.enqueue()`, `pump()`, confirmation in `onDescriptorWrite()` and `onCharacteristicWrite()`). If the confirmation does not arrive within 3 s, `onTick()` unblocks the queue.

Writes use `WRITE_TYPE_WITH_RESPONSE` (`RaysidProtocol.WRITE_TYPE`). The official Python script sends the ping without response; with response it works on a real Raysid.

After an app update, the Raysid may stay connected to the watch from the previous instance and then it does not advertise. So after registering the profile, `BleManager.adoptPaired()` first goes through `getPairedDevices()`, takes over an active connection and removes inactive ones (`unpairDevice`).

## 3. Command frame (watch → Raysid)

`RaysidProtocol.command(payload)` wraps every command like this:

```
[0xFF] [CRC2] [0xEE] [CRC1: 4 B, big-endian] [payload ...] [TotalSize]
```

| Field | Length | Meaning |
|---|---|---|
| `0xFF` | 1 | start of frame |
| `CRC2` | 1 | XOR of all bytes from `0xEE` to the end of the payload (that is `0xEE`, the 4 bytes of CRC1 and the payload) |
| `0xEE` | 1 | fixed marker |
| `CRC1` | 4 | sum of the payload in 4-byte blocks, written big-endian |
| payload | N | the first byte is the command code, followed by parameters |
| `TotalSize` | 1 | length of the whole frame including this byte, i.e. N + 8 |

**CRC1** (`RaysidProtocol.crc1`): the payload is split into 4-byte blocks, each read as a **little-endian** 32-bit number (an incomplete last block is padded with zeros at the top), and the blocks are summed modulo 2³². The result is written into the frame **big-endian** (most significant byte first).

**CRC2**: a plain XOR of the bytes `0xEE`, CRC1 (4 B) and the payload.

Examples computed according to the code:

| Command | Payload | Frame |
|---|---|---|
| divider 1:10 | `16 0A` | `FF EE EE 00 00 0A 16 16 0A 0A` |
| `1b 01` (request settings) | `1B 01` | `FF EE EE 00 00 01 1B 1B 01 0A` |

For a two-byte payload, CRC1 = `payload[1] << 8 | payload[0]`, which is why the same two bytes appear in the frame in reverse order.

## 4. Ping

```
payload = [0x12] [tab] [unix time: 4 B big-endian]
```

Function `RaysidProtocol.ping(tab)`. `tab` tells the Raysid which screen the app has open: `0` = main screen with telemetry (`ACTIVE_TAB`), `9` = settings screen (`SETTINGS_TAB`). The time is `Time.now().value()`, i.e. seconds since 1 Jan 1970 UTC.

**The Raysid disconnects when it gets no ping for 10 s.** The app therefore sends one every 4 s (`POLL_MS` = 4000, timer in `BleManager.start()`, sending in `BleManager.onTick()`). The ping is put at the **front** of the queue so that it is not delayed behind other commands. Exception: when a settings read is in progress in the queue (items marked `:seq`), the ping is skipped, because the read sequence itself ends with a ping with `tab` 0 and an inserted ping would split it (the Raysid would then not reply).

The whole ping frame is 14 bytes.

## 5. Reading Raysid settings

The sequence is taken from sniffing the official app, function `RaysidProtocol.settingsCommands()`:

| # | Payload | Meaning |
|---|---|---|
| 1 | `12 09 <time>` | ping with `tab` 9 (the app "opened" settings) |
| 2 | `1F 00` | meaning unknown, the official app sends it |
| 3 | `1B 01` | the Raysid replies with a `0x0a` packet with the settings |
| 4 | `1B 02` | meaning unknown, the official app sends it |
| 5 | `12 00 <time>` | ping with `tab` 0, back to the main screen |

When the sequence is sent (`BleManager`):

- right after connecting (`subscribe()` → `initCommands()`),
- after every settings command (`send()` calls `requestSettings()`), so that the watch knows what the Raysid actually accepted,
- after a `0x18` packet (someone pressed a button on the Raysid and may have changed the settings).

The counter `_setReq` makes sure that only the reply to the **last** read is written into the menu. Otherwise a reply to an older read would briefly revert a toggle that was just switched. Pending reads older than 3 s are considered lost.

### Packet `0x0a` (settings)

Decoded by `RaysidParser.decode()`, only when the packet has at least 14 bytes:

| Byte | Meaning | Key in the result |
|---|---|---|
| `p[4]` | sound divider 1:N, the value N directly | `:devDiv` |
| `p[6]` | sound (clicks) in the Raysid, 0 = off | `:devSound` |
| `p[10]` bit `0x10` | dose rate alarm enabled | `:devDoseAl` |
| `p[10]` bit `0x01` | cps alarm enabled | `:devCpsAl` |

We do not know the other bytes (alarm thresholds, brightness, mode and the like are probably there, but nobody has verified them).

## 6. Settings commands (sniffed 14 Oct 2026)

None of these commands is in `API.md`. We found them from a btsnoop log of the official Android app.

| Payload | Function in `RaysidProtocol` | Meaning |
|---|---|---|
| `16 N` | `dividerCommand(n)` | sound divider 1:N. The official app offers 1, 5, 10, 20, 50, 100, 250. The value 1 did not appear in the log, the others did. |
| `03 01` / `03 00` | `soundCommand(on)` | sound signalling (clicks) in the Raysid on / off |
| `18 01` / `18 00` | `doseAlarmCommand(on)` | dose rate alarm on / off |
| `17 01` / `17 00` | `cpsAlarmCommand(on)` | cps alarm on / off |

Note: the command codes `0x17` and `0x18` coincide with the **incoming** packet types `0x17` and `0x18`, but have nothing to do with them. The watch → Raysid and Raysid → watch directions are separate.

Commands are sent by `BleManager.send()`; it returns `false` when the Raysid is not connected. Divider merging (`BleManager.syncDivider()`): when `state.divLink` is enabled and the divider in the Raysid differs from the watch divider, the watch divider is sent to the Raysid (only values up to 255, one attempt per difference, so that it does not loop if rejected).

## 7. Incoming packets (Raysid → watch)

### Packet format

```
[Size] [Type] [Payload ...] [Checksum: 3 B]
```

- `Size` is the length of the whole packet including the `Size` byte and the checksum. The minimum the parser accepts is 4.
- One packet may arrive split across several notifications and one notification may contain several packets. The parser therefore assembles the data in a buffer (chapter 8).

### Checksum

`RaysidProtocol.checksumOk()`: XOR of 3-byte blocks of all bytes before the checksum (from `Size` to the end of the payload; an incomplete last block is padded with zeros). `API.md` and `cps-doserate.py` differ in byte order, so the code accepts **both** variants. Byte by byte this means:

- variant `le` in the code: checksum byte k (k = 0, 1, 2) = XOR of the bytes at positions ≡ k (mod 3),
- variant `be` in the code: checksum byte k = XOR of the bytes at positions ≡ 2 − k (mod 3).

The real Raysid (log from 14 Oct 2026) sends the `be` variant. A checksum of value 0 is rejected so that zeros are not "valid packets".

Example of a real `0x17` packet (12 bytes): `0C 17 00 77 20 01 6E 1A 00 01 2D 15`. Checksum `01 2D 15`: `01` = `00^01^00` (positions 2, 5, 8), `2D` = `17^20^1A` (positions 1, 4, 7), `15` = `0C^77^6E` (positions 0, 3, 6).

### Overview of types

The list of known types is in the constant `KNOWN_TYPES` in `RaysidProtocol.mc`. The parser uses it when looking for the delimiter (chapter 8).

| Type | Contents | What the app does with it |
|---|---|---|
| `0x17` | cps and dose rate, overload flag | decodes `:cps`, `:doseRate`, `:ovl` |
| `0x02` | Raysid temperature and battery | decodes `:temp`, `:battery` (only the battery is stored in the state) |
| `0x0a` | Raysid settings | decodes `:devDiv`, `:devSound`, `:devDoseAl`, `:devCpsAl` |
| `0x18` | button event on the Raysid | sets `:btn`, `BleManager` then reloads the settings |
| `0x22` | alarm or LED event | debug log only |
| `0x21` | spectrum, about 182 bytes | nothing (skipped in the log) |
| `0x03`, `0x06`, `0x23` | unknown | nothing, only the type counter on the debug screen and the debug log (`0x23` always, `0x03` on change, `0x06` never) |

### `0x17`: cps and dose rate

The type is followed by 3-byte blocks `[RangeType] [LSB] [MSB]`, then one flag byte and then the checksum:

```
[Size] [0x17] {[RangeType] [LSB] [MSB]} ... [OVL] [Checksum: 3 B]
```

- `RangeType` 0 = cps, 1 = dose rate.
- The 16-bit value `LSB | MSB << 8` is compressed. `RaysidProtocol.unpackValue(v)`: the result is `v % 6000` multiplied by ten as many times as `v / 6000` (integer division). Then it is divided by 600.
- The dose rate comes out in **µR/h**. The app divides it by `UR_PER_USV` = 100 and works in µSv/h (1 µSv/h ≈ 100 µR/h). Verified against the Raysid display on 13 Oct 2026.
- The byte right before the checksum is the **overload flag** (`01` when the Raysid blinks its red LED; sniffed 14 Oct 2026). The code reads it only when the length matches "blocks + 1 byte", i.e. `(Size − 5) % 3 == 1`, and returns it as `:ovl`. `BleManager` stores it in `state.devOvl` and `RaysidState.updateOvl()` (`RaysidApp.mc`) then uses it directly as the cps overload. The app's own overload estimate from the course of cps and dose runs only when the flag did not arrive (older firmware or a different Raysid).

Calculation for the example above: block `00 77 20` → v = 0x2077 = 8311 → 8311 / 6000 = 1, 2311 × 10 = 23,110 → / 600 = **38.5 cps**. Block `01 6E 1A` → v = 6766 → 766 × 10 / 600 = 12.8 µR/h → **0.128 µSv/h**. Flag `00`.

A longer `0x17` packet (42 bytes) with `RangeType` blocks 0 to 9 also appeared in the log. The code ignores blocks with type 2 and higher and we do not know their meaning (see open questions).

If several `0x17` packets arrive in one notification, `feed()` returns only the values of the last one (the keys are overwritten). At a rate of about 240 ms this is knowingly acceptable.

### `0x02`: temperature and battery

| Bytes | Calculation | Key |
|---|---|---|
| `p[2]`, `p[3]` (LE) | value / 10 − 100 = temperature in °C | `:temp` |
| `p[4]`, `p[5]` (LE) | battery in % | `:battery` |

Only a packet with length at least 9 is decoded. `API.md` says the battery is divided by ten, but the real Raysid sends the percentage directly (verified on the device). A typical `0x02` packet has 27 bytes; we do not know the meaning of the rest.

### `0x18`: button on the Raysid

Payload `[function] [new state]`. Function `02` = clicks, `03` = alarms (sniffed 14 Oct 2026). The code does not read the content, it only sets `:btn` and `BleManager.onCharacteristicChanged()` calls `requestSettings()` so that the change shows up in the Raysid menu.

### `0x22`: alarm or LED event

From the log we read this sequence of payloads:

| Payload | When |
|---|---|
| `01 05` | start of alarm |
| `04 00` | repeatedly about every 2 s while the alarm lasts |
| `02 xx` | end of alarm (`xx` unknown) |
| `03 00` | about 15 s after the end |

The app does not decode the packet. It evaluates alarms itself from the `0x17` values (class `Alarms`), and overload from the flag in `0x17`. The packet is only always written to the debug log.

### `0x21`: spectrum

About 182 bytes (`Size` = `0xB6`), arrives in several notifications. The app does not use it and does not write it to the log. We do not know the format. For the parser it matters only because it is long and split, so it is where assembly errors show up most often.

## 8. Delimiter between packets and resynchronization

The real Raysid sends one extra byte between packets that `API.md` does not describe. We have seen the value `0x84` and, after restarting the Raysid (without disconnecting the watch), `0x10`. So the parser does not have it hard-coded but **learns it**.

How `RaysidParser.feed(value)` works:

1. The notification is appended to `_buf`. When the buffer grows past 1024 B, the last 512 B are kept and the parser is marked as out of sync.
2. At the current position:
   - If there is the known delimiter and we are right after a packet (or out of sync), it is skipped and parsing continues as at the start of a packet.
   - If the delimiter is known and the parser is out of sync, it skips without computing checksums up to the next delimiter.
   - If there is a length byte at the position and the checksum matches, the packet is decoded.
   - Otherwise it checks whether the current byte is a delimiter: a packet of a known type (`KNOWN_TYPES`) with a valid checksum must start right after it. Then the byte is counted as a candidate (`learnDelimiter`). A value that shows up like this **three times** becomes the delimiter `_delim`.
   - If the rest of the packet is missing and we are in sync, it waits for the next notification.
   - Otherwise the byte is junk and is skipped.
3. Watchdog protection: within one notification, the checksum is tried on at most `JUNK_MAX` = 120 bytes of junk, then the rest of the buffer is discarded.
4. When `RELEARN_AFTER` = 10 consecutive notifications bring no valid packet, the delimiter is forgotten and learned again (a Raysid restart changes `0x84` to `0x10`).
5. `RaysidParser.reset()` (called on every new connection) forgets the buffer and the delimiter.

The parser was tested by simulation (delimiter `0x84` and `0x10`, split packets, junk, 5000 notifications with random errors), see `docs/ui-test-2026-10-15.md`.

## 9. Timing

| What | Value | Where in code |
|---|---|---|
| ping | every 4 s | `RaysidProtocol.POLL_MS`, `BleManager.onTick()` |
| disconnect without ping | 10 s (Raysid behaviour) | |
| `0x17` data on the real device | about every **240 ms** | measured, the debug screen shows the average interval |
| pairing timeout | 15 s | `BleManager.CONNECT_TIMEOUT_MS` |
| reconnect without connection or without data | 30 s | `BleManager.RECOVER_MS` |
| values turn grey | 5 s without a new measurement | `RaysidView` |
| collecting candidates while scanning | 3 s | `BleManager.CHOOSE_MS` |

Older documentation and comments state that the Raysid sends data about every 2 s. On the real device it is about 240 ms. That is why alarms and averaging are computed by time, not by number of measurements (`Alarms.mc`). The comments in `Clicker.mc` ("cps every ~2 s") and in `Alarms.mc` at the `sigma` calculation ("cps measured over ~2 s") date from before this finding.

## 10. How to sniff the official app (btsnoop)

This is how the commands in chapter 6 and the layout of the `0x0a` packet were found. The procedure is useful when more settings need to be decoded.

**Principle:** after connecting, the official app requests the settings bundle (`0x0a`) and the Raysid sends it. It arrives again on every new connection. When **only one thing** is changed between connections, comparing the bundles shows which byte changed. The command the app used to send the change is right before it in the log.

**Preparation (Android):**

1. In developer options, turn on **Bluetooth HCI snoop log** (Enabled).
2. On the watch, close the Raysid app so that it does not connect to the dosimeter instead of the phone (the Raysid has a BLE connection with only one device).
3. Turn Bluetooth on the phone off and on once (this starts a clean log). After that, **do not turn Bluetooth off**: each time it is turned off a new file starts, the old one is renamed to `btsnoop_hci.log.last` and an even older one is lost. One log easily holds twenty connections.
4. For each step, note the time from the phone (hour and minute) and what changed.

**One step = one change and a new connection:**

1. In the official app, change one item, wait 5 s.
2. Disconnect (with the button in the app, or turn off the Raysid), wait 10 s.
3. Connect again, wait 15 s for values to start arriving.
4. Note the time and the change.

First, one connection without any change as the baseline (with a screenshot of the SETS screen).

**Order used on 14 Oct 2026:**

| # | Change |
|---|---|
| 0 | nothing, baseline |
| 1–7 | divider 1:1, 1:5, 1:10, 1:20, 1:50, 1:100, 1:250 (seven values unambiguously identify the byte) |
| 8, 9 | Sound Clicks off, on |
| 10, 11 | Dose rate alarm off, on |
| 12, 13 | CPS alarm off, on |

"Enable Clicks" in the official app is clicking in the phone, not in the Raysid, so it was not changed.

**Getting the log:**

```
adb bugreport raysid.zip
unzip -j raysid.zip 'FS/data/misc/bluetooth/logs/btsnoop_hci.log*'
```

The log also contains traffic of the other Bluetooth devices on the phone. Raw logs do not belong in the repository (they may contain personal data and device addresses); there are none in the repository. The log can be opened in Wireshark (filter `btatt`), where you look for writes to the TX characteristic and notifications from RX.

## 11. Open questions

1. **Meaning of `1F 00` and `1B 02`** in the settings read sequence. We send them because the official app sends them.
2. **The rest of the `0x0a` packet**: where the alarm thresholds and other settings are.
3. **`RangeType` blocks 2 to 9** in the longer `0x17` packet (perhaps cps over different time windows or other ranges).
4. **Types `0x03`, `0x06`, `0x23`**: content unknown. `0x06` arrives periodically, `0x23` is always logged because it is most likely an event.
5. **The second byte of `0x22 02 xx`** and what exactly `0x22 03 00` means.
6. **Format of the `0x21` spectrum.**
7. **Origin of the delimiter `0x84` / `0x10`** and why it changes after a Raysid restart. The parser learns it, so functionality does not depend on the answer.
8. **Checksum:** the real device sends the `be` variant. We do not know whether other firmware sends `le`, so both remain.
9. **Overload without the flag:** when the Raysid does not send the OVL flag in `0x17`, the app estimates overload itself from the course of the values (constants `OVL_*` in `RaysidDelegate.mc`, estimated; `OVL_CPS_ON` is disabled for testing). Dose overload (above `OVL_DOSE` = 999 µSv/h) is always computed from the value. We do not know whether the Raysid also sends the flag for dose overload.
10. **Divider 1:1** with the command `16 01` was not seen in the sniffing.
