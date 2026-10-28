# Pixtamer — Implementation Plan

Milestones follow PRD §10. `[x]` = done and verified as noted; `[ ]` = open.

## Milestone 0 — Repository audit and format spike ✅

- [x] Audit repository and toolchain → `PROJECT_AUDIT.md`
- [x] Confirm macOS 14.0 deployment target, Swift 6 language mode
- [x] Image I/O read/write type discovery on this Mac
- [x] JPEG/PNG/HEIC/AVIF/TIFF round trips: quality, alpha, orientation, sizing, malformed input, metadata, ICC
- [x] WebP PoC with vendored libwebp 1.6.0 (checksum-verified source, SwiftPM C target)
- [x] AVIF evaluated: system encoder works on macOS 27; libavif deferred
- [x] Format matrix → `FORMAT_SUPPORT.md`

## Milestone 1 — App shell ✅

- [x] Xcode project (synchronized groups) + local `PixtamerKit` package, sandbox entitlements, app icon
- [x] Window, sidebar navigation, toolbar, welcome/empty state
- [x] File and folder import (panel, drag and drop, Open With), duplicate detection, import report
- [x] Queue table with thumbnails, dimensions, sizes, output, status; multi-select, remove, clear
- [x] Inspector with selected-image details

## Milestone 2 — First processing slice ✅

- [x] Renderer (orientation, exact sizing, alpha/white flattening, colour space) and encoders (Image I/O, WebP)
- [x] Runtime format probe; unavailable formats hidden
- [x] Planner with destination, collision policy, source protection
- [x] Temp write → verify → atomic rename
- [x] Bounded background export, progress events, per-file failures, cancellation
- [x] Results with real on-disk sizes
- [x] Fix: image work moved to dedicated threads after reproducing AVIF deadlocks (cooperative pool, then GCD pool)

## Milestone 3 — Production batch workflow ✅

- [x] Presets: create, rename, duplicate, update, delete, apply, set as default; versioned JSON; starters
- [x] Multiple widths, no-upscale skips, exact crop/stretch
- [x] Filename templates, web-safe names, subfolders, live preview
- [x] Collision policies incl. replace confirmation; late-collision protection
- [x] Summary accounting, Retry Failed, Recent Exports history

## Milestone 4 — Beta polish (in progress)

- [x] Preview: original/output, actual vs estimate, fit/100 %, prev/next, checkerboard for transparency
- [x] Settings with reset confirmation; appearance
- [x] Help/About with formats, shortcuts, limitations, privacy, diagnostics
- [x] Keyboard shortcuts and menu commands
- [x] Accessibility labels on custom controls and status
- [x] README
- [x] `scripts/make-dmg.sh`: universal Release build → drag-to-install DMG (ad-hoc signed)
- [ ] VoiceOver walkthrough of every screen
- [ ] XCUITest target for the core flows (import → export, responsive, retry, cancel)
- [ ] Large-batch performance and memory profiling (500+ images, 24–48 MP) with Instruments
- [ ] Test on macOS 14 and 15 (deployment target; AVIF probe behaviour; UI APIs)
- [x] libwebp licence and patent grant bundled as `ThirdPartyNotices.txt`, linked from Help
- [ ] Automated tests for disk-full / permission-denied write failures
- [ ] Manual: drag and drop from Finder; quit during export

## Milestone 5 — Release preparation (not started)

- [ ] Choose distribution (Mac App Store vs Developer ID); real bundle identifier and team
- [ ] Developer ID signing + notarisation (only an Apple Development identity is installed today)
- [ ] Private beta checklist, feedback questions (PRD §12)

## Verification log

### 2026-10-14

| Command | Result |
|---|---|
| `swift test --package-path Packages/PixtamerKit` | 97 tests in 11 suites passed (≈4.7 s); repeated several times, no flakes |
| `cd Packages/PixtamerKit && xcodebuild -scheme PixtamerKit -destination 'platform=macOS' test` | TEST SUCCEEDED (97 tests); this runner exposed the second deadlock, now fixed |
| `xcodebuild -project Pixtamer.xcodeproj -scheme Pixtamer -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build` | BUILD SUCCEEDED, no compiler warnings |
| `codesign -d --entitlements -` on the built app | sandbox, user-selected read-write, app-scope bookmarks; no network |
| `otool -L` on the built app | system frameworks only; libwebp statically linked |

Manual run of the built app (driven with macOS UI scripting, sandbox active):

- [x] Launch shows the welcome screen (an initial layout loop crash in the welcome view was found and fixed)
- [x] Open With on a folder of 8 files: 6 images added, `broken.jpg` reported as unreadable, `notes.txt` ignored
- [x] Thumbnails, dimensions, sizes; rotated JPEG shown upright; transparency labelled
- [x] Applied starter preset "Responsive — 480/960/1440px": 6 images → 12 files, 6 upscale skips explained
- [x] ⌘E opened the folder panel; export wrote 12 valid WebP files with correct dimensions, no partial files
- [x] Results: 12 exported / 6 skipped / 0 failed; 1.5 MB → 162 KB matches the on-disk total (162,488 bytes)
- [x] Preview shows the actual exported file labelled "Saved" with dimensions and savings
- [x] Presets screen, Help window, dark appearance
- [x] Second export into the same folder: existing files kept, new outputs named `-1`, notes shown
- [x] After the threading change: AVIF export of 6 images (incl. rotated JPEG, transparent PNG) — 6 valid files, correct sizes, no partial files

### 2026-10-14 — test DMG

- `scripts/make-dmg.sh` → `dist/Pixtamer-0.1.0.dmg` (2.6 MB). `hdiutil verify` passed; `codesign --verify --deep --strict` passed; binary is `x86_64 arm64`.
- Release entitlements: sandbox, user-selected read-write, app-scope bookmarks only (`get-task-allow` removed via `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`).
- `spctl --assess` rejects the app, as expected for ad-hoc signing.
- Launched from the mounted DMG and exported 3 images to AVIF: valid files, rotation applied, no partial files.
