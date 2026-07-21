#!/bin/bash
set -e

TIMESTAMP=$(date +%s)
DEPLOY_DIR="gh-pages-deploy"

echo "=== Step 1: Cleaning up old deployment directory ==="
rm -rf $DEPLOY_DIR
mkdir $DEPLOY_DIR

echo "=== Step 2: Building Flutter Web App into /app sub-directory ==="
cd mobile
# The base href must point to the subdirectory where the app will live.
flutter build web --base-href "/Travel-V1/app/" --release
cd .. # back to project root

echo "=== Step 3: Preparing deployment directory ==="
# Copy the static landing page and its assets to the root of the deployment dir
cp index.html $DEPLOY_DIR/
if [ -f "favicon.png" ]; then
    cp favicon.png $DEPLOY_DIR/
fi
if [ -f "preview.png" ]; then
    cp preview.png $DEPLOY_DIR/
fi

# Create the /app subdirectory and move the flutter build into it
mkdir $DEPLOY_DIR/app
mv mobile/build/web/* $DEPLOY_DIR/app/

echo "=== Step 4: Cache-busting JS references ==="
cd $DEPLOY_DIR/app

# Add timestamp query parameter to flutter_bootstrap.js in index.html
sed -i '' "s/flutter_bootstrap.js/flutter_bootstrap.js?v=${TIMESTAMP}/" index.html

# Rename main.dart.js to include timestamp, update the reference in flutter_bootstrap.js
mv main.dart.js "main.dart.${TIMESTAMP}.js"
sed -i '' "s/main.dart.js/main.dart.${TIMESTAMP}.js/" flutter_bootstrap.js

# Delete service worker file to disable caching of stale JS files
rm -f flutter_service_worker.js

cd ../.. # back to project root

echo "=== Step 5: Preparing gh-pages Deployment ==="
cd $DEPLOY_DIR

# Initialize a temporary git repository in the build folder
git init
git checkout -b gh-pages
git add .
git commit -m "Deploy static landing page + web app (build ${TIMESTAMP})"

# Add the remote and force push to gh-pages branch
git remote add origin https://github.com/Gowtham64/Travel-V1.git
echo "=== Step 6: Pushing to GitHub Pages ==="
git push -f origin gh-pages

cd .. # back to project root
echo "=== Deployment Successful! (build ${TIMESTAMP}) ==="
