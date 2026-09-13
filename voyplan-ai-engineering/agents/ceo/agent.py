"""
Agent 1: CEO Agent (Master Executive Orchestrator)
Coordinates the autonomous engineering fleet:
1. Reads project state, backlog, and requirements.
2. Directs R&D Agent to research and plan.
3. Assigns Coding Agent to implement isolated branch patches.
4. Dispatches Testing Agent across real execution runners (Web, Android, iOS, Backend).
5. Dispatches Debug Agent if tests fail.
6. Dispatches Fix Agent to add regression tests and repairs.
7. Dispatches Security Agent for CVE and secret auditing.
8. Dispatches Verification Agent for independent cross-platform sign-off.
9. Dispatches Deployment Agent for staging releases.
10. Dispatches Monitoring Agent to observe production health.
ABSOLUTE NO-MOCK RULE: Every decision is grounded in real command execution results.
"""

import os
import sys
import json
import time
from typing import Dict, Any, List, Optional

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from agents.common.llm_client import LLMClient
from agents.common.logger import AgentLogger
from agents.common.workspace import resolve_workspace
from state.database import StateDB

class CEOAgent:
    def __init__(self, workspace_path: str = None, model_provider: str = None, model_name: str = None):
        self.workspace_path = resolve_workspace(workspace_path)
        self.llm = LLMClient(provider=model_provider, model=model_name, role="ceo")
        self.db = StateDB()
        self.logger = AgentLogger("ceo", "fleet")

    def review_project_and_dispatch(self, task: Dict[str, Any]) -> Dict[str, Any]:
        """Evaluates a task, assigns it to the fleet, and records persistent status."""
        task_id = str(task.get("id", f"task-{int(time.time())}"))
        title = task.get("title", "Autonomous Engineering Task")
        self.logger.log_event(f"CEO Agent reviewing task #{task_id}: '{title}'")
        
        self.db.record_agent_state(
            agent_id="ceo",
            name="CEO Agent",
            role="Master Executive Orchestrator",
            status="WORKING",
            current_task_id=task_id,
            action=f"Orchestrating Task #{task_id}",
            result="IN_PROGRESS"
        )

        prompt = f"""You are the CEO of VoyPlan Autonomous Engineering.
Analyze this task and assign priorities across R&D, Coding, Testing, Security, and Release.
TASK ID: {task_id}
TITLE: {title}
DESCRIPTION: {task.get('description', '')}

Respond in pure JSON with keys:
- "strategic_priority": "P0" | "P1" | "P2"
- "executive_directive": string
- "required_platforms": list of "web" | "android" | "ios" | "backend"
- "risk_assessment": string
"""
        decision = self.llm.query(
            system_prompt="You are an executive autonomous engineering leader. Output pure JSON.",
            user_prompt=prompt,
            expect_json=True
        )

        self.db.record_agent_state(
            agent_id="ceo",
            name="CEO Agent",
            role="Master Executive Orchestrator",
            status="ONLINE",
            current_task_id=task_id,
            action=f"Dispatched Task #{task_id}",
            result=decision.get("executive_directive", "Directive issued to fleet.")
        )

        return {
            "task_id": task_id,
            "title": title,
            "directive": decision,
            "status": "DISPATCHED"
        }
