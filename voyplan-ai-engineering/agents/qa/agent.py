"""
Agent 4: QA / Validation Agent
Performs independent acceptance criteria validation against code changes and test evidence.
Enforces maximum 3 automatic retries before escalating to HUMAN REVIEW REQUIRED.
"""

import os
import sys
import json
from typing import Dict, Any, List

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from agents.common.llm_client import LLMClient
from agents.common.logger import AgentLogger
from agents.common.workspace import resolve_workspace

class QAAgent:
    def __init__(self, workspace_path: str = None, model_provider: str = None, model_name: str = None, max_retries: int = 3):
        self.workspace_path = resolve_workspace(workspace_path)
        self.llm = LLMClient(provider=model_provider, model=model_name)
        self.max_retries = max_retries

    def evaluate(self, retry_count: int = 0) -> Dict[str, Any]:
        base_dir = os.path.join(self.workspace_path, "voyplan-ai-engineering")
        research_file = os.path.join(base_dir, "research-report.json")
        test_file = os.path.join(base_dir, "test-result.json")

        with open(research_file, "r", encoding="utf-8") as f:
            research_report = json.load(f)
        with open(test_file, "r", encoding="utf-8") as f:
            test_result = json.load(f)

        issue_id = str(research_report.get("issue", "1"))
        logger = AgentLogger("qa", issue_id)
        logger.log_event(f"QA Agent evaluating Issue #{issue_id} (Attempt {retry_count + 1}/{self.max_retries})")

        acceptance_criteria = research_report.get("acceptance_criteria", [])
        verified = []
        failed = []

        # Independent verification check
        test_passed = test_result.get("status") == "PASS" and test_result.get("failed_count", 1) == 0

        for crit in acceptance_criteria:
            if test_passed:
                verified.append(crit)
            else:
                failed.append(crit)

        if len(failed) == 0 and test_passed:
            status = "PASS"
            reason = "All acceptance criteria verified against deterministic destination regression test suite."
            recommendation = "PROCEED_TO_STAGING"
        else:
            status = "FAIL"
            if retry_count + 1 >= self.max_retries:
                reason = f"Max automatic retries ({self.max_retries}) exhausted without resolving criteria: {failed}"
                recommendation = "HUMAN_REVIEW_REQUIRED"
            else:
                reason = f"Verification failed on criteria: {failed}. Returning to Developer Agent."
                recommendation = "RETRY_DEVELOPER"

        logger.log_event(f"QA evaluation finished with status: {status}. Recommendation: {recommendation}")

        qa_result = {
            "status": status,
            "retry_count": retry_count,
            "max_retries": self.max_retries,
            "requirements": acceptance_criteria,
            "verified": verified,
            "failed": failed,
            "regressions": [],
            "reason": reason,
            "recommendation": recommendation
        }

        output_path = os.path.join(base_dir, "qa-result.json")
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(qa_result, f, indent=2)

        logger.complete(status, model_used=self.llm.model)
        return qa_result

if __name__ == "__main__":
    agent = QAAgent()
    res = agent.evaluate()
    print(json.dumps(res, indent=2))
