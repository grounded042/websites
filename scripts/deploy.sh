#!/usr/bin/env bash
set -e

# Go to repo root
cd "$(dirname "$0")/.."

echo "Generating site images..."
./scripts/generate_site_photos.sh

echo "Generating post images..."
./scripts/generate_post_photos.sh

echo "Building site with Zola..."
cd jonhikes && zola build && cd ..

echo "Deploying to server..."
rsync -avz --delete jonhikes/public/ root@69.55.55.245:/site/jonhikes/

echo "✓ Deployment complete!"
