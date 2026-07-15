#!/bin/bash
set -e

echo "=== Step 1: Building Flutter Web App ==="
cd mobile
flutter build web --base-href "/Travel-V1/" --release

echo "=== Step 2: Preparing gh-pages Deployment ==="
cd build/web

# Remove any existing temp git repository
rm -rf .git

# Initialize a temporary git repository in the build folder
git init
git checkout -b gh-pages
git add .
git commit -m "Deploy web app update (automated build)"

# Add the remote and force push to gh-pages branch
git remote add origin https://github.com/Gowtham64/Travel-V1.git
echo "=== Step 3: Pushing to GitHub Pages ==="
git push -f origin gh-pages

echo "=== Deployment Successful! ==="
