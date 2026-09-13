"""
Persistent SQLite State Storage for VoyPlan Autonomous AI Engineering System.
Tracks tasks, agent executions, test runs, reproduced bugs, artifacts, and runner node heartbeats.
"""

import os
import sqlite3
import json
import time
from typing import Dict, Any, List, Optional

STATE_DIR = os.path.abspath(os.path.dirname(__file__))
DB_PATH = os.path.join(STATE_DIR, "voyplan_autonomous_system.db")

def get_db_connection():
    os.makedirs(STATE_DIR, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # 1. Tasks table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        priority TEXT DEFAULT 'P2',
        status TEXT DEFAULT 'PENDING',
        assigned_agent TEXT,
        created_at REAL,
        updated_at REAL,
        metadata TEXT
    )
    """)
    
    # 2. Agent Execution States
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS agent_states (
        agent_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        status TEXT DEFAULT 'ONLINE', -- ONLINE, WORKING, WAITING, BLOCKED, FAILED
        current_task_id TEXT,
        last_heartbeat REAL,
        last_action TEXT,
        last_result TEXT
    )
    """)
    
    # 3. Runner Nodes (Linux, Android, macOS)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS runner_nodes (
        runner_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        platform TEXT NOT NULL, -- linux, android, macos, web
        status TEXT DEFAULT 'OFFLINE', -- ONLINE, BUSY, AVAILABLE, OFFLINE, BLOCKED
        capabilities TEXT,
        available_devices TEXT,
        current_job TEXT,
        last_ping REAL,
        system_stats TEXT
    )
    """)
    
    # 4. Bugs with Real Reproduction Evidence
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS bugs (
        id TEXT PRIMARY KEY,
        task_id TEXT,
        title TEXT NOT NULL,
        platform TEXT NOT NULL,
        feature TEXT,
        expected TEXT,
        actual TEXT,
        stdout TEXT,
        stderr TEXT,
        exit_code INTEGER,
        reproduced INTEGER DEFAULT 0,
        screenshot_path TEXT,
        video_path TEXT,
        log_path TEXT,
        status TEXT DEFAULT 'OPEN', -- OPEN, REPRODUCED, IN_DEBUG, FIXED, VERIFIED
        created_at REAL
    )
    """)
    
    # 5. Test Runs
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS test_runs (
        id TEXT PRIMARY KEY,
        task_id TEXT,
        runner_id TEXT,
        platform TEXT NOT NULL,
        test_type TEXT NOT NULL,
        command TEXT,
        exit_code INTEGER,
        stdout TEXT,
        stderr TEXT,
        duration REAL,
        result TEXT NOT NULL, -- PASS, FAIL, BLOCKED
        evidence_json TEXT,
        created_at REAL
    )
    """)
    
    # 6. Artifacts
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS artifacts (
        id TEXT PRIMARY KEY,
        task_id TEXT,
        artifact_type TEXT NOT NULL,
        file_path TEXT NOT NULL,
        file_size INTEGER,
        platform TEXT,
        created_at REAL,
        metadata TEXT
    )
    """)
    
    conn.commit()
    conn.close()

class StateDB:
    def __init__(self):
        init_db()

    def record_agent_state(self, agent_id: str, name: str, role: str, status: str, 
                           current_task_id: str = None, action: str = None, result: str = None):
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
        INSERT INTO agent_states (agent_id, name, role, status, current_task_id, last_heartbeat, last_action, last_result)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(agent_id) DO UPDATE SET
            status=excluded.status,
            current_task_id=excluded.current_task_id,
            last_heartbeat=excluded.last_heartbeat,
            last_action=excluded.last_action,
            last_result=excluded.last_result
        """, (agent_id, name, role, status, current_task_id, time.time(), action, result))
        conn.commit()
        conn.close()

    def record_runner_node(self, runner_id: str, name: str, platform: str, status: str, 
                           capabilities: List[str], available_devices: List[str], current_job: str = None, stats: Dict[str, Any] = None):
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
        INSERT INTO runner_nodes (runner_id, name, platform, status, capabilities, available_devices, current_job, last_ping, system_stats)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(runner_id) DO UPDATE SET
            status=excluded.status,
            capabilities=excluded.capabilities,
            available_devices=excluded.available_devices,
            current_job=excluded.current_job,
            last_ping=excluded.last_ping,
            system_stats=excluded.system_stats
        """, (
            runner_id, name, platform, status, 
            json.dumps(capabilities), json.dumps(available_devices), 
            current_job, time.time(), json.dumps(stats or {})
        ))
        conn.commit()
        conn.close()

    def record_test_run(self, task_id: str, runner_id: str, platform: str, test_type: str, 
                        command: str, exit_code: int, stdout: str, stderr: str, duration: float, result: str, evidence: Dict[str, Any] = None) -> str:
        run_id = f"test-{int(time.time()*1000)}"
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
        INSERT INTO test_runs (id, task_id, runner_id, platform, test_type, command, exit_code, stdout, stderr, duration, result, evidence_json, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            run_id, task_id, runner_id, platform, test_type,
            command, exit_code, stdout, stderr, duration, result,
            json.dumps(evidence or {}), time.time()
        ))
        conn.commit()
        conn.close()
        return run_id

    def record_bug(self, bug_id: str, task_id: str, title: str, platform: str, feature: str, 
                   expected: str, actual: str, stdout: str, stderr: str, exit_code: int, 
                   screenshot: str = None, video: str = None, log_file: str = None):
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
        INSERT INTO bugs (id, task_id, title, platform, feature, expected, actual, stdout, stderr, exit_code, reproduced, screenshot_path, video_path, log_path, status, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, 'OPEN', ?)
        ON CONFLICT(id) DO UPDATE SET
            expected=excluded.expected,
            actual=excluded.actual,
            stdout=excluded.stdout,
            stderr=excluded.stderr,
            exit_code=excluded.exit_code,
            screenshot_path=excluded.screenshot_path,
            video_path=excluded.video_path,
            log_path=excluded.log_path,
            status=excluded.status
        """, (
            bug_id, task_id, title, platform, feature, expected, actual,
            stdout, stderr, exit_code, screenshot, video, log_file, time.time()
        ))
        conn.commit()
        conn.close()

    def get_fleet_summary(self) -> Dict[str, Any]:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("SELECT * FROM agent_states")
        agents = [dict(row) for row in cursor.fetchall()]
        
        cursor.execute("SELECT * FROM runner_nodes")
        runners = [dict(row) for row in cursor.fetchall()]
        
        cursor.execute("SELECT * FROM bugs ORDER BY created_at DESC LIMIT 10")
        bugs = [dict(row) for row in cursor.fetchall()]
        
        cursor.execute("SELECT * FROM test_runs ORDER BY created_at DESC LIMIT 10")
        test_runs = [dict(row) for row in cursor.fetchall()]
        
        conn.close()
        return {
            "agents": agents,
            "runners": runners,
            "recent_bugs": bugs,
            "recent_tests": test_runs
        }

# Auto-initialize database on import
init_db()
