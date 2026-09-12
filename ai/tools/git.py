"""
Git Operations Tool
Provides branch management, isolated worktrees, diff analysis, and commit/PR creation.
"""

from typing import Dict, Any, List, Optional
from ai.tools.terminal import run_command

def get_status(cwd: str = ".") -> Dict[str, Any]:
    """Retrieves git status (modified, untracked, staged files)."""
    res = run_command("git status --porcelain", cwd=cwd)
    lines = res["stdout"].splitlines() if res["stdout"] else []
    modified = []
    untracked = []
    for line in lines:
        status_code = line[:2].strip()
        filename = line[3:].strip()
        if "?" in status_code:
            untracked.append(filename)
        else:
            modified.append(filename)
    return {
        "clean": len(lines) == 0,
        "modified": modified,
        "untracked": untracked,
        "raw": res["stdout"]
    }

def get_diff(cwd: str = ".", staged: bool = False) -> str:
    """Returns the unified git diff."""
    cmd = "git diff --staged" if staged else "git diff"
    res = run_command(cmd, cwd=cwd)
    return res["stdout"]

def create_work_branch(branch_name: str, base_branch: str = "main", cwd: str = ".") -> Dict[str, Any]:
    """Creates and switches to an isolated fix branch."""
    # Ensure base branch is fresh
    run_command(f"git fetch origin {base_branch}", cwd=cwd)
    res = run_command(f"git checkout -b {branch_name} origin/{base_branch}", cwd=cwd)
    if not res["success"]:
        # Fallback if local exists
        res = run_command(f"git checkout -b {branch_name} {base_branch}", cwd=cwd)
    return res

def commit_changes(message: str, files: Optional[List[str]] = None, cwd: str = ".") -> Dict[str, Any]:
    """Stages specific files or all changes and commits them with a standard message."""
    if files:
        for f in files:
            run_command(f"git add {f}", cwd=cwd)
    else:
        run_command("git add -A", cwd=cwd)

    res = run_command(f'git commit -m "{message}"', cwd=cwd)
    return res

def push_branch(branch_name: str, cwd: str = ".") -> Dict[str, Any]:
    """Pushes the isolated branch to the origin repository."""
    return run_command(f"git push -u origin {branch_name}", cwd=cwd)

def create_pull_request(title: str, body: str, head_branch: str, base_branch: str = "main", cwd: str = ".") -> Dict[str, Any]:
    """Creates a pull request using the GitHub CLI (gh) if available."""
    gh_check = run_command("which gh", cwd=cwd)
    if gh_check["success"]:
        escaped_title = title.replace('"', '\\"')
        escaped_body = body.replace('"', '\\"')
        cmd = f'gh pr create --title "{escaped_title}" --body "{escaped_body}" --base {base_branch} --head {head_branch}'
        return run_command(cmd, cwd=cwd)
    return {
        "success": False,
        "message": f"GitHub CLI 'gh' not available. Branch {head_branch} is ready for manual PR against {base_branch}."
    }

if __name__ == "__main__":
    st = get_status()
    print("Git status:", st)
