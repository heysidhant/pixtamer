# Pixtamer — User Flows

Each flow lists the steps, the success condition and how it is verified. "Unit" = automated test in
`Packages/PixtamerKit/Tests`; "App run" = the manual run on 2026-10-14 recorded in `IMPLEMENTATION_PLAN.md`.

## Flow A — Quick batch export

1. Launch → welcome screen.
2. Add Images / Add Folder / drop / Open With → queue shows thumbnails, dimensions, sizes.
3. Choose format, quality, max width in the inspector; file-name preview updates.
4. Start Export (⌘E). If no folder is chosen yet, the folder panel opens.
5. Progress sheet → results sheet with real totals → Show in Finder.

**Success:** every planned output ends written, skipped or failed; outputs open; originals unchanged.
**Verified:** Unit (`jpegToWebPFitWidthKeepsSourceUnchanged`, `summaryMatchesDisk`); App run.

## Flow B — Responsive images

1. Import → Size: Multiple widths → 480, 960, 1440 (or apply "Responsive — 480/960/1440px").
2. Name: template `{name}-{width}w` (or original name, which appends `-{width}w`).
3. Preview shows names and "N images → M files"; a note counts widths skipped to avoid upscaling.
4. Export; optional subfolder by width.

**Success:** exact expected variant count, aspect ratio kept, no upscaling, collision policy applied.
**Verified:** Unit (`responsiveWidthsProduceExpectedFiles`, `aspectRatioPreserved`, `variantCountForResponsiveExport`); App run (6 sources → 12 files, 6 skipped).

## Flow C — Save and reuse a preset

1. Configure settings → Preset → Save… → unique name (duplicates rejected inline).
2. Later batch → Preset menu → apply; or Presets screen → Apply to Batch.
3. Quit and relaunch → preset is still listed and produces the same recipe.

**Success:** persists across relaunch; duplicating/editing never mutates another preset.
**Verified:** Unit (`presetsSurviveRelaunch`, `duplicateDoesNotMutateOriginal`, `starterPresetsExportSuccessfully`); App run (starter preset applied and exported).

## Flow D — Partial failure and retry

1. A batch where one file is damaged or deleted after import.
2. Valid images still export; the bad one is Failed with an actionable message and code.
3. Fix the file → Retry Failed → only failed outputs run, with the same names.

**Success:** no crash, accurate counts, no duplicate successful outputs.
**Verified:** Unit (`partialFailureIsIsolatedAndRetryDoesNotDuplicate`, `missingSourceFailsWithActionableMessage`).
Malformed files at import time are rejected with reasons (Unit `malformedFilesAreRejectedNotCrashing`; App run).

## Flow E — Collision-safe export

1. Destination already contains `photo.webp`.
2. Policy Rename → `photo-1.webp`; Skip → reported as skipped; Replace → confirmation dialog, then replaced.
3. Destination is the source folder with the same name and format → output renamed, source untouched.

**Success:** no silent data loss; source never overwritten.
**Verified:** Unit (`collisionPoliciesOnDisk`, `exportingIntoSourceFolderNeverOverwritesSource`,
`finalizerRefusesProtectedPath`, `lateCollisionIsRenamedAtomically`, planner tests).

## Flow F — Cancel

1. Start a large export → Cancel.
2. Files in progress finish verifying or are discarded; unstarted ones become "Not processed".

**Success:** no partial files, every planned output has a final state, results sheet explains.
**Verified:** Unit (`cancellationLeavesOnlyCompleteFiles`). Quitting during export asks, cancels, then quits — implemented, not yet exercised manually.

## Edge cases

| Case | Behaviour |
|---|---|
| Same file added twice | Counted as duplicate, not re-added |
| Folder with documents/hidden files | Non-images ignored and counted; hidden files skipped |
| RAW/PSD/TGA | Rejected: "<type> images are not supported." |
| Truncated JPEG/PNG | Imported with a "may be incomplete" warning |
| Source deleted or changed after import | That image fails with PB-SRC-MISSING / PB-SRC-UNREADABLE; others continue |
| Every output would upscale | "Nothing to export" alert before anything runs |
| Preset uses a format unavailable on this Mac | Alert; format falls back; validation blocks export until changed |
| Disk full / permission denied | Failed with readable reason; temp file removed (implemented; no automated test yet) |
| Destination folder deleted between exports | Folder panel opens again |
| Corrupt presets file | Moved aside, starters restored, user told at launch |
