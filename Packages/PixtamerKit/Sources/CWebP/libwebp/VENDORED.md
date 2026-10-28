# Vendored libwebp

- Upstream: https://chromium.googlesource.com/webm/libwebp (release tarball)
- Version: 1.6.0
- Tarball: https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz
- SHA-256 of tarball: e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564
  (matches the checksum published in the Homebrew `webp` formula)
- License: BSD-3-Clause (see COPYING) plus the additional patent grant in PATENTS.

## What was copied

Only `*.c` and `*.h` files from `src/` and `sharpyuv/`. The `src/mux` and `src/demux`
directories were removed because Pixtamer only needs the still-image encoder
(decoding is handled by Apple Image I/O). No upstream file was modified.

## Updating

1. Download the new release tarball and verify its checksum.
2. Replace `src/` and `sharpyuv/` with the new `*.c`/`*.h` files (keep mux/demux out).
3. Replace COPYING, PATENTS and AUTHORS, then update this file.
4. Run `swift test --package-path Packages/PixtamerKit`.
