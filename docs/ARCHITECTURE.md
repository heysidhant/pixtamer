# Pixtamer — Architecture

## 1. Layout

```
Pixtamer.xcodeproj          App target (synchronized folder groups; depends on the local package)
App/                          SwiftUI + AppKit UI only
  AppShell/                   App entry, AppModel (+ feature extensions), BatchModel, ExportSession, commands, RootView
  Workspace/                  Welcome/empty state, queue table, status bar, import report
  Inspector/                  Export settings inspector and its controls
  Preview/                    Original/output preview
  Presets/  Recents/  Settings/  Help/
  Support/                    Formatting, thumbnail cache, open panels, destination folder access
  Resources/Assets.xcassets   App icon, accent colour
Config/Pixtamer.entitlements
Packages/PixtamerKit/       Everything that is not UI (testable with `swift test`)
  Sources/CWebP/              Vendored libwebp 1.6.0 (C)
  Sources/PixtamerKit/
    Domain/                   Settings, inputs, results, errors, validation
    Import/                   ImageInspector (metadata only), ImageImporter (files/folders)
    ImageProcessing/          ResizePlanner, ImageRenderer, encoders, FormatCapabilities, ImageProcessor, Thumbnailer
    Export/                   FilenameRenderer, ExportPlanner, OutputWriter, BatchExporter
    Persistence/              VersionedJSONStore, PresetLibrary/PresetStore, AppPreferences, RecentExportHistory
    Support/                  BlockingWorkQueue, Diagnostics, decoding helpers
  Tests/PixtamerKitTests/   Swift Testing suites + generated fixtures
```

The package boundary enforces the rule that processing never imports SwiftUI.

## 2. Domain model

| Type | Role |
|---|---|
| `ImageInput` | One accepted source: URL, display-oriented `PixelSize`, bytes, type, alpha, orientation, profile, warnings. |
| `ExportSettings` | The recipe: format, quality, WebP lossless, `ResizeSettings`, `FilenameRule`, `SubfolderRule`, `MetadataPolicy`, `CollisionPolicy`. Every field decodes with a default. |
| `ExportPreset` | id, name, settings, timestamps. Stored in `PresetLibrary`. |
| `VariantPlan` | Output size + fill (whole / crop-to-fill / stretch) + requested width. |
| `ExportPlan` → `PlannedJob` → `PlannedVariant` | Fully resolved export: every output path decided before processing. |
| `VariantResult` / `VariantOutcome` | written(file, bytes) / skipped(reason) / failed(code, message) / cancelled. |
| `BatchSummary` | Counts and bytes computed only from written files. |

## 3. Pipeline

```
open panel / drop / Open With
        │ URLs
        ▼
ImageImporter ──► ImageInspector (CGImageSource properties only, no pixel decode)
        │ ImportReport: added, rejected (+reason), duplicates, ignored non-images
        ▼
BatchModel queue  ── thumbnails: ThumbnailLoader (cache, max 4 concurrent, BlockingWorkQueue)
        │
        ▼  Start Export
ExportPlanner (pure)
  ResizePlanner → variants per image (skip if it would upscale)
  FilenameRenderer → sanitised names
  collision resolution → final URLs, notes, planned skips
        │ ExportPlan
        ▼
BatchExporter  (≤ N jobs in flight, one source image per job)
  per job, on a BlockingWorkQueue thread:
    ImageProcessor.process
      open CGImageSource, re-check size (source changed?)
      for each variant:
        ImageRenderer.render  (thumbnail decode with orientation → exact-size 8-bit redraw)
        encoder.encode        (ImageIOEncoder or WebPEncoder → Data)
        OutputWriter.write    (hidden temp file → verify → atomic rename)
        │
        ▼ ExportEvent stream (jobStarted / variantFinished / jobFinished / finished)
ExportSession (main actor) → progress UI, results, queue status, recent history
```

### Sizing rules (`ResizePlanner`)

- The constrained side is exact; the other side is rounded to the nearest pixel (matches Image I/O).
- *Fit within*: scale = min(maxW/w, maxH/h), capped at 1 unless upscaling is allowed.
- *Exact size*: crop-to-fill (aspect kept) or stretch. Skipped if the source is smaller and upscaling is off.
- *Multiple widths*: de-duplicated, sorted; each width larger than the source is skipped (no upscale) and reported.

