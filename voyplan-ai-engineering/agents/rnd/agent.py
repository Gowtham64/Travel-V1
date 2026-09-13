"""
Agent 2: R&D Agent (Architectural Research & Technical Planning)
1. Inspects real repository files and directories.
2. Identifies dependencies, database schemas, and API contracts.
3. Formulates real technical designs and acceptance criteria.
"""

import os
import sys
import json
from typing import Dict, Any, List, Optional

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from agents.researcher.agent import ResearchAgent
from state.database import StateDB

class RndAgent:
    def __init__(self, workspace_path: str = None, model_provider: str = None, model_name: str = None):
        self.researcher = ResearchAgent(workspace_path=workspace_path, model_provider=model_provider, model_name=model_name, role="rnd")
        self.db = StateDB()

    def research(self, issue_id: str, title: str, body: str) -> Dict[str, Any]:
        self.db.record_agent_state(
            agent_id="rnd",
            name="R&D Agent",
            role="Architectural Research & Planning",
            status="WORKING",
            current_task_id=issue_id,
            action=f"Researching issue #{issue_id}: {title}",
            result="IN_PROGRESS"
        )

        report = self.researcher.analyze_issue(issue_id, title, body)
        
        # Save output artifact
        output_path = os.path.join(self.researcher.workspace_path, "voyplan-ai-engineering", "research-report.json")
        try:
            with open(output_path, "w", encoding="utf-8") as f:
                json.dump(report, f, indent=2)
        except Exception:
            pass

        self.db.record_agent_state(
            agent_id="rnd",
            name="R&D Agent",
            role="Architectural Research & Planning",
            status="ONLINE",
            current_task_id=issue_id,
            action=f"Completed research for #{issue_id}",
            result=report.get("recommended_solution", "Plan generated.")
        )

        return report
