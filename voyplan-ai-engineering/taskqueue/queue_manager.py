"""
VoyPlan 24/7 Autonomous AI Engineering System - Task Queue & Priority Manager

Implements:
1. Priority Queue: P0 (Outage) > P1 (Critical Bug) > P2 (Important Feature) > P3 (Normal) > P4 (Improvement) > P5 (Tech Debt)
2. State Lifecycle: NEW → RESEARCHING → READY_FOR_DEV → DEVELOPING → TESTING → QA → STAGING → READY_FOR_RELEASE → RELEASED
3. Concurrency & Resource Locking: Prevents conflicting edits to the same feature/files.
4. Continuous Background Scanners: Monitors GitHub issues, TODOs, test health, and error logs.
"""

import os
import json
import time
import threading
from typing import Dict, Any, List, Optional

PRIORITY_WEIGHTS = {
    "P0": 0,  # Production outage
    "P1": 1,  # Critical bug
    "P2": 2,  # Important feature
    "P3": 3,  # Normal feature
    "P4": 4,  # Improvement
    "P5": 5,  # Technical debt
}

class QueueManager:
    def __init__(self, queue_file_path: str = None):
        if not queue_file_path:
            base_dir = os.path.dirname(os.path.abspath(__file__))
            queue_file_path = os.path.join(base_dir, "task_queue.json")
        self.queue_file = queue_file_path
        self.lock = threading.Lock()
        self.resource_locks: Dict[str, str] = {}  # file_path -> task_id
        self._init_queue()

    def _init_queue(self):
        if not os.path.exists(self.queue_file):
            initial_data = {
                "tasks": [
                    {
                        "id": "123",
                        "title": "Fix AI Planner Random Locations",
                        "description": "Destination: Tirumala. The planner must not add unrelated locations.",
                        "priority": "P1",
                        "status": "RELEASED",
                        "type": "bug",
                        "locked_resources": ["backend/src/services/itineraryEngine.js", "backend/src/services/geminiValidatorService.js"],
                        "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                        "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                        "retry_count": 0
                    },
                    {
                        "id": "124",
                        "title": "Trip Itinerary Item Editing & Drag-and-Drop Reordering",
                        "description": "Users should be able to edit, reorder, and remove itinerary stops on active trips.",
                        "priority": "P2",
                        "status": "NEW",
                        "type": "feature",
                        "locked_resources": ["mobile/lib/screens/itinerary_screen.dart", "backend/src/routes/trip.js"],
                        "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                        "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                        "retry_count": 0
                    },
                    {
                        "id": "125",
                        "title": "Automated Offline OSRM Response Caching",
                        "description": "Cache repeated routing calls locally to accelerate integration tests and prevent network rate-limiting.",
                        "priority": "P4",
                        "status": "NEW",
                        "type": "improvement",
                        "locked_resources": ["backend/src/services/routingService.js"],
                        "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                        "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                        "retry_count": 0
                    }
                ],
                "stats": {
                    "completed_today": 1,
                    "failed_today": 0,
                    "prs_created": 1,
                    "prs_merged": 1,
                    "tests_executed": 24,
                    "qa_failures": 0,
                    "deployments": 1,
                    "rollbacks": 0
                }
            }
            with open(self.queue_file, "w", encoding="utf-8") as f:
                json.dump(initial_data, f, indent=2)

    def get_all(self) -> Dict[str, Any]:
        with self.lock:
            try:
                with open(self.queue_file, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                return {"tasks": [], "stats": {}}

    def save_all(self, data: Dict[str, Any]):
        with self.lock:
            with open(self.queue_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)

    def add_task(self, title: str, description: str, priority: str = "P3", task_type: str = "feature", locked_resources: List[str] = None) -> Dict[str, Any]:
        data = self.get_all()
        task_id = str(len(data.get("tasks", [])) + 124)
        task = {
            "id": task_id,
            "title": title,
            "description": description,
            "priority": priority if priority in PRIORITY_WEIGHTS else "P3",
            "status": "NEW",
            "type": task_type,
            "locked_resources": locked_resources or [],
            "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "retry_count": 0
        }
        data["tasks"].append(task)
        self.save_all(data)
        return task

    def get_next_task(self) -> Optional[Dict[str, Any]]:
        """Pulls next executable task ordered by priority and resource availability."""
        data = self.get_all()
        actionable_tasks = [
            t for t in data.get("tasks", [])
            if t["status"] in ["NEW", "READY_FOR_DEV", "READY_FOR_TEST", "READY_FOR_QA"]
        ]
        if not actionable_tasks:
            return None

        # Sort by priority weight
        actionable_tasks.sort(key=lambda t: (PRIORITY_WEIGHTS.get(t["priority"], 99), t["created_at"]))

        # Check resource lock conflicts
        for task in actionable_tasks:
            conflicts = [res for res in task.get("locked_resources", []) if res in self.resource_locks and self.resource_locks[res] != task["id"]]
            if not conflicts:
                return task

        return None

    def acquire_locks(self, task_id: str, resources: List[str]) -> bool:
        with self.lock:
            for res in resources:
                if res in self.resource_locks and self.resource_locks[res] != task_id:
                    return False
            for res in resources:
                self.resource_locks[res] = task_id
            return True

    def release_locks(self, task_id: str):
        with self.lock:
            to_remove = [res for res, t_id in self.resource_locks.items() if t_id == task_id]
            for res in to_remove:
                del self.resource_locks[res]

    def update_task_status(self, task_id: str, new_status: str, error_reason: str = None):
        data = self.get_all()
        for t in data.get("tasks", []):
            if t["id"] == str(task_id):
                t["status"] = new_status
                t["updated_at"] = time.strftime("%Y-%m-%d %H:%M:%S")
                if error_reason:
                    t["last_error"] = error_reason
                    t["retry_count"] = t.get("retry_count", 0) + 1
                break
        self.save_all(data)

    def increment_stat(self, stat_name: str, delta: int = 1):
        data = self.get_all()
        stats = data.get("stats", {})
        stats[stat_name] = stats.get(stat_name, 0) + delta
        data["stats"] = stats
        self.save_all(data)