### Naming (`FilenameRenderer`)

Tokens `{name} {width} {height} {format} {index}`, single-pass expansion (a source called `{width}.jpg`
cannot be expanded twice). Sanitisation always removes `/ \ : * ? " < > |`, control characters, leading dots
and trailing dots/spaces, and limits names to 200 UTF-8 bytes. Web-safe mode transliterates to Latin,
strips accents, lowercases and hyphenates. Multiple-widths exports require `{width}` (templates) or append
`-{width}w` automatically (original/suffix modes).

### Collision policy (`ExportPlanner` + `OutputWriter`)

| Situation | Behaviour |
|---|---|
| Two outputs in one batch want the same name | Later ones get `-1`, `-2`… regardless of policy |
| Planned output path is a source image | Renamed regardless of policy; writer also refuses protected paths |
| File exists, policy Rename (default) | Next free `name-N.ext` |
| File exists, policy Skip | Planned as skipped with reason |
| File exists, policy Replace | Replaced, after a confirmation dialog listing the count |
| File appears after planning | Rename/Skip use `renamex_np(RENAME_EXCL)` so nothing is overwritten |

Path keys are symlink-resolved, Unicode-normalised and case-insensitive (conservative for APFS defaults).

### Safe writes

`OutputWriter` writes `.<name>.<token>.pixtamer-partial` next to the final file (same volume), re-opens it
to verify type, dimensions and decodability, then renames it into place. The temp file is removed in a
`defer`, so failures and cancellations leave nothing behind. Success is only reported with the size `stat`
returns for the final file.

## 4. Concurrency

- UI state (`AppModel`, `BatchModel`, `ExportSession`, `DestinationFolder`) is `@MainActor @Observable`.
- `BatchExporter` runs a detached task with a task group limited to `min(4, cores/2)` jobs.
- **All Image I/O and libwebp work runs on `BlockingWorkQueue`**, which starts a dedicated `Thread` per
  work item — outside both Swift's cooperative pool and GCD's constrained worker pool. The AVIF system
  encoder fans work out to GCD and waits on a dispatch group; when the caller came from a saturated
  constrained pool, that work never got a thread. This deadlocked twice during development (on cooperative
  threads under `swift test`, and on a concurrent GCD queue under `xcodebuild test`). Callers bound the
  number of threads (export job limit, 4 thumbnail decodes). Nothing in the app blocks a cooperative thread
  waiting for image work; capability detection uses the async `FormatCapabilities.detected()`.
- Cancellation: `ExportRun.cancel()` cancels the task; a `withTaskCancellationHandler` sets a
  `CancellationFlag` read by the processor between variants and before the final rename. Jobs never
  started are reported as `cancelled`.
- Memory: at most N decoded images exist at once; each variant is rendered inside an autorelease pool;
  thumbnails are decoded at ≤ 2× row size.

## 5. Persistence

`VersionedJSONStore` writes `{ "schemaVersion": n, "payload": … }` atomically to
`~/Library/Containers/com.heysidhant.Pixtamer/Data/Library/Application Support/Pixtamer/`:

| File | Content |
|---|---|
| `presets.json` | `PresetLibrary` (starter presets written on first launch only) |
| `preferences.json` | Defaults, destination behaviour, appearance, subfolder import, optional bookmark |
| `recent-exports.json` | Last 25 export summaries (counts, bytes, destination path) |

Corrupt files are moved aside as `name.corrupt-<timestamp>.json` and the user is told. Files written by a
newer schema load best-effort and are never overwritten (read-only). Unknown enum values fall back to defaults.

## 6. File access and sandbox

Entitlements: `app-sandbox`, `files.user-selected.read-write`, `files.bookmarks.app-scope`. No network
entitlement, so the app cannot open network connections.

- Inputs: open panel, drag and drop, and Open With grant read access for the session.
- Destination: chosen in an open panel (write access for the session). A security-scoped bookmark is
  stored only while "Remember the last export folder" is on; turning it off deletes the bookmark.
- Hidden temp files are written inside the chosen destination, which the sandbox already allows.

## 7. Errors and diagnostics

`ExportFailure` carries a stable code (`PB-DECODE`, `PB-WRITE`, …) and a message naming files by file name
only. Help → Diagnostics copies versions, format probe results, last summary and error codes; home paths are
redacted and no image data is included.
