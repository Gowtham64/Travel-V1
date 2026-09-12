"""
Browser Automation Tool (Playwright)
Executes end-to-end browser journeys, captures screenshots, intercepts network errors,
and logs uncaught console exceptions for evidence-backed debugging.
"""

import os
import json
import time
from typing import Dict, Any, List, Optional
from ai.tools.terminal import run_command

def run_playwright_test(test_script_or_path: str, cwd: str = ".") -> Dict[str, Any]:
    """
    Executes a Playwright test script or runner and captures output.
    If Node/Playwright runner is present, executes test.
    """
    cmd = f"npx playwright test {test_script_or_path}"
    return run_command(cmd, cwd=cwd, timeout=90)

def generate_browser_journey_script(
    journey_name: str,
    base_url: str,
    actions: List[Dict[str, Any]],
    output_dir: str = "ai/evidence/browser"
) -> str:
    """
    Synthesizes a standalone Node Playwright script that performs a user journey,
    records all console errors and network failures, and saves screenshots.
    """
    os.makedirs(output_dir, exist_ok=True)
    script_path = os.path.join(output_dir, f"{journey_name}.js")

    actions_js = []
    for a in actions:
        atype = a.get("type")
        if atype == "goto":
            url = a.get("url", "/")
            actions_js.append(f"await page.goto('{base_url}{url}', {{ waitUntil: 'networkidle' }});")
        elif atype == "click":
            sel = a.get("selector")
            actions_js.append(f"await page.waitForSelector('{sel}', {{ timeout: 10000 }});")
            actions_js.append(f"await page.click('{sel}');")
        elif atype == "type":
            sel = a.get("selector")
            text = a.get("text", "")
            actions_js.append(f"await page.waitForSelector('{sel}', {{ timeout: 10000 }});")
            actions_js.append(f"await page.fill('{sel}', '{text}');")
        elif atype == "screenshot":
            name = a.get("name", "screenshot")
            actions_js.append(f"await page.screenshot({{ path: '{output_dir}/{journey_name}_{name}.png' }});")
        elif atype == "wait":
            ms = a.get("ms", 1000)
            actions_js.append(f"await page.waitForTimeout({ms});")

    script_content = f"""// Auto-generated Playwright Journey: {journey_name}
const {{ chromium }} = require('playwright');
const fs = require('fs');

(async () => {{
  const browser = await chromium.launch({{ headless: true }});
  const context = await browser.newContext();
  const page = await context.newPage();

  const consoleErrors = [];
  const networkErrors = [];

  page.on('console', msg => {{
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  }});

  page.on('requestfailed', request => {{
    networkErrors.push({{ url: request.url(), failure: request.failure()?.errorText }});
  }});

  try {{
    {chr(10).join('    ' + line for line in actions_js)}
    await page.screenshot({{ path: '{output_dir}/{journey_name}_final.png' }});
    console.log(JSON.stringify({{
      success: true,
      consoleErrors,
      networkErrors
    }}));
  }} catch (err) {{
    await page.screenshot({{ path: '{output_dir}/{journey_name}_error.png' }}).catch(() => {{}});
    console.log(JSON.stringify({{
      success: false,
      error: err.message,
      consoleErrors,
      networkErrors
    }}));
    process.exit(1);
  }} finally {{
    await browser.close();
  }}
}})();
"""
    with open(script_path, "w", encoding="utf-8") as f:
        f.write(script_content)

    return script_path

def execute_browser_journey(journey_name: str, base_url: str, actions: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Generates and executes a browser journey, returning structured evidence."""
    script_path = generate_browser_journey_script(journey_name, base_url, actions)
    res = run_command(f"node {script_path}")

    # Parse JSON output from the script
    evidence = {}
    for line in res["stdout"].splitlines():
        if line.strip().startswith("{") and "success" in line:
            try:
                evidence = json.loads(line)
                break
            except Exception:
                pass

    return {
        "journey": journey_name,
        "success": res["success"] and evidence.get("success", False),
        "evidence": evidence,
        "script_path": script_path,
        "stderr": res["stderr"]
    }

if __name__ == "__main__":
    print("Browser tool loaded.")
