# Pixtamer — Format Support

Status as of 2026-10-14. Verified on macOS 27.0.1 (Apple Silicon) with Xcode 27.0.
Runtime discovery decides what each user actually sees; nothing below is assumed on other macOS versions.

## 1. Output formats

| Format | Encoder | Shown when | Quality | Transparency | Colour profile | Metadata | Status |
|---|---|---|---|---|---|---|---|
| JPEG | Apple Image I/O | Probe passes (always on supported macOS) | 1–100 | No — flattened onto white | Source RGB profile embedded | Remove / keep without GPS / keep all | **Shipping** |
| PNG | Apple Image I/O | Probe passes | Lossless (no slider) | Yes | Source RGB profile embedded | Remove / keep without GPS / keep all | **Shipping** |
| WebP | libwebp 1.6.0, vendored (BSD-3-Clause) | Probe passes (bundled, so always) | 1–100, or lossless | Yes | Converted to sRGB (no ICC embedded) | Always removed | **Shipping** |
| AVIF | Apple Image I/O (VideoToolbox `AV1EncoderSW`) | System lists `public.avif` as writable **and** probe passes | 1–100 | Yes | Source RGB profile embedded | Remove / keep without GPS / keep all | **Shipping, runtime-gated** |
| HEIC, TIFF, others | Image I/O can write them | — | — | — | — | — | Not offered: not web delivery formats |

### The runtime probe

`FormatCapabilities.detect()` runs once at launch. For each format it:

1. Checks the encoder exists (Image I/O: `CGImageDestinationCopyTypeIdentifiers()`; WebP: compiled in).
2. Checks Image I/O can read the format back (needed to verify outputs).
3. Encodes a 16×16 image (half opaque, half transparent), decodes it, and checks type, size and — for
   formats that support it — that transparency survived.

A format that fails any step is hidden from the format picker, rejected by validation if a preset names
it, and listed with the reason in Help → Formats on This Mac and in copied diagnostics.

## 2. Input formats

Accepted when Image I/O on the running Mac can read them:

| Type | Notes |
|---|---|
| JPEG, PNG | Main targets. Truncation heuristic (missing JPEG EOI / PNG IEND) adds a warning. |
| HEIC / HEIF, AVIF, WebP, JPEG XL | Decoded by Image I/O. |
| TIFF, BMP | Decoded by Image I/O. |
| GIF | First frame only; animated files get a warning. |

Rejected with a reason, even though Image I/O can read some of them: camera RAW, PSD, PDF, OpenEXR/HDR,
DICOM, ICO/ICNS, TGA, KTX/ASTC. These need workflows (RAW development, layers, HDR) outside v1 scope.
Non-image files found while scanning folders are ignored and counted; unreadable or empty image files are
listed in the import report.

## 3. Processing behaviour common to all formats

- **Orientation:** EXIF orientation is applied to the pixels; outputs are written "up" (orientation 1),
  including when metadata is kept.
- **Pixel format:** every output is rendered into an 8-bit RGB(A) bitmap. CMYK and greyscale sources become
  RGB; 16-bit sources become 8-bit.
- **Colour:** the source RGB colour space is kept and embedded (JPEG, PNG, AVIF). Untagged or non-RGB sources
  are written as sRGB. WebP is always converted to sRGB because the bundled encoder cannot embed a profile.
- **Resizing:** decoded with Image I/O's subsampled thumbnail path, then redrawn with high-quality
  interpolation to the exact target size.
- **Verification:** every output is re-opened before it is given its final name: type, pixel size and a
  small decode must all match.

## 4. Spike results (Milestone 0)

Measured on this Mac (Apple Silicon, macOS 27.0.1), single-threaded, synthetic test patterns.

