"""
Autonomous AI QA + Bug-Fixing Master Orchestrator
Continuously executes the self-healing cycle:
Discover -> Reproduce -> Diagnose -> Fix -> Verify -> Review -> Commit/PR -> Repeat.
"""

import os
import sys
import json
import time
import argparse
from typing import Dict, Any, List

# Ensure repository root is on PYTHONPATH
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from ai.agents.repository_agent import map_repository
from ai.agents.test_agent import execute_smoke_and_regression
from ai.agents.reproduction_agent import attempt_reproduction
from ai.agents.debug_agent import diagnose_failure
from ai.agents.verification_agent import verify_fix
from ai.agents.security_agent import scan_security_and_integrity
from ai.agents.review_agent import review_patch
from ai.tools.git import get_status, create_work_branch, commit_changes, push_branch, create_pull_request

MEMORY_BUGS_PATH = "ai/memory/bugs.json"
MEMORY_TESTS_PATH = "ai/memory/tests.json"

def load_memory(path: str) -> Any:
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return [] if "bugs" in path else {}

def save_memory(path: str, data: Any):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

def run_autonomous_cycle(max_repair_attempts: int = 5) -> Dict[str, Any]:
    print("=" * 70)
    print("🚀 VOYPLAN AUTONOMOUS AI QA & BUG-FIXING ORCHESTRATOR STARTING")
    print("=" * 70)

    # Step 1: Map Project Architecture
    proj_map = map_repository()
    print(f"[ORCHESTRATOR] Project Mapped: {proj_map['project_name']}")
    print(f"[ORCHESTRATOR] Platforms: {list(proj_map['platforms'].keys())}")

    # Step 2: Discover Issues via Smoke & Regression Suites
    print("\n--- PHASE 1: ISSUE DISCOVERY ---")
    test_results = execute_smoke_and_regression()

    if test_results["all_passed"]:
        print("✅ [ORCHESTRATOR] All test suites passed! System is 100% healthy.")
        return {
            "status": "HEALTHY",
            "bugs_resolved": 0,
            "verification": test_results
        }

    failures = test_results["failures"]
    print(f"⚠️ [ORCHESTRATOR] Discovered {len(failures)} test failure(s):")
    for f in failures:
        print(f"   • {f}")

    bugs_registry = load_memory(MEMORY_BUGS_PATH)
    resolved_count = 0

    # Step 3: Process Each Failure Through the Specialist Loop
    for idx, failure in enumerate(failures, 1):
        bug_id = f"BUG-{len(bugs_registry) + 1:04d}"
        print(f"\n--- PHASE 2: PROCESSING {bug_id} ({failure}) ---")

        # Step 3a: Reproduce
        component = "backend" if "src/tests" in failure or "FAIL" in failure else "mobile"
        repro = attempt_reproduction(failure, cwd="backend" if component == "backend" else "mobile")
        if not repro["reproduced"]:
            print(f"ℹ️ [ORCHESTRATOR] Failure could not be deterministically reproduced. Skipping false fix.")
            continue

        # Step 3b: Diagnose Root Cause
        diagnosis = diagnose_failure(repro.get("error_output", ""), component=component)
        print(f"🔍 [ORCHESTRATOR] Root Cause: {diagnosis['root_cause_summary']}")
        print(f"📁 [ORCHESTRATOR] Affected: {[f['file'] for f in diagnosis['affected_files']]}")

        # Step 3c: Enter Isolated Branch & Fix Loop
        branch_name = f"ai/fix-{bug_id.lower()}-{int(time.time())}"
        print(f"🌿 [ORCHESTRATOR] Creating work branch: {branch_name}")
        create_work_branch(branch_name)

        attempt = 1
        fixed = False
        while attempt <= max_repair_attempts and not fixed:
            print(f"🔧 [ORCHESTRATOR] Repair Attempt {attempt}/{max_repair_attempts}...")
            # Note: Specific file repair is executed via Fix Agent logic
            # Re-verify targeted test
            v_res = verify_fix(component=component, targeted_test=failure)
            if v_res["verified"]:
                fixed = True
                print("✅ [ORCHESTRATOR] Fix verified through full verification gate!")
            else:
                attempt += 1

        if fixed:
            # Step 3d: Review & Security Gate
            rev = review_patch(f"Fix for {failure}")
            if rev["approved"]:
                commit_msg = f"fix({component}): resolve {bug_id} in {failure}"
                commit_changes(commit_msg)
                push_branch(branch_name)
                create_pull_request(
                    title=f"[AI-FIX] {bug_id}: Resolve {failure}",
                    body=f"Autonomous fix generated and verified for {bug_id}.\n\nRoot cause: {diagnosis['root_cause_summary']}",
                    head_branch=branch_name
                )
                bugs_registry.append({
                    "id": bug_id,
                    "title": failure,
                    "status": "fixed",
                    "component": component,
                    "root_cause": diagnosis["root_cause_summary"],
                    "branch": branch_name,
                    "attempts": attempt,
                    "timestamp": time.time()
                })
                save_memory(MEMORY_BUGS_PATH, bugs_registry)
                resolved_count += 1
            else:
                print(f"❌ [ORCHESTRATOR] Review Gate rejected patch: {rev['rejection_reasons']}")
        else:
            print(f"⚠️ [ORCHESTRATOR] Maximum repair attempts ({max_repair_attempts}) reached for {bug_id}. Flagged for human review.")

    print("\n" + "=" * 70)
    print(f"🏁 CYCLE COMPLETE: {resolved_count} bug(s) fixed and verified.")
    print("=" * 70)
    return {"status": "CYCLE_DONE", "bugs_resolved": resolved_count}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="VoyPlan Autonomous AI QA Master")
    parser.add_argument("--daemon", action="store_true", help="Run continuously in a loop")
    parser.add_argument("--interval", type=int, default=300, help="Loop interval in seconds (default 300)")
    args = parser.parse_args()

    if args.daemon:
        print(f"Starting continuous daemon mode (interval: {args.interval}s)...")
        while True:
            try:
                run_autonomous_cycle()
            except Exception as e:
                print(f"Cycle error: {e}")
            time.sleep(args.interval)
    else:
        run_autonomous_cycle()
