"""
Workspace resolution utility to correctly locate the repository root
regardless of whether scripts are run from repository root, subfolders, or CI.
"""

import os

def resolve_workspace(explicit_path: str = None) -> str:
    if explicit_path and os.path.exists(explicit_path):
        candidate = os.path.abspath(explicit_path)
        if os.path.exists(os.path.join(candidate, "voyplan-ai-engineering")):
            return candidate
        if os.path.exists(os.path.join(candidate, "backend")):
            return candidate

    # Check current working directory
    cwd = os.path.abspath(os.getcwd())
    if os.path.exists(os.path.join(cwd, "voyplan-ai-engineering")):
        return cwd
    if os.path.basename(cwd) == "voyplan-ai-engineering":
        return os.path.abspath(os.path.join(cwd, ".."))

    # Fallback using file location
    file_dir = os.path.abspath(os.path.dirname(__file__))
    # agents/common -> agents -> voyplan-ai-engineering -> travel-app
    parent_travel_app = os.path.abspath(os.path.join(file_dir, "../../.."))
    if os.path.exists(os.path.join(parent_travel_app, "backend")):
        return parent_travel_app

    return cwd
