"""
Agent 3: Coding Agent (Autonomous Code Implementation)
1. Creates isolated Git feature branch (never commits directly to main).
2. Reads target source files.
3. Generates real source modifications via LLM.
4. Performs pre-flight syntax verification.
5. Commits real code to Git branch.
"""

import os
import sys
import json
from typing import Dict, Any, List, Optional

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from agents.developer.agent import DeveloperAgent
from state.database import StateDB

class CodingAgent:
    def __init__(self, workspace_path: str = None, model_provider: str = None, model_name: str = None):
        self.dev = DeveloperAgent(workspace_path=workspace_path, model_provider=model_provider, model_name=model_name, role="coding")
        self.db = StateDB()

    def implement_feature(self, research_report_path: str = None, feedback: Dict[str, Any] = None) -> Dict[str, Any]:
        task_id = "unknown"
        if research_report_path and os.path.exists(research_report_path):
            try:
                with open(research_report_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    task_id = str(data.get("issue") or data.get("task") or "1")
            except Exception:
                pass

        self.db.record_agent_state(
            agent_id="coding",
            name="Coding Agent",
            role="Autonomous Code Implementation",
            status="WORKING",
            current_task_id=task_id,
            action=f"Writing code changes for Task #{task_id}",
            result="IN_PROGRESS"
        )

        res = self.dev.develop(research_report_path=research_report_path, feedback=feedback)

        # Record persistent status
        status = "ONLINE" if res.get("status") == "PASS" else "FAILED"
        action = f"Committed {len(res.get('files_changed', []))} files ({res.get('commit')})" if res.get("status") == "PASS" else "Syntax check failed"
        
        self.db.record_agent_state(
            agent_id="coding",
            name="Coding Agent",
            role="Autonomous Code Implementation",
            status=status,
            current_task_id=task_id,
            action=action,
            result=json.dumps(res.get("files_changed", []))
        )

        return res
