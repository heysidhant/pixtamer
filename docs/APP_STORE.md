# Mac App Store submission

Everything needed to submit Pixtamer 1.0.0. Limits in brackets are Apple's.

## Checklist

1. In [App Store Connect](https://appstoreconnect.apple.com), choose **Apps → + → New App**:
   - Platform: macOS
   - Name: Pixtamer
   - Primary language: English (U.S.)
   - Bundle ID: `com.heysidhant.Pixtamer`
   - SKU: `pixtamer-mac`
2. Fill in the listing, App Privacy and App Review sections below.
3. Upload the build: `UPLOAD=1 scripts/make-appstore.sh`. Increase `BUILD_NUMBER` for each later upload.
4. Install it through TestFlight and work through "Test before submitting".
5. Select the build, choose **Manually release this version**, and submit for review.

## Listing

**Name** [30]

Pixtamer

**Subtitle** [30]

Batch Image Optimizer for Web

**Promotional text** [170]

Turn a folder of images into web-ready JPEG, PNG, WebP or AVIF in one batch. Everything runs on your Mac, with no account and no upload.

**Keywords** [100]

webp,avif,jpeg,png,heic,compress,convert,resize,rename,batch,srcset,responsive,optimize,web,photo

**Description** [4000]

```text
Pixtamer turns a folder of photos, screenshots or design exports into web-ready images in one batch: the right format, the right size and a clean file name, with real before-and-after sizes for every file.

Drop in images or whole folders, pick a format and size, and export. Everything runs on your Mac. There's no account and no upload, and your originals are never changed.

CONVERT
JPEG, PNG, WebP and AVIF output. Reads JPEG, PNG, HEIC/HEIF, WebP, AVIF, TIFF, GIF, BMP and JPEG XL, depending on your version of macOS. AVIF output appears when your Mac's encoder supports it.

COMPRESS
Set the quality, or use lossless WebP. Keep metadata or strip it.

RESIZE
Fit a box, set an exact size, or export several widths at once. One source can become 480w, 960w and 1440w files for srcset, and small images are never upscaled.

RENAME
Web-safe names turn "Homepage Hero (FINAL).heic" into "homepage-hero-final.webp". Add a suffix, or use a template like {name}-{width}w.

ORGANISE
Sort output into subfolders by format or by width.

PRESETS
Save a recipe once and apply it to the next batch.

PRIVATE BY DESIGN
Pixtamer is sandboxed and can read only the files you add. It writes only to the folder you choose.

OPEN SOURCE
Pixtamer is free and open source under the MIT licence.
```

**What's New** (first version: not requested)

**URLs**

- Support: `https://github.com/heysidhant/pixtamer/issues`
- Marketing: `https://pixtamer.pages.dev`
- Privacy policy: `https://pixtamer.pages.dev/privacy/`

**Other fields**

- Category: Graphics & Design. Secondary: Photography.
- Price: Free, all territories.
- Copyright: 2026 Sidhant Sinha
- Age rating: answer "None" or "No" throughout.
- Third-party content: No. Bundled open-source code is listed in Third-Party Notices.

**Screenshots** (Mac, 2880 × 1800)

Use the files in `marketing-media/app-store/`, which stays out of this repository. They are in upload order.

## App Privacy

Select **Data Not Collected**. Pixtamer has no analytics, account or server.

## App Review

**Sign-in required:** No.

**Notes:**

```text
Pixtamer needs no account. To test:
1. Drag a few images or a folder into the window, or choose Add Images.
2. Choose a format and size in the panel on the right.
3. Choose Start Export and pick an output folder.
4. Open the results with Show in Finder.

All processing is on-device. The app is sandboxed, has no network entitlement, and uses only user-selected file access. Links in Help open in the default browser. Source code: https://github.com/heysidhant/pixtamer
```

**Export compliance:** handled by `ITSAppUsesNonExemptEncryption = NO`. Pixtamer uses no encryption.

## Test before submitting

Use the TestFlight build, not an Xcode run.

- [ ] Add images by drag and drop and with the open panel.
- [ ] Add a folder, export it, and confirm files land in the chosen folder.
- [ ] Quit and reopen. Confirm presets and "Remember the last export folder" still work.
- [ ] Help opens, and its Privacy Policy and Support links work.
- [ ] The MightyBench section is absent. It stays in GitHub and Homebrew builds only, because App Store rules outside the US bar links to purchases made elsewhere.
- [ ] macOS 14 and 15, or raise `MACOSX_DEPLOYMENT_TARGET` to the oldest version tested.

## Signing

`scripts/make-appstore.sh` signs with team `RUCQNP5F6L` using automatic signing. The project keeps an empty team and ad-hoc signing, so anyone can build it without an Apple account.

## Later: Pixtamer Pro

Before any in-app purchase work, test StoreKit in TestFlight without `com.apple.security.network.client`. If the entitlement proves necessary, change every "no network access" claim in the README, Help, `PRIVACY.md` and this listing.
