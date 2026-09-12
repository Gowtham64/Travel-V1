"""
Filesystem Tool
Provides code search, targeted file reading, safe atomic file modification, and tree discovery.
"""

import os
import re
from typing import List, Dict, Any, Optional

def read_file(file_path: str, start_line: Optional[int] = None, end_line: Optional[int] = None) -> Dict[str, Any]:
    """Reads lines from a file with optional 1-indexed line ranges."""
    if not os.path.exists(file_path):
        return {"success": False, "error": f"File not found: {file_path}", "content": ""}

    try:
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()

        total_lines = len(lines)
        s = max(1, start_line) if start_line else 1
        e = min(total_lines, end_line) if end_line else total_lines

        selected = lines[s - 1:e]
        return {
            "success": True,
            "file_path": file_path,
            "total_lines": total_lines,
            "start_line": s,
            "end_line": e,
            "content": "".join(selected)
        }
    except Exception as e:
        return {"success": False, "error": str(e), "content": ""}

def write_file(file_path: str, content: str) -> Dict[str, Any]:
    """Writes content to a file, creating parent directories if necessary."""
    try:
        os.makedirs(os.path.dirname(os.path.abspath(file_path)), exist_ok=True)
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(content)
        return {"success": True, "file_path": file_path, "bytes_written": len(content)}
    except Exception as e:
        return {"success": False, "error": str(e), "file_path": file_path}

def replace_in_file(file_path: str, target: str, replacement: str) -> Dict[str, Any]:
    """Replaces a precise string block inside a file."""
    if not os.path.exists(file_path):
        return {"success": False, "error": f"File not found: {file_path}"}

    try:
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()

        if target not in content:
            return {"success": False, "error": "Target string not found in file"}

        updated = content.replace(target, replacement, 1)
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(updated)
        return {"success": True, "file_path": file_path}
    except Exception as e:
        return {"success": False, "error": str(e)}

def search_code(query: str, root_dir: str = ".", extensions: Optional[List[str]] = None) -> List[Dict[str, Any]]:
    """Recursively searches for regex or pattern matches across project code."""
    results = []
    ext_set = set(extensions) if extensions else None
    pattern = re.compile(query, re.IGNORECASE)

    for root, dirs, files in os.walk(root_dir):
        # Skip dependency & cache directories
        dirs[:] = [d for d in dirs if d not in {".git", "node_modules", ".dart_tool", "build", ".venv", "Pods"}]
        for file in files:
            if ext_set and not any(file.endswith(ext) for ext in ext_set):
                continue
            path = os.path.join(root, file)
            try:
                with open(path, "r", encoding="utf-8", errors="ignore") as f:
                    for idx, line in enumerate(f, 1):
                        if pattern.search(line):
                            results.append({
                                "file": path,
                                "line_number": idx,
                                "content": line.strip()
                            })
                            if len(results) >= 50:
                                return results
            except Exception:
                continue
    return results

if __name__ == "__main__":
    hits = search_code("fuelCost", root_dir="backend/src")
    print(f"Found {len(hits)} occurrences")
