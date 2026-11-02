# BOKKI Chart

On-screen color charts for tuning camera color on iPhone and iPad.

- Reference charts from published data: X-Rite ColorChecker Classic (before/after Nov 2014), 1976, 2005, BabelColor average, SG 140, TE226 V2 (45)
- Physical-ratio and full-screen-fill layouts
- Per-patch values at 24, 16, 10 and 8 bit, in Display P3 and sRGB
- Color editor per patch: Lab, LCh, RGB (8/10/16 bit, hex) and HSV with gradient tracks, selectable step size, ΔE2000 against the original, undo / redo; saved as custom charts
- Pre-shoot D-Log slate for later color matching
- Brightness locked to 100% while a chart is open
- Skin tone charts: ITA six-class scale (BOKKI-defined chroma), Monk Skin Tone Scale, CC24 skin patches
- BOKKI CAM calibration link: shows the charts and full-screen colors BOKKI CAM asks for; BOKKI CAM can list every grid chart (grays, skin tones, hue, white balance, custom) and send its own color grids (CALIB1102)
- English and Korean UI, following the device language

## Build

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open BOKKIColor.xcodeproj
```

Requires Xcode 16+ and iOS 17+. The `.xcodeproj` is not committed; regenerate it after a fresh checkout or after editing `project.yml`.

## Project layout

| Folder | Contents |
|---|---|
| `BOKKIColor/App` | App entry, `HomeView`, `Localization.swift` (`tr()`) |
| `BOKKIColor/Color` | Lab / XYZ / Bradford math, output spaces (Display P3, sRGB), per-patch value formatting, `ColorEdit.swift` (LCh, HSV, ΔE2000) |
| `BOKKIColor/Data` | Chart models, catalog, generated charts (grays, CCT, hue wheel, skin ITA, ...), custom chart store |
| `BOKKIColor/Charts` | Chart screen, patch grid, patterns, slate, per-patch detail, `PatchColorEditor` (color editor) |
| `BOKKIColor/Display` | Pre-shoot display check, brightness lock, shoot-mode shortcuts |
| `BOKKIColor/Calibration` | BOKKI CAM link (`_bokki-calib`, QR token pairing, CALIBV2 results), `CalibrationCatalog` (CALIB1102 chart catalog and custom grids) and the full-screen target |
| `docs/calibration` | Protocol documents shared with BOKKI CAM (`CALIB1102-chart-catalog.md`) |
| `BOKKIColor/Resources` | Chart datasets (JSON) and the `BOKKI Shoot Mode.bokkishortcut` file |

## Localization

- Korean text is the string key: `tr("한국어 문장")` is `NSLocalizedString`. `Localizable.xcstrings` holds the `ko` and `en` values; `InfoPlist.xcstrings` localizes the Local Network prompt.
- Interpolated strings use `String(format: tr("... %@ ..."), x)`. Enum raw values stay Korean literals and are translated at render time with `tr(rawValue)`.
- Add a new user-facing string by wrapping it in `tr()` and adding its `en` value to the catalog. English wording says "chart", never "checker".
- The development language is `ko`; the app follows the device language (no in-app switch).

## Debug-only launch arguments

Used for App Store captures and previews; compiled out of Release.

| Argument | Effect |
|---|---|
| `-openChart <id>` | Opens that chart at launch (e.g. `slate`, `cc24_after2014`) |
| `-slate.camera <name>` | Sets the slate camera name |
| `-demoTour YES` | Scrolls the home list and walks through the display check, calibration screen and four charts on its own |

Language for a capture: `-AppleLanguages (en)` or `(ko)`.

## BOKKI CAM calibration link

The base protocol (CALIB1101) is defined in the BOKKI CAM repository (`docs/calibration/CALIB1101-checker-link.md`); `CalibrationLink.swift` mirrors it field for field. The link runs over MultipeerConnectivity (service type `bokki-calib`, Bonjour `_bokki-calib._tcp` / `_udp`): BOKKI Chart advertises, BOKKI CAM pairs by QR token, then requests charts or full-screen colors step by step. The `app` identifier is `BOKKI Chart`; BOKKI CAM does not validate it. The bundle ID stays `com.bokki.checker` and the URL scheme stays `bokkichecker`.

CALIB1102 (`docs/calibration/CALIB1102-chart-catalog.md`, also in the BOKKI CAM repo) adds, announced in `ready.features` as `catalog` and `custom`, with `pv` unchanged:

- `catalog` / `describe`: the CAM lists every grid chart (id, title, category, size) and reads a chart's colors without showing it.
- `show` with target `patches`: a grid of colors the CAM defines (Display P3 or Lab D50, at most 1024) drawn with the same fiducials, margin and gap as every chart.
- `clipped` on patches that are outside Display P3.
- Result screen: shows the per-LUT verify error when the CAM sends `result.verifyLUTs` (`CalibrationResult.LUTVerify`). That field is defined on the BOKKI CAM branch `claude/serene-jones-d0a0e2`, not merged to its `main` yet.

Known gaps: the pairing token is advertised in discovery info and checked on the invitation only when the CAM sends one in the invitation context; a rejoin is recognised by an equal display name. Both need a BOKKI CAM change to tighten.

## Release

- Bundle `com.bokki.checker`, team `4FWG8XXYM7`, marketing version 1.0, build number `CURRENT_PROJECT_VERSION` in `project.yml` (build 5 is the one in review).
- Archive and export need a local `ExportOptions.plist` (not committed), then upload with `xcrun altool --upload-app` using an App Store Connect API key.
- The site lives in the `bokkiyaw` Cloudflare Pages project: `bokkiyaw.com/products/chart/`, `/support/chart/`, `/privacy/chart/` (old `/checker/` URLs redirect). Support mail: support@bokkiyaw.com.
- App Privacy answers are set in the App Store Connect web UI only.

## Tests

```bash
xcodebuild -project BOKKIColor.xcodeproj -scheme BOKKIColor \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Data sources

- X-Rite (2016), *New color specifications for ColorChecker SG and Classic Charts*
- BabelColor, ColorChecker averages
- Image Engineering TE226 V2 data sheet
- Dataset files come from [colour-science](https://github.com/colour-science/colour) (BSD-3-Clause)
- Monk Skin Tone Scale, Google, CC BY 4.0
- ITA skin tone classes: Del Bino et al. (Pigment Cell Research, 2006); mean facial hue angle: Wang, Luo et al., *Spectrophotometric measurement of human skin colour*, Color Research & Application 42(6), 2017

Values marked "BOKKI 정의" in the app are app-defined and are not published standards.
ColorChecker is a trademark of X-Rite/Calibrite. This project is not affiliated with them.
