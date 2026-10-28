# Pixtamer — Project Audit

**Audit date:** 2026-10-14
**Auditor:** initial engineering pass before implementation

## 1. Repository state at start

| Item | Finding |
|---|---|
| Repository type | Blank. Not a git repository. |
| Contents | the product brief (PRD v0.1, kept private) and a Finder `.DS_Store`. |
| Xcode project | None. |
| Swift sources / tests | None. |
| Assets | None. |
| Dependencies | None. |

There was no existing code to preserve. The PRD is treated as the primary product source;
`docs/PRODUCT_REQUIREMENTS.md` reconciles it with what was actually built.

## 2. Development environment

| Item | Value | How verified |
|---|---|---|
| Host OS | macOS 27.0.1 (build 26A434), Apple Silicon (arm64) | `sw_vers`, `uname -m` |
| Xcode | 27.0 (27A266a) | `xcodebuild -version` |
| Swift | 6.4 (swiftlang-6.4.0.34.1) | `swift --version` |
| Project generators | xcodegen / tuist not installed | `which` |
| Homebrew `webp` | 1.6.0 (used only for `cwebp`/`dwebp` cross-checks in the spike, never linked) | `brew list --versions` |

Can be built and tested here: SwiftPM package build and `swift test`, `xcodebuild` builds of the
macOS app, launching the built app. Cannot be verified automatically here: interactive UI flows
(clicking through panels, drag-and-drop from Finder), VoiceOver, and behavior on macOS 14–26.
Those are listed as manual checks in `docs/IMPLEMENTATION_PLAN.md`.

## 3. Decisions made from the audit

1. **Project structure.** Because no project existed, a new one was created:
   - `Packages/PixtamerKit` — Swift package with all non-UI logic (domain, import, image
     processing, export, persistence) plus the vendored WebP encoder. Testable with `swift test`
     without launching the UI.
   - `Pixtamer.xcodeproj` + `App/` — the SwiftUI/AppKit application target, which depends on the
     local package. The project uses Xcode file-system-synchronized groups, so new files in `App/`
     are picked up without editing the project file.
2. **Deployment target: macOS 14.0.** Required APIs (`@Observable`, `.inspector`,
   `ContentUnavailableView`, `onKeyPress`, SwiftUI `Table`) are all macOS 14+. Format availability
   is discovered at runtime, so no format is assumed from the build machine's OS.
3. **Language mode: Swift 6** with strict concurrency checking for both package and app.
4. **Tests: Swift Testing** (`import Testing`), run through `swift test`.
5. **Third-party code: libwebp 1.6.0 only**, vendored as source (BSD-3-Clause) because Image I/O
   cannot encode WebP. See `docs/FORMAT_SUPPORT.md`.
6. **Sandbox: enabled**, with user-selected read/write files and app-scoped bookmarks (used only
   when the user turns on "Remember last export folder").

## 4. Risks identified

| Risk | Status |
|---|---|
| Image I/O encoder availability differs on older macOS releases (notably AVIF). | Mitigated by a runtime probe; formats that fail the probe are hidden. Only verified on macOS 27. |
| Truncated JPEG/PNG files decode "successfully" in Image I/O (grey fill). | Import adds a "file may be truncated" warning using end-marker checks. Cannot be fully detected. |
| Interactive UI not testable in this environment. | Partly resolved: the built app was driven with macOS UI scripting (see the verification log in `IMPLEMENTATION_PLAN.md`). Core logic covered by package tests. |
| System AVIF encoder can deadlock when called from a saturated thread pool. | Found during testing; all image work moved to dedicated threads (`BlockingWorkQueue`). |
