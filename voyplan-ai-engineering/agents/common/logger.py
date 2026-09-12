"""
Structured Agent Audit Logger with automatic secret sanitization.
Creates audit trails under logs/<YYYY-MM-DD>/issue-<num>/<agent>.log.
"""

import os
import re
import json
import datetime
from typing import Dict, Any, List, Optional

SECRET_PATTERNS = [
    re.compile(r"(?:api[_-]?key|token|password|secret|authorization)[:=]\s*['\"]?([a-zA-Z0-9_\-\.]{8,})['\"]?", re.IGNORECASE),
    re.compile(r"pk\.[a-zA-Z0-9_\-\.]{20,}", re.IGNORECASE),
    re.compile(r"sk-[a-zA-Z0-9_\-\.]{20,}", re.IGNORECASE),
    re.compile(r"ghp_[a-zA-Z0-9]{20,}", re.IGNORECASE),
    re.compile(r"AIza[0-9A-Za-z\-_]{35}", re.IGNORECASE),
]

def sanitize(text: str) -> str:
    if not isinstance(text, str):
        text = str(text)
    sanitized = text
    for pattern in SECRET_PATTERNS:
        sanitized = pattern.sub(r"***REDACTED***", sanitized)
    return sanitized

class AgentLogger:
    def __init__(self, agent_name: str, issue_id: str, base_log_dir: str = "logs"):
        self.agent_name = agent_name
        self.issue_id = str(issue_id).replace("#", "")
        self.date_str = datetime.datetime.now().strftime("%Y-%m-%d")
        
        self.log_dir = os.path.join(base_log_dir, self.date_str, f"issue-{self.issue_id}")
        os.makedirs(self.log_dir, exist_ok=True)
        self.log_path = os.path.join(self.log_dir, f"{self.agent_name}.log")
        
        self.audit_record: Dict[str, Any] = {
            "agent": self.agent_name,
            "issue_id": self.issue_id,
            "start_time": datetime.datetime.now().isoformat(),
            "end_time": None,
            "model": None,
            "files_changed": [],
            "commands_executed": [],
            "tests": [],
            "failures": [],
            "final_result": None,
        }

    def log_event(self, message: str, level: str = "INFO"):
        safe_msg = sanitize(message)
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        line = f"[{timestamp}] [{level.upper()}] [{self.agent_name}] {safe_msg}\n"
        with open(self.log_path, "a", encoding="utf-8") as f:
            f.write(line)
        print(line.strip())

    def info(self, message: str):
        self.log_event(message, level="INFO")

    def warn(self, message: str):
        self.log_event(message, level="WARN")

    def error(self, message: str):
        self.log_event(message, level="ERROR")

    def record_command(self, command: str, exit_code: int, output_snippet: str = ""):
        self.audit_record["commands_executed"].append({
            "command": sanitize(command),
            "exit_code": exit_code,
            "output_snippet": sanitize(output_snippet[:300])
        })
        self.log_event(f"Executed: {command} (exit: {exit_code})")

    def record_files_changed(self, files: List[str]):
        self.audit_record["files_changed"] = list(set(self.audit_record["files_changed"] + files))

    def complete(self, result: str, model_used: Optional[str] = None):
        self.audit_record["end_time"] = datetime.datetime.now().isoformat()
        self.audit_record["final_result"] = result
        self.audit_record["model"] = model_used
        
        summary_path = os.path.join(self.log_dir, f"{self.agent_name}-summary.json")
        with open(summary_path, "w", encoding="utf-8") as f:
            json.dump(self.audit_record, f, indent=2)
            
        self.log_event(f"Task completed with result: {result}")
