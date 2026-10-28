# Pixtamer — Product Requirements

Reconciles the original product brief (PRD v0.1, kept private) with what has been built. Screen details are in `UI_SPEC.md`, journeys in `USER_FLOWS.md`, format facts in
`FORMAT_SUPPORT.md`.

## 1. Goal

A local-first native Mac app that turns folders of source images into consistently named, optimised,
web-ready assets in one batch: convert, compress, resize (including responsive widths), rename, and report
real before/after sizes — with reusable presets and exports that can never damage the originals.

## 2. Users

| Persona | Need |
|---|---|
| Frontend developer | WebP/AVIF/JPEG at fixed widths with predictable `{name}-{width}w` names. |
| Shopify / e-commerce operator | Consistent product image sizes (fit or square crop) and smaller files. |
| Designer / agency | Reusable per-client presets, a review step, reliable results. |

## 3. Principles

Local-first (no account, upload, telemetry or network access) · safe by default (originals never
modified, collisions explicit) · predictable (same preset + same inputs = same names) · honest (real
on-disk sizes; estimates labelled) · native Mac behaviour · no non-functional controls.

## 4. v1 scope and status

| # | Requirement | Status |
|---|---|---|
| R1 | Import files and folders via panel, drag and drop, Open With | Done |
| R2 | Detect supported inputs at runtime; per-file rejection reasons; duplicates prevented | Done |
| R3 | Queue with thumbnail, name, dimensions, size, planned/actual output, status; multi-select, remove, clear | Done |
| R4 | Offer only output formats that pass a runtime probe | Done (JPEG, PNG, WebP; AVIF when probe passes) |
| R5 | Quality for lossy formats; WebP lossless | Done |
| R6 | Resize: original, fit within W/H, exact (crop or stretch), multiple widths; no upscale by default | Done |
| R7 | Filename rules: original, suffix, template with tokens; web-safe option; live preview | Done |
| R8 | Destination folder; optional subfolder (format, width, custom) | Done |
| R9 | Collision policy: rename (default), skip, replace; sources never overwritten | Done |
| R10 | Metadata: remove (default), keep without GPS, keep all (not WebP) | Done |
| R11 | Validation with inline errors that block export | Done |
| R12 | Background export with bounded parallelism, progress, per-file status, cancel | Done |
| R13 | Results with exported/skipped/failed counts, real bytes, savings (negative shown), destination | Done |
| R14 | Retry failed outputs only; open output folder; start another batch | Done |
| R15 | Presets: create, rename, duplicate, update, delete, apply, set as default; persist; versioned | Done |
| R16 | Preview: original vs output, actual vs estimate labelled, fit/100 %, prev/next, checkerboard | Done |
| R17 | Settings: defaults, destination behaviour, subfolder import, appearance, reset with confirmation | Done |
| R18 | Help/About: version, formats, shortcuts, limitations, privacy, copyable diagnostics without paths | Done |
| R19 | Light/dark, keyboard shortcuts, accessibility labels | Done; VoiceOver audit pending |
| R20 | Automated tests for naming, sizing, collisions, presets, accounting, formats, failure isolation | Done (97 tests) |

## 5. Non-goals for v1

Accounts, cloud storage or sync, subscriptions or licence server, analytics, AI features, editing/filters,
video or animated GIF output, RAW development, watch folders, CLI/Shortcuts, plug-ins, Pause (Cancel only).

## 6. Decisions that refine the PRD

| Topic | Decision | Reason |
|---|---|---|
| Default metadata | **Remove** | Web assets; GPS privacy; smaller files. Keeping is one click away. |
| Default format | WebP 80 | Bundled, so always available; best fit for the web audience. |
| Responsive widths larger than the source | Skipped and reported | No silent upscaling; the PRD's "warn" is shown both before and after export. |
| Duplicate output names in one batch | Always numbered | Replacing would destroy another output from the same batch. |
| Retry Failed | Re-runs failed outputs with the original plan (same settings and names) | Cannot duplicate successful outputs. Changed settings = new export. |
| Destination memory | Off by default; bookmark only when enabled | Persist sandbox access only when needed. |
| Percentage saved with responsive variants | Originals counted once vs. sum of all variants | Stated under the totals in the results sheet. |

## 7. Acceptance criteria (beta)

PRD §9 criteria 1–13 are met by automated tests plus the manual run recorded in
`IMPLEMENTATION_PLAN.md`. Open items: 14 (clean macOS account, older macOS releases), VoiceOver audit, and
interactive drag-and-drop from Finder (code path shared with Open With, which was verified).
