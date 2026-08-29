
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
if [ -z "${MAPBOX_TOKEN:-}" ]; then
    echo "⚠️  WARNING: MAPBOX_TOKEN is not set — map tiles/globe will not load."
    echo "    Run: export MAPBOX_TOKEN=pk.your_token   before deploying."
fi
# The base href must point to the subdirectory where the app will live.
flutter build web --base-href "/Travel-V1/app/" --release \
    --dart-define=MAPBOX_TOKEN="${MAPBOX_TOKEN:-}"
cd .. # back to project root

echo "=== Step 3: Preparing deployment directory ==="
# Prevent GitHub Pages from processing with Jekyll (ensures all Flutter web files serve correctly)
touch $DEPLOY_DIR/.nojekyll
cp index.html $DEPLOY_DIR/
if [ -f "ios-install.html" ]; then
    cp ios-install.html $DEPLOY_DIR/
    echo "  ✓ iPhone install guide page copied to deployment as ios-install.html"
fi
if [ -f "favicon.png" ]; then
    cp favicon.png $DEPLOY_DIR/
fi
if [ -f "favicon.svg" ]; then
    cp favicon.svg $DEPLOY_DIR/
fi
if [ -f "preview.png" ]; then
    cp preview.png $DEPLOY_DIR/
fi
if [ -f "manifest.json" ]; then
    cp manifest.json $DEPLOY_DIR/
fi
if [ -f "manifest.plist" ]; then
    cp manifest.plist $DEPLOY_DIR/
    echo "  ✓ iOS OTA Download Manifest copied to deployment as manifest.plist"
fi
if [ -f "apps.json" ]; then
    cp apps.json $DEPLOY_DIR/
    echo "  ✓ SideStore/AltStore source copied to deployment as apps.json"
fi
if [ -f "mobile/build/app/outputs/flutter-apk/app-release.apk" ]; then
    cp mobile/build/app/outputs/flutter-apk/app-release.apk $DEPLOY_DIR/Voyplan.apk
    echo "  ✓ Android APK copied to deployment as Voyplan.apk"
elif [ -f "Voyplan.apk" ]; then
    cp Voyplan.apk $DEPLOY_DIR/Voyplan.apk
    echo "  ✓ Root Voyplan.apk copied to deployment as Voyplan.apk"
fi
if [ -f "mobile/build/ios/ipa/Voyplan.ipa" ]; then
    cp mobile/build/ios/ipa/Voyplan.ipa $DEPLOY_DIR/Voyplan.ipa
    echo "  ✓ iOS IPA package copied to deployment as Voyplan.ipa"
elif [ -f "Voyplan.ipa" ]; then
    cp Voyplan.ipa $DEPLOY_DIR/Voyplan.ipa
    echo "  ✓ Root Voyplan.ipa copied to deployment as Voyplan.ipa"
fi
if [ -f "Voyplan-Simulator.zip" ]; then
    cp Voyplan-Simulator.zip $DEPLOY_DIR/Voyplan-Simulator.zip
    echo "  ✓ iOS Simulator bundle copied to deployment as Voyplan-Simulator.zip"
fi

# GSAP-powered trip demo page + its vendored libs (served at site root).
if [ -d "webdemo" ]; then
    cp webdemo/demo.html webdemo/promo.html webdemo/gsap.min.js webdemo/leaflet.js webdemo/leaflet.css $DEPLOY_DIR/
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
