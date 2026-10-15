# GPS mapping and upload to Žhavá místa

Technical documentation of the modules `source/Recorder.mc` (recording points to the watch storage) and `source/Uploader.mc` (uploading to the web), plus `source/KeyEntry.mc` (API key). It describes the code as of version 1.1, build 82; it refers to functions, not line numbers. The overall architecture is described in [ARCHITECTURE.md](ARCHITECTURE.md).

## Contents

1. [Recording points](#1-recording-points)
2. [Storage format](#2-storage-format)
3. [Chunk queue and gradual deletion](#3-chunk-queue-and-gradual-deletion)
4. [Full storage and merging](#4-full-storage-and-merging)
5. [Uploader](#5-uploader)
6. [API key on the watch](#6-api-key-on-the-watch)
7. [Web endpoint contract](#7-web-endpoint-contract)
8. [Lifecycle and edge cases](#8-lifecycle-and-edge-cases)

---

## 1. Recording points

### 1.1 Enabling and states

`Recorder` has these flags:

| Field | Meaning |
|---|---|
| `enabled` | mapping module enabled (menu Žhavá místa → Mapping enabled, key `rEn`, default true). When off, the Mapping page and submenu are hidden. |
| `autostart` | record automatically after the app starts (`rAuto`) |
| `on` | recording is running, GPS is on |
| `paused` | paused, the route stays open |
| `full` | storage full, recording cannot be started (`rFull`) |
| `gpsOk` / `gpsWeak` | position with sufficient / insufficient quality |
| `noData` | GPS is there, but there is no valid data from the Raysid (points are not stored) |

Controls: the **UP button on the Mapping page** (`RaysidDelegate.onPreviousPage`) calls `recorder().pause()` when `on`, otherwise `recorder().start()`. After the app starts, `Recorder.resume()` closes a route that nothing ended last time (app crash), and with `autostart` calls `start()`. `initialize` itself always sets `on = false`.

```
           start()                 pause()
  stop ───────────────► on ───────────────────► paused
   ▲                    │ ▲                       │
   │  stop()/suspend()  │ └──────── start() ──────┘   (same route, statistics continue)
   └────────────────────┘
   storageFull() from any state → full (on = paused = false, GPS off)
```

- **`start()`**: does nothing when `full` or `!enabled`. From pause it just continues: adds the pause length to `_pausedSec` and resets the last position (the first point after the pause is stored immediately and the distance travelled during the pause is not counted). Otherwise it first closes any open route (`closeChunk(true)`; if that fails, `storageFull()` and done), resets the statistics (`session`, `meters`, `maxDose`, `maxCps`), sets `_start = Time.now()`, `_part = 1` and turns on GPS.
- **`pause()`**: turns off GPS, saves the pending points (`flush`) and the statistics. The route stays open.
- **`stop()`**: turns off GPS and closes the route with `closeChunk(true)`, so the last chunk goes to the web with `final = true`.
- **`suspend()`** (from `RaysidApp.onStop`): like `stop()`, but with `_noKick = true`, so that on app exit no request is sent whose response can no longer arrive. The chunk goes out on the next start.
- **`setEnabled(false)`** stops running or paused recording (`stop()`).

GPS (`gpsOn`): `LOCATION_CONTINUOUS`, tries the configurations `GPS_GLONASS_GALILEO_BEIDOU_L1_L5`, then `…_L1`, then `GPS_GALILEO`, otherwise the default.

### 1.2 Quality filter and spacing (`Recorder.onPosition`)

1. The watch gives only a quality level (`info.accuracy`), not accuracy in metres. There is a fix when `accuracy >= QUALITY_POOR` and `position != null`. `gpsOk = fix && accuracy >= minQ`; `minQ` is the GPS quality option: 4 good (default), 3 usable, 2 poor (key `rQual`).
2. Without `gpsOk` or when `!on`, nothing is stored.
3. **Fresh data from the Raysid:** `state.lastUpdate` younger than `FRESH_MS` = 5 s, known dose and cps, and **no OVL** (`state.ovl`). Otherwise `noData = true`, the point is not stored and `_lastPtMs` is moved to "now", so the average for the next point starts only after the outage or overload ends.
4. **Spacing:** distance from the last stored point, `Recorder.distance()` (planar approximation, 111,132 m per degree of latitude, 111,320 × cos(latitude) per degree of longitude). A point is created when `d >= dist` (option Point spacing, 5/8/10/12/15 m or custom 2–200 m, key `rDist`). The first point after start or pause is stored immediately.
5. `meters += d`, the position is remembered and `addPoint` is called.

On the display (`RaysidView.drawRecord`, `drawMapping`): red "REC N" only when `on && gpsOk && !noData`; orange "waiting for GPS", "weak GPS", "waiting for Raysid" or "OVL"; "paused", "full".

### 1.3 Point value (`Recorder.pointValues`)

- The dose and cps of a point = **average of all readings since the previous point, at most over the last `PT_AVG_MS` = 10 s** (`RaysidState.avgSince(from)`; always at least the last reading).
- After start, pause, data outage or OVL the start of the window is moved (see `_lastPtMs`), so values from the time when points were not being stored are not mixed in.
- It does not depend on the display averaging setting.
- The point time is the watch `Time.now()` at the moment of storing (unix, UTC), not the time of the GPS fix.

### 1.4 Routes

- `newRoute()` at the first point of a route:
  - `client_route_id = "garmin-" + first 6 characters of System.getDeviceSettings().uniqueIdentifier (otherwise "watch") + "-" + _start + "-" + _part`
  - name `"Raysid Garmin D. M. YYYY HH:MM"`, for further parts with ` (N)`.
- A route has at most **`ROUTE_MAX` = 5000 points** (`_routePts`). Point number 5000 closes the chunk with `final = true`, `_part++`, and the next point starts a new route with the same `_start`.
- The Mapping screen statistics (`session`, `meters`, `maxDose`, `maxCps`, `activeSec()`) apply from when recording was turned on and continue across pauses.

## 2. Storage format

Everything is in `Application.Storage`, writes go through the global `put()` (returns `false` instead of crashing when storage is full).

### 2.1 Point chunks `r<i>`

- Array of integers, **5 numbers per point** (`FIELDS`), at most **50 points per chunk** (`CHUNK`):

| Index in point | Value | Unit |
|---|---|---|
| 0 | latitude × 10⁶ | integer |
| 1 | longitude × 10⁶ | integer |
| 2 | unix time | s (UTC) |
| 3 | dose rate | nSv/h (µSv/h × 1000, rounded) |
| 4 | cps × 10 | rounded |

- `r<rChunks>` is the **pending** chunk (in memory `_buf`; `flush()` writes it to disk every `FLUSH_EVERY` = 10 points and on pause/exit).
- Chunks `r<rHead>` … `r<rChunks − 1>` are **closed** and waiting to be uploaded.

### 2.2 Chunk descriptor `rm<i>`

For each closed chunk (written by `closeChunk`):

| Index | Meaning |
|---|---|
| `meta[0]` | `client_route_id` (String) |
| `meta[1]` | batch number within the route, from 0 (`batch`) |
| `meta[2]` | `final`: last batch of the route (Boolean); it may also be an empty chunk, so that the server learns about the end |
| `meta[3]` | route name |
| `meta[4]` | **merge level**: how many times the chunk has already been merged (added by `compactStep`; older chunks lack the element = 0) |

A chunk from an older version without `rm<i>` gets a substitute descriptor `["garmin-old-<i>", 0, true, "Raysid Garmin"]` in `headChunk()`.

### 2.3 Other Recorder keys

| Key | Type | Meaning |
|---|---|---|
| `rEn` | Boolean | mapping enabled |
| `rAuto` | Boolean | record on start |
| `rDist` | Number | point spacing in m (clamped to 2–200) |
| `rQual` | Number | minimum GPS quality (`Position.QUALITY_*`, clamped POOR–GOOD) |
| `rCmp` | Number | `cmpMax`: 0, 1, 2, 3 or 99 (no limit); default 2 |
| `rHead` | Number | index of the oldest unsent chunk |
| `rChunks` | Number | index of the pending chunk (= number of chunks ever created) |
| `rCount` | Number | total unsent points (including the pending chunk); after merging it cannot be derived from the number of chunks |
| `rFull` | Boolean | storage full (persists across restart) |
| `rGc` | Array `[from, to]` | range of chunks waiting for gradual deletion |
| `rRoute` | String | `client_route_id` of the open route (missing = the next point starts a new one) |
| `rRName` | String | name of the open route |
| `rBatch` | Number | number of the next batch in the open route |
| `rRPts` | Number | points in the open route (for `ROUTE_MAX`) |
| `rPart` | Number | route part number (`_part`) |
| `rStart` | Number | unix time when recording was turned on (part of the route id) |
| `rSess`, `rMeters`, `rMaxD`, `rMaxC` | Number / Float | statistics since recording was turned on |
| `rSend` | Boolean | `sendReq`: send the whole queue now (set at `SEND_MIN` points, at the end of a route or by hand; cleared when the queue is empty) |
| `rUpAt` | Number | `lastUpAt`: unix time of the last accepted non-final batch of the open route (0 = nothing sent yet), for the 40-minute keep-alive |
| `rOn` | Boolean | written, but never read anywhere |

The order of writes in `closeChunk` is intentional: first `r<i>` and `rm<i>`, then `rBatch`, `rRPts`, `rCount` and **`rChunks` last**. A crash between writes thus cannot create a chunk with an old batch number (the server would discard it as a duplicate). At startup `Recorder.initialize` recalculates `count` from the chunks (only with ≤ 100 waiting chunks, because of the watchdog).

Capacity: `MAX_POINTS` = 4000 unsent points (soft limit, see chapter 4); the app's actual storage may run out sooner, which is handled by the return value of `put()`.

## 3. Chunk queue and gradual deletion

```
 rHead                               rChunks
   │                                    │
   ▼                                    ▼
 [r5][r6][r7][r8] ... [r11]          [r12 pending]
  ▲ sent by Uploader                  ▲ filled by addPoint / flush
  └ dropHead() after confirmation
```

- `pending()` = `rChunks − rHead` (closed chunks).
- `headChunk()` returns `[points, meta]` of the oldest chunk; a damaged chunk (points missing) is skipped via `dropHead()`.
- `dropHead()` deletes `r<head>` and `rm<head>`, advances `rHead`, decreases `rCount` and clears `full` when `count < MAX_POINTS`.

**Delete unsent** (`Recorder.clear`, menu Storage → confirmation):
1. `uploader().cancel()`: the response to the chunk currently being sent no longer deletes anything (`_sentId = ""`).
2. Running or paused recording is ended (`stop()` with `_noKick`, nothing is sent). The next route therefore gets a new id and does not collide on the web with batches already sent.
3. Numbering continues: `_chunks++`, `_head = _chunks`; `rHead` and `rChunks` are written and **then** `rGc = [from, to]` (`from` = start of an earlier unfinished `rGc`, otherwise the old `_head`; `to` = the old `_chunks`). A crash between writes leaves at most old chunks; nothing new is deleted.
4. Resets `count`, `session`, `full`, `paused`, the open route and any running merge.

The deletion itself is done by `Recorder.gcStep()` from the BLE timer (every 4 s), **at most 10 chunks** (`r<i>` and `rm<i>`) per call. Deleting hundreds of chunks at once could trip the watchdog.

## 4. Full storage and merging

### 4.1 When it is "full"

| Trigger | Where | Reaction |
|---|---|---|
| `count >= MAX_POINTS` (4000) after adding a point | `addPoint` | `startCompact()` |
| `put("r<i>")` in `flush()` fails | `flush` | `startCompact()` |
| `put` of the chunk or descriptor in `closeChunk()` fails | `closeChunk` | deletes `r<i>` (a chunk without a descriptor cannot be sent), the points stay in `_buf`; when no merge is running and `_buf` has at least 100 points (2 chunks), `storageFull()`, otherwise `startCompact()` |
| `cmpMax == 0` (Stop recording) | `startCompact` | `stop()` and `storageFull()` |
| merging freed nothing or not enough | end of `compactStep` | `stop()` and `storageFull()` |

`storageFull()`: one long 1.5 s vibration (only on the transition to full), `full = true` (`rFull`), `on = paused = false`, GPS off. Points already stored stay and go to the web. It does not close the route; the next `start()` closes it, and if that fails, it stays full.

`full` is cleared by: `dropHead()` after upload (when `count < MAX_POINTS`), raising `cmpMax` in the menu (`setCmpMax`), a successful merge, `clear()`, or at startup when `count < MAX_POINTS` and nothing is waiting.

### 4.2 "When full" options (`cmpMax`, `CMP_OPTS`)

| Option | `cmpMax` | Behaviour | Largest spacing at 5 m |
|---|---|---|---|
| Stop recording | 0 | recording ends | 5 m |
| Merge at most 1× | 1 | each chunk at most once | 10 m |
| Merge at most 2× (default) | 2 | at most twice | 20 m |
| Merge at most 3× | 3 | at most three times | 40 m |
| Merge without limit | 99 (`CMP_ANY`) | as long as chunks have at least 2 points | – |

The label with the spacing is computed by `cmpSubLabel()` as `dist << n`. According to `docs/code-review-2026-10-14.md` (simulation), about 4,000 / 8,000 / 15,000 / 27,000 points fit without uploading.

### 4.3 Algorithm (`startCompact`, `compactStep`)

- `startCompact()` sets `_cmpNext = rHead + 1` (**the oldest chunk is skipped**, because it may be being sent right now) and `_cmpGain = 0`.
- `compactStep()` processes at most `CMP_STEP` = 4 chunks per call. It is called after every added point (`addPoint`) and from the BLE timer via `compactTick()` when recording is not running, so a merge that has started finishes.
- A chunk is skipped when it has fewer than 2 points, lacks `rm<i>`, or `meta[4] >= cmpMax` (except 99).
- **Of each pair of neighbouring points, the one with the higher dose is kept** (index 3), together with its actual position and cps, but with the **time of the newer of the two** (index 2); an odd last point stays. Hotspots are thus not smeared, only the spacing grows.
- `rm<i>` with `meta[4] + 1` is written first, then `r<i>`; `count` is decreased by the freed points.
- The pending chunk `_buf` is not merged (the loop ends before `rChunks`).
- **End of a pass** (`_cmpNext >= rChunks`): saves `rCount`; when `_cmpGain == 0` (nothing to merge) or `count` is still ≥ `MAX_POINTS`, `stop()` + `storageFull()`. Otherwise, if it was full, `full = false`.
- The batch number (`meta[1]`) does not change with merging; the server just gets a smaller batch.

## 5. Uploader

The watch has no internet of its own: `Communications.makeWebRequest` goes through the Garmin Connect app on the phone (phone paired and in range). **One chunk at a time, oldest first** is sent; after confirmation the chunk is deleted from the watch.

**Sending in portions.** The website joins the batches of one route only when they arrive less than 1 hour apart; a batch that comes later becomes a separate small route. So the queue is not sent chunk by chunk, but drained all at once (`Recorder.sendReq`) when:

- unsent points (`count`, including the pending chunk) reach `SEND_MIN` = 500,
- a route ends (`closeChunk(true)`: stop, app exit, 5000 points), so short routes go out whole,
- the user selects Upload to web (`retry()`),
- part of the open route is already on the web (`lastUpAt > 0`) and `KEEP_SEC` = 40 min have passed since: the pending chunk is closed early (`closePartial()`, fewer than 50 points) and sent, so the route stays joined.

`sendReq` is cleared when the queue is empty. Every point carries the unix time when it was measured (`addPoint`), never the time of sending. Limitation: the rest of a route closed by app exit goes out on the next start; if part of that route was sent more than an hour earlier, the web shows it as a separate route.

### 5.1 When it runs

- `Uploader.start()` (from `RaysidApp.onStart` and when mapping is enabled in the menu) starts the timer `TICK_MS` = 30 s, only when `active()` = mapping enabled or `recorder().pending() > 0`. At startup, with a key filled in and `verify == :vfIdle`, it starts verification.
- `kick()` is called from the timer, from `Recorder.closeChunk` (new chunk), after every successful or discarded response (the next chunk right away), from `retry()` (selecting Upload to web in the menu), from `settingsChanged()` and after a successful verification.
- After mapping is disabled, the timer stops only when nothing is waiting; unsent points keep being sent.

### 5.2 `kick()` step by step

1. A request in progress younger than `BUSY_MAX_MS` = 120 s → nothing. Older → it is considered lost, `_lost++` (a late response is then ignored) and it continues.
2. `!active()` → done, no state change.
3. Property `zmUpload` false → state `:upOff` ("off").
4. Key missing (`currentKey()`) → `:upNoKey`.
5. An earlier 401/403 (`_authFailed`) → `:upAuth`, nothing is sent until the key is changed by `settingsChanged()`, `retry()` or a successful verification.
6. Gate: unless `sendReq`, it is set when `count >= SEND_MIN`, or after the keep-alive (`closePartial()` itself calls `kick()`, which sends; the outer call then returns because `_busy`).
7. No closed chunk → `sendReq = false` and `:upHold` ("collecting points") when points are waiting in the pending chunk, `:upWait` ("ongoing") when recording or paused, otherwise `:upDone` ("all sent"). Closed chunks but no `sendReq` → `:upHold`.
8. Phone not connected (`System.getDeviceSettings().phoneConnected`) → `:upNoPhone`.
9. Builds the body and headers, `_busy = true`, `_sentId = meta[0] + "#" + meta[1]`, state `:upSending` and `makeWebRequest(url(), body, options, method(:onResponse))`. Exception while sending → `_busy = false`, `:upErr`.

### 5.3 Request

```
POST https://www.zhavamista.cz/api/1.0/all/route-points      (Uploader.DEFAULT_URL; overridden by the zmUrl property)
Content-Type: application/json                                (Communications.REQUEST_CONTENT_TYPE_JSON)
Authorization: Bearer <API key>
X-API-Key: <API key>
```

Body (a `Dictionary` converted to JSON by Connect IQ):

| Field | Source | Note |
|---|---|---|
| `client_route_id` | `meta[0]` | e.g. `garmin-3a9f1c-1791916357-1` |
| `batch` | `meta[1]` | batch order within the route, from 0 |
| `final` | `meta[2]` | last batch of the route |
| `name` | `meta[3]` | `Raysid Garmin 13. 10. 2026 18:40` |
| `device` | constant | `"RAYSID"` |
| `points` | chunk `r<i>` | array `[lat, lon, unix time, µSv/h, cps]`; conversion `lat/1e6` (Double), `dose/1000`, `cps/10` |

### 5.4 Handling the response (`onResponse`)

| Situation | Decision | Consequence |
|---|---|---|
| `_lost > 0` | late response to a request that timed out | `_lost--`, nothing else (the chunk was sent again in the meantime; the server does not duplicate the batch thanks to `client_route_id` + `batch`) |
| 2xx and body without `state`/`status`, or `"ok"` | success | `sent += number of points`, `dropHead()`, `kick()` right away; a possible `verify == :vfBad` changes to `:vfOk` |
| 2xx, but `state`/`status` is not `"ok"` | error | `:upErr`, retried at the next tick |
| **400, 409, 413, 422** | the server permanently rejected the batch content | the chunk is **discarded** (`dropHead()`) and it continues with the next one, so that one bad batch does not block the queue |
| **401, 403** | wrong key | `_authFailed = true`, `:upAuth` ("wrong API key"), nothing more is sent |
| others (404, 405, 408, 429, 5xx, negative Connect IQ codes) | outage, wrong address, later | `:upErr` + code, the data stay, retried in 30 s |

Protection against deleting the wrong chunk: `dropHead()` is called only when `chunkId(headChunk().meta)` is still equal to `_sentId`. After `clear()` (`cancel()` resets `_sentId`) or another change of the queue, the response therefore deletes nothing.

### 5.5 Key verification (`startVerify`, `onVerify`)

- Address: in `url()`, `route-points` is replaced with `user-info`; when a custom address does not contain `route-points`, `https://www.zhavamista.cz/api/1.0/all/user-info` is used.
- `GET` with the header `Authorization: Bearer <key>` (without `X-API-Key`), JSON response.
- 200 and `state == "ok"` → `:vfOk`, name from `user.nickname` (`verifyName`), clears `_authFailed` and calls `kick()`. 200 with another `state` → `:vfBad`.
- 401/403 → `:vfBad` ("key rejected"); negative code → `:vfNoPhone`; otherwise `:vfErr` + code. Without a key `:vfNoKey`, without a phone `:vfNoPhone`.
- A running verification is not repeated (an older response would overwrite a newer one); the new menu item is only remembered so that its label gets refreshed.
- It is started at app startup, after saving the key on the watch, after a settings change in Garmin Connect, and manually with the Test connection item.

### 5.6 Sequence

```
Recorder                    Uploader                       Garmin Connect (phone)          Žhavá místa
   │ closeChunk(final?)        │                                  │                              │
   │── kick() ────────────────►│                                  │                              │
   │                           │ headChunk() → [points, meta]     │                              │
   │◄──────────────────────────│                                  │                              │
   │                           │ makeWebRequest(POST JSON) ──────►│── HTTPS POST route-points ──►│
   │                           │   _busy, _sentId = id#batch      │                              │ stores the batch
   │                           │                                  │◄─ 200 {"state":"ok",…} ──────│ (ignores duplicate id+batch)
   │                           │◄──────── onResponse(200, data) ──│                              │
   │ dropHead() ◄──────────────│ (only when head == _sentId)      │                              │
   │                           │ kick() → next chunk …            │                              │
   │                           │                                  │                              │
   │        no response for 120 s: next kick() → _lost++ and the same chunk again;              │
   │        the late response to the first attempt is discarded (_lost--)                       │
```

### 5.7 States for the user

`Uploader.label()` = state text (`:upOff`, `:upNoKey`, `:upNoPhone`, `:upSending`, `:upHold`, `:upWait`, `:upDone`, `:upAuth`, `:upErr` + code) and, when there are unsent points, ", queued N" (`recorder().count`). The Mapping screen shows a "Web: …" line in red on error or a rejected key, and in green after a successful verification.

## 6. API key on the watch

- Where: menu **Žhavá místa → Web and upload → API key** (`KeyEntryView` + `KeyEntryDelegate`). For the app from the Store, the key can also be set in Garmin Connect (property `zmKey`, type password); for an app sideloaded over USB, the settings in Garmin Connect do not work.
- The Žhavá místa key is 48 hexadecimal characters (`KEY_LEN`); the character picker offers only `0123456789abcdef` (`KEY_CHARS`) and `OK` at the end.
- Controls: UP/DOWN selects a character, START adds it (after the 48th character the cursor jumps to OK), START on OK saves, BACK deletes the last character and closes the screen when the entry is empty. Touch and swipe are ignored, nothing needs to be held. When a key is already entered, the cursor starts on OK (START = close without change).
- Display: the entered text in groups of four, 16 characters per line, the last 3 lines are visible; in the menu only the end of the key `...abcd` (`keyLabel()`).
- Saving (`KeyEntryDelegate.save`): `Application.Properties.setValue("zmKey", …)` and a **backup** in `Storage` `zmKeyBak` (in case the settings are lost during an app update), then `uploader().settingsChanged()` and `startVerify()`. The length is not checked; a shorter key can also be saved.
- Reading: `currentKey()` returns `zmKey`, and when it is empty, `zmKeyBak`.
- Security: the key is stored in the watch storage as plain text (Properties and the backup). It does not belong in documentation, logs or commits.

## 7. Web endpoint contract

The endpoint was created at the project's request; the proposal for the API maintainer is in [zhavamista/endpoint-proposal.md](zhavamista/endpoint-proposal.md). The website has been running it since 14 Oct 2026. Official Žhavá místa API documentation: <https://mapa.zhavamista.cz/api-docs.html> .

Summary of the proposal:

- **Why a new endpoint:** routes could previously only be created by uploading a file (multipart), which `makeWebRequest` cannot do (only JSON or urlencoded). The endpoint for stations does not accept a position. The watch has little memory, so it sends in batches.
- **Request:** `POST /api/1.0/all/route-points`, `Content-Type: application/json`, authentication `Authorization: Bearer <token>` or `X-API-Key` (the app sends both).
- **Body:** `client_route_id`, `batch`, `final`, `name`, `device`, `points` (see section 5.3).
  - The first request with a new `client_route_id` creates the route, further ones add to it.
  - The server should recognize a batch by the pair `client_route_id` + `batch` and not store it a second time, but reply with a normal `ok` (the watch resends after a timeout).
  - `final: true` on the last batch; the server may finalize the route. A route has at most 5000 points, then the watch starts a new one with another `client_route_id`.
  - Point `[lat, lng, time (unix s, UTC), µSv/h, cps]`, typically 50 points per batch. `name` and `device` are enough from the first batch.
- **Response:** `{"state": "ok", "route_id": …, "points": …}`; error HTTP 4xx with `{"state": "error", "message": "…"}`. On 401 the watch shows a wrong key and stops sending; on 5xx it tries later.
- **Authentication:** ideally a long-term user key (the Bearer token from `/login` is valid for only 30 days).

Differences between the proposal and the code worth knowing about:
- The proposal gives the name `Garmin 13. 10. 2026 18:40`, the code sends `Raysid Garmin …`.
- Besides 401, the code also stops sending on 403 and discards batches on 400/409/413/422 (the proposal does not specify this). Other 4xx (404, 405, 408, 429) are retried.
- The code also recognizes success by the `status` field, or when the JSON has no state at all.
- Verification uses `GET …/user-info` (not part of the proposal) and reads `state` and `user.nickname`.

## 8. Lifecycle and edge cases

| Situation | What happens |
|---|---|
| App crash during recording | On the next start `resume()` closes the open route (`rRoute`) with a chunk with `final = true`; `count` is recalculated. |
| App exit (BACK) | `suspend()` closes the route without sending; the chunk goes out on the next start. |
| Pause | GPS off, route open; the next UP continues the same route. |
| Raysid disconnected / OVL during recording | GPS runs, points are not stored (`noData`), the display shows "waiting for Raysid" / "OVL". |
| Full storage | See chapter 4; recording ends with "full" and a long vibration. |
| Phone out of range | `:upNoPhone`, an attempt every 30 s. |
| Web not responding | after 120 s a new attempt with the same batch, the late response is ignored. |
| Deletion during upload | the response deletes nothing (`cancel()`), chunks are deleted gradually via `gcStep`. |
| Mapping disabled | recording stops and the route is closed; unsent chunks keep being sent. |
| Route over 5000 points | it is closed with `final = true`, the next point starts part `(2)` with the same `rStart`. |
