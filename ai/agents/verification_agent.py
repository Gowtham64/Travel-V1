"""
Verification Agent
Enforces the complete multi-tiered verification loop:
Targeted Test -> Regression Suite -> Full Unit/Integration -> Quality Gate.
"""

from typing import Dict, Any, List
from ai.tools.tests import run_backend_tests, run_mobile_tests, run_all_verification

def verify_fix(component: str = "backend", targeted_test: str = None) -> Dict[str, Any]:
    """
    Runs the verification gate:
    1. Targeted test must pass.
    2. Component test suite must pass.
    3. Global regression suite must pass.
    """
    print(f"[VERIFICATION AGENT] Beginning verification gate for {component}...")

    # Step 1: Targeted test verification
    if targeted_test:
        print(f"[VERIFICATION AGENT] Step 1: Running targeted test: {targeted_test}")
        if component == "backend":
            t_res = run_backend_tests(test_path=targeted_test)
        else:
            t_res = run_mobile_tests(test_path=targeted_test)

        if not t_res["success"]:
            return {
                "verified": False,
                "step": "targeted_test",
                "message": "Targeted test failed to verify the fix.",
                "details": t_res
            }

    # Step 2: Component-wide verification
    print(f"[VERIFICATION AGENT] Step 2: Running component suite for {component}...")
    if component == "backend":
        comp_res = run_backend_tests()
    else:
        comp_res = run_mobile_tests()

    if not comp_res["success"]:
        return {
            "verified": False,
            "step": "component_suite",
            "message": f"{component} test suite regression detected.",
            "details": comp_res
        }

    # Step 3: Full cross-tier regression check
    print("[VERIFICATION AGENT] Step 3: Running cross-tier regression check...")
    global_res = run_all_verification()

    return {
        "verified": global_res["all_passed"],
        "step": "complete",
        "message": "All verification gates passed cleanly." if global_res["all_passed"] else "Cross-tier regression detected.",
        "details": global_res
    }

if __name__ == "__main__":
    v = verify_fix("backend", "src/tests/fuelExpenseFlow.test.js")
    print("Verification result:", v["verified"])
