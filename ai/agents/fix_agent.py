"""
Fix Agent
Applies surgical, minimal code edits to resolve the verified root cause,
and ensures syntax/compilation validity before passing to verification.
"""

from typing import Dict, Any, List
from ai.tools.filesystem import replace_in_file, read_file
from ai.tools.terminal import run_command

def apply_patch(file_path: str, target_block: str, replacement_block: str) -> Dict[str, Any]:
    """Applies a targeted replacement block in the code."""
    res = replace_in_file(file_path, target_block, replacement_block)
    if not res["success"]:
        return res

    # Syntax & compilation validation
    if file_path.endswith(".js"):
        check = run_command(f"node -c {file_path}")
        if not check["success"]:
            # Rollback if syntax is broken
            replace_in_file(file_path, replacement_block, target_block)
            return {
                "success": False,
                "error": f"Node syntax validation failed, patch rolled back: {check['stderr']}"
            }
    elif file_path.endswith(".dart"):
        check = run_command("flutter analyze", cwd="mobile")
        if not check["success"]:
            # Check if errors occurred in this specific file
            if file_path in check["stdout"]:
                replace_in_file(file_path, replacement_block, target_block)
                return {
                    "success": False,
                    "error": f"Flutter analyzer detected error in modified file, patch rolled back: {check['stdout']}"
                }

    return {"success": True, "file_path": file_path}

if __name__ == "__main__":
    print("Fix Agent initialized.")
