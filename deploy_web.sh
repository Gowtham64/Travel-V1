#!/bin/bash
set -e

TIMESTAMP=$(date +%s)

echo "=== Step 1: Building Flutter Web App ==="
cd mobile
flutter build web --base-href "/Travel-V1/" --release

echo "=== Step 2: Cache-busting JS references ==="
cd build/web

# Add timestamp query parameter to flutter_bootstrap.js in index.html
sed -i '' "s/flutter_bootstrap.js/flutter_bootstrap.js?v=${TIMESTAMP}/" index.html

# Rename main.dart.js to include timestamp, update the reference in flutter_bootstrap.js
mv main.dart.js "main.dart.${TIMESTAMP}.js"
sed -i '' "s/main.dart.js/main.dart.${TIMESTAMP}.js/" flutter_bootstrap.js

echo "=== Step 3: Preparing gh-pages Deployment ==="

# Remove any existing temp git repository
rm -rf .git

# Initialize a temporary git repository in the build folder
git init
git checkout -b gh-pages
git add .
git commit -m "Deploy web app update (build ${TIMESTAMP})"

# Add the remote and force push to gh-pages branch
git remote add origin https://github.com/Gowtham64/Travel-V1.git
echo "=== Step 4: Pushing to GitHub Pages ==="
git push -f origin gh-pages

echo "=== Deployment Successful! (build ${TIMESTAMP}) ==="
