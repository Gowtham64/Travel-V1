"""
Repository Agent
Analyzes the codebase structure, frameworks, dependencies, and build/test targets
to construct the authoritative Project AI Map.
"""

import os
import json
from typing import Dict, Any

def map_repository(root_dir: str = ".") -> Dict[str, Any]:
    """Inspects the workspace and constructs an environmental and architectural map."""
    has_backend = os.path.exists(os.path.join(root_dir, "backend"))
    has_mobile = os.path.exists(os.path.join(root_dir, "mobile"))
    has_web = os.path.exists(os.path.join(root_dir, "web"))
    has_ios = os.path.exists(os.path.join(root_dir, "mobile/ios"))
    has_android = os.path.exists(os.path.join(root_dir, "mobile/android"))

    project_map = {
        "project_name": "VoyPlan",
        "platforms": {
            "web": has_web or has_mobile,
            "android": has_android,
            "ios": has_ios,
            "backend_api": has_backend
        },
        "languages": [
            "Dart", "JavaScript", "TypeScript", "Python", "Swift", "Kotlin"
        ],
        "frameworks": {
            "mobile": "Flutter 3.x",
            "backend": "Node.js / Express.js",
            "routing": "OSRM / Mapbox GL JS",
            "database": "Supabase PostgreSQL"
        },
        "test_commands": {
            "backend_unit": "npm test -- --forceExit",
            "mobile_unit": "flutter test",
            "e2e_web": "npx playwright test",
            "regression": "npm test -- --forceExit && flutter test"
        },
        "build_commands": {
            "backend": "node -c src/index.js",
            "web": "flutter build web --release",
            "android_apk": "flutter build apk --release",
            "ios_bundle": "flutter build ios --release"
        },
        "entry_points": {
            "backend": "backend/src/index.js",
            "mobile": "mobile/lib/main.dart",
            "web_landing": "web/index.html"
        }
    }
    return project_map

if __name__ == "__main__":
    rep = map_repository()
    print(json.dumps(rep, indent=2))