| Test | Result |
|---|---|
| JPEG quality 0.3 / 0.6 / 0.8 / 0.95, 1200×800 | 47.8 / 95.1 / 142.3 / 187.6 KB — monotonic |
| Alpha round trip 400×400 (PNG, HEIC, AVIF, TIFF) | Transparent pixel alpha 0, opaque 255 in all four |
| Alpha into JPEG | Alpha dropped (Pixtamer now composites onto white explicitly) |
| EXIF orientation 6, 600×400 stored | Thumbnail-with-transform returns 400×600 |
| Thumbnail sizing 3000×2000 → max 1000 | 1000×667 (nearest-pixel rounding; matches `ResizePlanner`) |
| Random bytes named `.jpg`, empty file | Source/type nil → rejected cleanly |
| Truncated JPEG (first third of file) | **Decodes without error** (grey fill) → truncation heuristic added |
| GPS in source, re-encoded without properties | GPS absent; with properties copied, GPS present |
| Display P3 source → PNG / AVIF | Profile "Display P3" preserved |
| AVIF encode 1×1, 7×5, 333×222 | All valid |
| AVIF encode 4000×3000 / 8000×6000 | 0.26 s / 0.75 s (JPEG: 0.012 s / 0.050 s) |
| WebP (libwebp 1.6.0, method 4) 640×480 q50/75/90 | 12.8 / 14.9 / 20.5 KB, alpha preserved, Image I/O and `dwebp` decode |
| WebP 4000×3000 q80 | 0.31 s, valid |

### Concurrency finding

Image I/O's AVIF encoder dispatches work internally and waits for it (stack: `AV1EncoderSW` in
`dispatch_group_wait`). Called from a thread of a saturated constrained pool — Swift's cooperative pool, or
a concurrent GCD queue when the cooperative threads were blocked — it deadlocked. Both cases were reproduced
in the test suite. All image decoding and encoding now runs on dedicated threads (`BlockingWorkQueue`);
see `ARCHITECTURE.md`.

## 5. Decisions

### WebP — integrated via vendored libwebp

Image I/O reads WebP but cannot write it on any macOS version tested. libwebp is the reference
implementation, BSD-3-Clause with an additional patent grant, and builds cleanly from source with SwiftPM.

- Source: official release tarball, SHA-256 `e4ab7009…4564`, identical to Homebrew's published checksum.
- Only `src/` (minus mux/demux) and `sharpyuv/` C files are compiled; static, no runtime dylib.
- Licence obligations: include COPYING and PATENTS in distributed builds' acknowledgements (see
  `Packages/PixtamerKit/Sources/CWebP/libwebp/VENDORED.md`). **To do before public release:** add an
  acknowledgements screen or file in the app bundle.
- Limitation: no ICC/EXIF in WebP output. Embedding them requires libwebp's mux API; deferred.

### AVIF — system encoder only, gated by probe

The system encoder passed every spike test on macOS 27 and needs no packaging, so AVIF is offered when, and
only when, the probe passes. **Not verified:** the first macOS version whose Image I/O can encode AVIF.
On the macOS 14 deployment target the option may be hidden; that is the intended behaviour.

A bundled libavif was evaluated on paper and **not integrated**: it needs an AV1 encoder (libaom —
BSD-2-Clause plus the AOMedia patent licence — or rav1e/SVT-AV1), adds several MB, and adds a C/C++ build
that must be maintained for two architectures. Revisit only if older-macOS AVIF export is a validated need.

## 6. Automated test coverage

`swift test --package-path Packages/PixtamerKit` and `xcodebuild test` on the package scheme — 97 tests,
all passing on 2026-10-14. The built app also exported WebP (responsive widths) and AVIF batches correctly
in a manual run. Format-specific
tests (in `ExportIntegrationTests` and `FormatCapabilitiesTests`):

- JPEG → WebP resize with on-disk size and type checks; source hash unchanged.
- Transparency preserved for PNG, WebP and AVIF (pixel alpha 0 and 255 checked); JPEG flattened to white.
- Orientation applied and normalised under all three metadata policies.
- JPEG quality 30 smaller than 90.
- WebP lossless round-trips pixels exactly.
- Metadata: remove / keep-without-GPS / keep-all verified on EXIF, IPTC and GPS blocks; WebP strips.
- Display P3 profile kept for PNG; WebP pixels converted to sRGB.
- Probe hides a broken encoder and a missing encoder.
