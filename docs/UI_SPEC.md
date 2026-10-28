# Pixtamer — UI Specification

Native macOS layout: `NavigationSplitView` (sidebar + detail) and a trailing inspector on the Batch
screen. Semantic system colours, one teal accent (`AccentColor`, separate dark variant), SF Symbols, tabular
digits for sizes. Light, dark and System appearance (Settings → Appearance).

Minimum main window: 860 × 540. Default: 1200 × 760. Inspector 300–460 pt, collapsible (⌥⌘I).

## Sidebar (⌘1–⌘4)

Batch (badge = queue count) · Presets · Recent Exports · Settings.

## A. Welcome / empty state (`WelcomeView`)

- App icon, "Pixtamer", one-line promise.
- Dashed drop zone: "Drop images or folders here", **Add Images…** (default button, prominent) and
  **Add Folder…**. Zone turns accent-coloured while a drag hovers.
- Three benefits (responsive sizes, presets, safe and local); collapses to a column in narrow windows.
- Footer: "Your images are processed on this Mac. No account, no upload."
- Content sits in a scroll view so the window can shrink without layout loops.

## B. Batch workspace (`BatchWorkspaceView`)

**Toolbar:** Add Images (⌘O), Add Folder (⇧⌘O) on the leading side; Remove Selected (⌘⌫), Clear Queue
(⇧⌘⌫), **Start Export** (prominent, ⌘E) on the trailing side. Disabled states carry a tooltip with the reason.

**Queue table:** Name (34 pt thumbnail, file name, type · transparency · profile), Dimensions, Size, Output,
Status. Multi-select; Delete key removes; double-click / Space / ⌘Y opens preview; context menu: Preview,
Show in Finder, Show Exported Files, Remove.

- Output column: planned result in secondary colour ("WebP · 1600×1067", "WebP · 2 sizes, 1 skipped");
  after export, the actual result ("WebP · 1440×960 · 20 KB (−93%)").
- Status: icon + text (never colour alone): Ready, Check (import warning), Waiting, Exporting (spinner),
  Done, Done (n of m), Partly failed, Failed, Skipped, Cancelled. Tooltip shows the detail.

**Import banner:** transient "Added 24 images. Ignored 2 non-image files." When anything is rejected, an
import report sheet lists each file and reason, with Copy List.

**Status bar:** "6 images → 12 files", recipe summary, first blocking issue (orange), destination button.

**Drag and drop:** anywhere on the workspace; accent outline while targeted.

## C. Export settings inspector (`ExportInspectorView`)

Grouped form, top to bottom:

1. **Selected Image** (only with exactly one selection): thumbnail, type, size, profile, warnings, Preview…
2. **Preset:** menu of presets (name + summary) and "Reset to Default Settings"; label shows "(edited)"
   when settings differ from the applied preset; **Save…** opens a name sheet with live validation.
3. **Format:** segmented control with available formats only; one-line explanation; WebP Lossless toggle;
   Quality slider 1–100 (hidden for lossless) with caption.
4. **Size:** mode picker. Fit: max width/height (empty = no limit). Exact: width, height, Preserve aspect
   ratio (crop vs stretch, explained). Multiple widths: removable chips, add field (accepts "320, 640"),
   Common menu. Do not upscale toggle (on by default) and a note counting outputs that will be skipped.
5. **File Names:** Original / Add suffix / Template; token menu `{name} {width} {height} {format} {index}`;
   Web-safe names toggle; live preview of the first outputs and "N images → M files".
6. **Destination:** folder + Choose…; Subfolder (none, by format, by width, custom); If a file exists
   (rename/skip/replace) with explanation.
7. **Metadata:** remove / keep without GPS / keep all with explanation; disabled for WebP with reason.

Errors (red, octagon icon) block export; warnings (orange, triangle) don't. Changing settings never encodes.

## D. Preview (`ImagePreviewView`, sheet)

Header: previous/next (← →), file name, "3 of 24", Original | Output, Fit | 100 %, Done (Esc).
Canvas: checkerboard only when transparency can appear; otherwise neutral background.
Info bar: Original (dimensions, size, format) and Output labelled **"actual file — Saved"** or
**"estimate — Not saved"**, with dimensions, size, format, change %. "Estimate Output" encodes in memory with
the export code path and writes nothing. 100 % is capped at 4096 px for very large images.

## E. Presets (`PresetManagerView`)

Split view: list (name, summary, checkmark on applied) with +/− buttons and context menu; detail form with
recipe rows; actions Apply to Batch, Update from Current Settings… (confirmation), Duplicate, Rename…,
Set as Default, Delete… (confirmation: "Exported files are not affected"). Empty state when none.

## F. Export progress (`ExportProgressView`, non-dismissable sheet)

Title (Exporting… / Retrying failed files… / Cancelling…), progress bar, "12 of 72 files", current file,
per-image list (waiting, spinner, done, partial, failed with message, skipped, cancelled), failed count,
Cancel (Esc). No Pause.

## G. Export results (`ExportResultsView`)

Headline + icon (complete / with problems / failed / cancelled / nothing exported), duration, recipe.
Counts: Exported, Skipped, Failed, Not processed. Size box: original → output, "89% smaller" or "% larger"
in orange, explanation of how totals are computed. Saved-to path. Details list (problems first) with file
name, source, dimensions or reason, error code, notes (renames). Actions: Start Another Batch, Retry Failed
(n), Show in Finder, Done.

## H. Settings (`SettingsView`, sidebar and ⌘,)

Defaults for new batches (format, quality, resize, max width, upscale, collision, metadata, use current /
apply to batch), Export folder behaviour, Include subfolders, Appearance, Reset to Defaults… (confirmation
naming what is and isn't reset).

## I. Help & About (`HelpAboutView`, Help menu)

Icon, version/build, privacy statement, per-format availability with encoder and reason, input formats,
keyboard shortcuts, known limitations, diagnostics text with Copy Diagnostics.

## Alerts and confirmations

Replace existing files (Replace / Keep Both / Cancel) · Nothing to export · Preset format unavailable ·
Data recovered at launch · Quit during export (Stop and Quit / Keep Exporting).

## Accessibility

Status icons have text labels; thumbnails are decorative; drop zone, chips, token menu, progress and
size comparisons have explicit labels/values; all actions reachable from the menu bar with shortcuts.
