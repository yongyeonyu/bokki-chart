# CALIB1102 — BOKKI CAM ↔ BOKKI Chart: chart catalog and custom colours (additive to CALIB1101)

Extends [CALIB1101](CALIB1101-checker-link.md) so BOKKI CAM can use **every chart BOKKI Chart has**
(grays, skin tones, hue grids, white-balance fields, video bars, the user's custom charts) and can
also **send its own colours** to be shown. Protocol version stays **`pv` 1**: everything here is
additive and announced in `ready.features`, so an old CAM or an old Chart keeps working.

Both apps implement this document; the copy in each repository is the same text.

## Feature flags

`ready.features` (Chart → CAM) lists what this Chart build supports. CAM must not send a message
whose feature is missing.

| feature | adds |
|---|---|
| `catalog` | `catalog` and `describe` requests; `ready.charts` lists every showable chart id |
| `custom` | target `{"kind": "patches"}`; `clipped` on patches |

CALIB1101 features (`handshake`, `results`) are unchanged.

## Chart ids

`ready.charts` and `catalog` use the ids of the Chart app's catalog. Only **grid charts** are
listed (every patch in a rows × columns grid); ramps, the slate and optics patterns are not.

| category | examples |
|---|---|
| `reference` | `cc24_after2014`, `cc24_before2014`, `cc24_2005`, `cc24_babel`, `cc24_1976`, `sg140_after2014`, `sg140_before2014`, `te226_v2` |
| `combo` | video style, photo style, CC24+, wide gamut, 55 swatches |
| `gray` | 3-step, 6-step, L* 11 / 21 steps, 32-step code values, near black, near white, gray / white / black fields |
| `wb` | colour-temperature strip and fields (2700 … 7500 K) |
| `skin` | ITA six-class scale, Korean skin tones, Monk Skin Tone Scale |
| `hue` | hue grids (24 / 36), saturation sweep, memory colours |
| `video` | 7-bar, EBU, full bars |
| `custom` | the user's imported or tuned charts |

Ids of custom charts are chosen by the user's device, so the CAM takes them from `catalog`.

## CAM → Chart

### `catalog` (feature `catalog`)

`{"type": "catalog"}` — Chart answers with `catalog`.

### `describe` (feature `catalog`)

`{"type": "describe", "seq"?: Int, "id": "<chart id>"}` — Chart answers with `described`, or `error`
for an unknown id. Nothing is put on screen; use it to read a chart's colours before showing it.

### `show` with target `patches` (feature `custom`)

```json
{"type": "show", "seq": 7,
 "target": {"kind": "patches", "rows": 2, "columns": 3,
            "patches": [{"name": "skin A", "lab": [65, 18, 17]},
                        {"name": "gray 50", "p3": [0.5, 0.5, 0.5]}, ...]}}
```

- `rows * columns` must equal the number of patches, at most **1024**; row-major order.
- Each patch has **either** `p3` (Display P3 gamma-encoded, three numbers in 0…1) **or** `lab`
  (CIE L*a*b* D50: L* 0…100, a* and b* within ±200). `name` is optional and echoed back.
- The grid is drawn as sent (no rotation): same fiducials, margin and gap as every chart
  (CALIB1101 Layout), so the CAM's patch finder is unchanged. `layout.orientation` tells the screen's
  orientation, so the CAM chooses `rows` / `columns` for it.
- Invalid input is answered with `error` (`seq` echoed) and nothing changes on screen.

`show` with `{"kind": "chart", "id": ...}` works for every id in `catalog`, not only the CC24 charts.

## Chart → CAM

### `ready`

As CALIB1101, with `features` `["handshake", "results", "catalog", "custom"]` and `charts`
listing every showable id.

### `catalog`

```json
{"type": "catalog", "catalog": [
  {"id": "cc24_after2014", "title": "…", "category": "reference", "subtitle": "…",
   "rows": 4, "columns": 6, "count": 24, "source": "…"} ]}
```

`title` and `subtitle` are in the Chart's UI language (Korean or English) and are for display
only; `id` is the stable key. `subtitle` and `source` may be missing.

### `described`

`{"type": "described", "id": "<id>", "info": <catalog row>, "patches": [<Patch>, …]}` — `patches`
as in CALIB1101 (`index`, `name`, `row`, `column`, `p3`, `lab`), in the chart's own orientation.

### `shown`

As CALIB1101. For a `patches` target `patches` carries the colours as drawn.

### Patch: new field

`clipped`: `true` when the colour is outside Display P3, so `p3` is clipped and differs from the
requested or published colour. `lab` is always the exact definition (published value or the
requested `lab`). Absent means false. The CAM should treat a clipped patch as unreliable for
colour correction.

## Notes for the CAM

- Colour values compare as in CALIB1101: `lab` is the reference, `p3` is what the screen emits.
- Use `catalog` once after `ready`, then pick: gray charts for tone curves and white balance, skin
  charts for skin correction, `patches` for a measured set (for example a skin set built from a
  face sample).
- Request `describe` before `show` when the CAM needs the patch list to plan the shots.
