# App review – build 81 (version 1.1), 14 Oct 2026

I went through the whole source code in four parts: BLE and protocol, mapping and upload, menu and settings, screens, alarms and signalling. Everything compiles with the strictest type checking (`monkeyc -l 3`). I verified point merging with a simulation on 100,000 points.

It has not been tried on the watch yet, and I could not run it in the Garmin simulator either. The simulator needs the official fenix 7X device definition (Garmin login) and libraries that are missing in the cloud.

## New: Žhavá místa → Storage
- **Not uploaded:** how many points are waiting to be uploaded and what % of the capacity (about 4000 points) they take up.
- **When full:** Stop recording, Merge at most 1×, 2×, 3×, or Merge without limit. The default is 2×.
  - When merging, of each pair of neighbouring points the one with the higher dose is kept, so the spacing doubles.
  - 1× means points at most 2× farther apart (so 10 m at 5 m), 2× up to 4× farther (20 m), 3× up to 8× farther (40 m).
  - Capacity without uploading, according to the simulation: Stop about 4,000 points, 1× about 8,000, 2× about 15,000, 3× about 27,000; without limit it keeps recording.
- **Delete unsent:** this item used to be missing from the menu, now it is here.

## Fixed bugs
**Mapping and upload**
1. The merge limit was not respected: with limited merging the number of points could grow indefinitely until the storage overflowed. The simulation revealed this.
2. After filling up and a new start, the rest of the old route could go out as the start of a new one, and the old route was never closed on the web.
3. Deleting during recording could collide on the web with batches already sent. Recording is now ended first.
4. Deleting during upload: the web response could delete a new, not yet sent chunk. The response now deletes only the chunk that was actually sent.
5. A batch that the web permanently rejected (a 4xx error other than 401/403/408/429) was retried by the app indefinitely and blocked the whole queue. Such a batch is now skipped.
6. If sending the request itself failed, uploading got stuck until the app was restarted.
7. With full storage at the 5000-point route boundary, the route part number was increased needlessly.
8. Deleting hundreds of chunks at once could trip the computation time guard (watchdog). Deletion now happens gradually in the background.
9. Loading damaged chunks used recursion and could overflow the stack.

**Bluetooth (Raysid)**

10. If the connection did not recover by itself, the app stayed "Disconnected" forever. It now reconnects after 30 s without a connection or without data.
11. A delayed disconnection of the old device could, after reconnecting, cancel the enabling of data, so data did not arrive.
12. Delayed scan results could start a second pairing.
13. The ping (without it the Raysid disconnects after 10 s) was skipped when the command queue was full. It now always goes to the front of the queue.
14. With junk in the data, the parser could retry every byte again and a watchdog was a risk. Junk is now discarded.
15. After disconnecting, the alarm and OVL stayed lit and the screen was redrawn needlessly. The baseline for rapid rise is now forgotten after disconnecting, so it does not report a false rise after returning in a different place.
16. After a new connection, the OVL flag and divider merging are determined again.

**Menu and display**

17. Choosing a Raysid from history could select a different unit if another one connected in the meantime.
18. A custom dose limit (e.g. 1.5 or 0.05) was displayed rounded, e.g. "2 uSv/h".
19. The API key could be extended to 49 characters while editing.
20. After toggling Link divider, the note at Divider was not refreshed immediately.
21. After deleting, the number of unsent points was not refreshed.
22. Corrupted stored settings (language, averaging, alarm length) would crash the menu. They are now clamped to valid values.
23. The "by reading count" average mixed in old values from another place after a long outage. It now reaches back at most 60 s.
24. Chart scale labels and distance were rounded incorrectly at boundaries, for example "100.0" or "1000 m".
25. The help text was re-wrapped on every scroll, so a long text scrolled jerkily.
26. Flashing during an alarm needlessly redrew the chart and other screens.

## Knowingly not fixed (low risk)
- When several measurement packets arrive in one notification, only the last one is counted. But the Raysid sends one packet about every 240 ms.
- When the app exits with completely full storage, at most about the last 100 points that can no longer be stored may be lost.
- The watch timer overflows after about 24.8 days of continuous running. The chart then shows nothing for one window.
- OVL and alarms now turn off after disconnecting. After a new connection the Raysid reports them again right away according to the current values.
