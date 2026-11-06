# Pixtamer website

Plain static site in `public/`, with no build step. It is hosted on Cloudflare Pages at https://pixtamer.pages.dev.

## Preview

```sh
cd website/public && python3 -m http.server 4173
```

## Deploy

Run from the repository root:

```sh
npx wrangler pages deploy website/public --project-name pixtamer --branch main
```

Do not run `wrangler pages project create` again. The project already exists.

## New app release

In `public/index.html`, update the two download links, the JSON-LD version and download URL, and the version and size line in the hero.

## Hero figures

The hero map uses the real export shown in `docs/screenshot.png`: 10 images, 78.7 MB in, 30 WebP files, 927 KB out. Tile areas match each file's size. `.map-output` scales by 0.1085, the square root of 927 KB / 78.7 MB, so the shrunken map has the true area.

## Fonts

Anybody and Schibsted Grotesk are self-hosted under the SIL Open Font License 1.1. The licence texts are in `licenses/`.
