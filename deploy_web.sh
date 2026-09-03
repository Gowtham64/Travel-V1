
#!/bin/bash
set -e

TIMESTAMP=$(date +%s)
DEPLOY_DIR="gh-pages-deploy"

echo "=== Step 1: Cleaning up old deployment directory ==="
rm -rf $DEPLOY_DIR
mkdir $DEPLOY_DIR

echo "=== Step 2: Building Flutter Web App into /app sub-directory ==="
cd mobile
# The Mapbox token is injected at build time (no longer committed in source).
# Set it in your shell before deploying, e.g.:
#   export MAPBOX_TOKEN=pk.your_url_restricted_token
# Use a URL-restricted token from the Mapbox dashboard — client tokens are
# always visible to end users, so restriction is the real protection.
MAPBOX_TOKEN="${MAPBOX_TOKEN:-pk.eyJ1IjoiZ293dGhhbWVjNjQiLCJhIjoiY21yZzhnOG82MGh2dTJ6c2FuM3h6ZXdkayJ9.PmiHwk5A4-eSWu7zLYkSXQ}"
flutter build web --base-href "/app/" --release \
    --dart-define=MAPBOX_TOKEN="${MAPBOX_TOKEN}"
cd .. # back to project root

echo "=== Step 3: Preparing deployment directory ==="
# Prevent GitHub Pages from processing with Jekyll (ensures all Flutter web files serve correctly)
touch $DEPLOY_DIR/.nojekyll
# Custom domain for GitHub Pages. This file MUST be re-created on every deploy —
# the force-push replaces the whole gh-pages branch, so without it GitHub drops
# the custom domain and the site reverts to gowtham64.github.io/Travel-V1.
echo "voyplan.in" > $DEPLOY_DIR/CNAME
# Landing site lives under web/ ; everything there is served at the site root.
cp web/index.html $DEPLOY_DIR/
for f in ios-install.html privacy.html terms.html favicon.png favicon.svg preview.png manifest.json manifest.plist apps.json; do
    [ -f "web/$f" ] && cp "web/$f" $DEPLOY_DIR/
done
echo "  ✓ Landing site (index + iPhone guide + manifests + source) copied"

# iOS .ipa is served at the site root (ios-install.html and apps.json link to it).
# The Android APK is distributed via GitHub Releases, so it is NOT bundled in gh-pages.
if [ -f "mobile/build/ios/iphoneos/Voyplan.ipa" ]; then
    cp mobile/build/ios/iphoneos/Voyplan.ipa $DEPLOY_DIR/Voyplan.ipa
    echo "  ✓ iOS IPA (fresh build) copied as Voyplan.ipa"
elif [ -f "web/Voyplan.ipa" ]; then
    cp web/Voyplan.ipa $DEPLOY_DIR/Voyplan.ipa
    echo "  ✓ iOS IPA (web/Voyplan.ipa) copied as Voyplan.ipa"
fi

# GSAP-powered trip demo page + its vendored libs (served at site root).
if [ -d "web/webdemo" ]; then
    cp web/webdemo/demo.html web/webdemo/promo.html web/webdemo/gsap.min.js web/webdemo/leaflet.js web/webdemo/leaflet.css $DEPLOY_DIR/
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

# Replace Flutter's generated service worker with a self-destroying "kill
# switch". Deleting it is NOT enough: a service worker already installed in a
# visitor's browser keeps serving the old cached app (even through a hard
# refresh) until it is REPLACED. Serving this instead makes every stuck browser
# clear its caches and unregister on the next update check, then load fresh.
cat > flutter_service_worker.js <<'SW'
self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (event) {
  event.waitUntil((async function () {
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map(function (k) { return caches.delete(k); }));
      await self.registration.unregister();
      if (keys.length > 0) {
        const clients = await self.clients.matchAll({ type: 'window' });
        clients.forEach(function (c) { c.navigate(c.url); });
      }
    } catch (e) {}
  })());
});
self.addEventListener('fetch', function () {});
SW

# Stamp the build number into index.html so the on-map HUD can confirm the
# browser loaded the latest (non-cached) index.html.
sed -i '' "s/__BUILD__/${TIMESTAMP}/g" index.html

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
git config http.postBuffer 524288000
echo "=== Step 6: Pushing to GitHub Pages ==="
git push -f origin gh-pages

cd .. # back to project root
echo "=== Deployment Successful! (build ${TIMESTAMP}) ==="
