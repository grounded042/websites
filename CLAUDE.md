# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains jonhikes.com, a hiking blog built with Zola (static site generator) and deployed to a DigitalOcean server via NixOS/Colmena. The site features multi-format responsive images (AVIF/WebP/JPEG) generated from HEIC source files.

## Build & Deploy

### Development Shell

Enter the Nix development shell for Go/ImageMagick tools:
```bash
nix-shell
```

This provides: Go, ImageMagick with dev headers, Zola, and pkg-config.

### Cover Photo Tool

Build the interactive cover photo cropper:
```bash
nix-shell --run "go build -o cover-crop ./cmd/cover-crop"
```

Usage:
```bash
./cover-crop jonhikes/content/posts/my-trip/images/1.HEIC
```

Features:
- Calculates largest 3:1 crop from source image
- Interactive terminal preview (Kitty graphics protocol)
- Arrow keys to adjust vertical position
- Enter to save as cover.HEIC

**Note:** Preview requires running outside tmux (Kitty graphics protocol limitation).

### Local Development

Run the development server:
```bash
cd jonhikes
zola serve
```

The site will be available at http://127.0.0.1:1111

### Build & Deploy Process

Deploy the site (builds and syncs to server):
```bash
./scripts/deploy.sh
```

This script:
1. Generates site images (`scripts/generate_site_photos.sh`) - Converts cover and logo from HEIC
2. Generates post images (`scripts/generate_post_photos.sh`) - Converts all post images to AVIF/WebP/JPEG at multiple densities
3. Builds the static site (`zola build`)
4. Syncs to server via rsync

**Note:** Images are built locally (aarch64) because the server (x86_64) can't handle the CPU load. Cross-compilation with Nix is problematic, so we build locally and deploy the output.

### Infrastructure Deployment

Server infrastructure (nginx, SSL, etc.) is managed via Colmena:

```bash
colmena apply --build-on-target --on webserver
```

Target: 69.55.55.245 (webserver)

## Architecture

### Directory Structure

- `jonhikes/` - Zola site root
  - `content/posts/` - Blog posts (each post in its own directory with `index.md`)
  - `templates/` - Zola templates (base.html, blog.html, blog-page.html, etc.)
  - `static/images/` - Site-wide images (logo, cover)
  - `config.toml` - Zola configuration
  - `public/` - Build output (generated, not committed)
- `scripts/` - Image conversion and deployment scripts
- `flake.nix` - NixOS deployment configuration with nginx/ACME setup

### Image System

Images follow a specific workflow:

1. Source images are HEIC files (iPhone format)
2. Post images are in `content/posts/<post-name>/images/*.HEIC`
3. Site images are in `static/images/*.HEIC`
4. Build scripts convert HEIC to:
   - Post images: AVIF/WebP/JPEG at 800/1600/2400/3200px (1x/2x/3x/4x density)
   - Site cover: AVIF/WebP/JPEG at 800/1600/2400/3200/4000px (-800w/-1600w/-2400w/-3200w/-4000w)
   - Logo: AVIF/WebP/PNG at 300/600/900/1200px (1x/2x/3x/4x density)

Post images use max width of 800px with density variants. Cover images are 3:2 ratio (800x267px recommended).

### Zola Templates

The `post_img` macro in `templates/macros.html` generates responsive picture elements:
- Serves AVIF first (best compression)
- Falls back to WebP
- Falls back to JPEG/PNG
- Includes srcset for density variants

Usage in posts: `{{ post_img(path="images/photo.HEIC", alt="description") }}`

### Deployment Configuration

The nginx server (configured in flake.nix):
- Serves from `/site/jonhikes`
- SSL via ACME (Let's Encrypt)
- Brotli/Gzip/Zstd compression enabled
- Cache headers: 1 day default, 1 hour for feeds, 1 year for assets
- URL rewrites for old Medium URLs

## Working with Posts

Posts are in `jonhikes/content/posts/<slug>/index.md` with frontmatter:

```markdown
---
title: "Post Title"
date: 2024-04-20
extra:
  image: images/cover.HEIC
---
```

Images for each post go in `images/` subdirectory within the post folder.

## Nix Commands

Format Nix files:
```bash
alejandra .
```

Deploy infrastructure changes:
```bash
colmena apply --build-on-target --on webserver
```

The flake uses nixpkgs 25.11 stable for the server deployment configuration.
