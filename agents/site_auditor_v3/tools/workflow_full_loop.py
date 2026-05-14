#!/usr/bin/env python3
"""Run FULL audit mode inside one GitHub Actions job.

FULL is an operator intent, not a separate runtime primitive:
- start fresh when no open session exists for the URL;
- resume the one open session when it exists;
- keep running bounded audit batches until the ledger reports no pending pages.

The underlying runtime still executes normal START/NEXT batches. This helper only
orchestrates those batches inside one workflow run and republishes resumable
session state after each successful batch so a failed FULL run can be recovered.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

REQUEST_FIXTURE = Path("agents/site_auditor_v3/tests/fixtures/link.request.json")
WRAPPER = Path("agents/site_auditor_v3/tests/run_and_validate.sh")
RUNS_ROOT = Path("agents/site_auditor_v3/runs")
SESSION_STATE_HELPER = Path("agents/site_auditor_v3/tools/workflow_session_state.py")


class FullLoopError(RuntimeError):
    pass


def fail(message: str) -> "NoReturn":
    print(f"FULL_LOOP_FAIL: {message}", file=sys.stderr)
    raise SystemExit(2)


def locate_latest_report() -> Path:
    reports = sorted(
        RUNS_ROOT.glob("*/RUN_REPORT.json"),
        key=lambda path: path.stat().st_mtime,
    )
    if not reports:
        raise FullLoopError("RUN_REPORT not found after wrapper execution")
    return reports[-1]


def write_request(target_url: str, audit_action: str, session_id: str | None) -> Path:
    if not REQUEST_FIXTURE.is_file():
        raise FullLoopError(f"request fixture missing: {REQUEST_FIXTURE}")

    data = json.loads(REQUEST_FIXTURE.read_text(encoding="utf-8"))
    data["target_url"] = target_url
    data["scan_profile"] = "STANDARD"
    data["batch_size"] = 250
    data["auto_audit"] = False
    data["run_mode"] = "FULL"
    data["audit_action"] = audit_action
    data["session_id"] = session_id or None

    fd, raw_path = tempfile.mkstemp(prefix="site_auditor_v3_full_", suffix=".json")
    os.close(fd)
    path = Path(raw_path)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return path


def resolve_bash_executable() -> str:
    """Resolve bash for both GitHub Linux runners and Windows operator diagnostics."""
    direct = shutil.which("bash")
    if direct:
        return direct

    candidates = []
    local_app_data = os.environ.get("LOCALAPPDATA")
    if local_app_data:
        candidates.append(Path(local_app_data) / "Programs" / "Git" / "bin" / "bash.exe")
    candidates.extend(
        [
            Path(r"C:\Program Files\Git\bin\bash.exe"),
            Path(r"C:\Program Files (x86)\Git\bin\bash.exe"),
        ]
    )

    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)

    fail("bash executable not found; install Git Bash or run FULL from a runner with bash available")
    return ""


def run_wrapper(request_path: Path) -> Path:
    env = os.environ.copy()
    env["REQUEST_PATH"] = str(request_path)
    bash_executable = resolve_bash_executable()
    wrapper_cmd = f"./{WRAPPER.as_posix()}"
    print(f"FULL_LOOP_REQUEST={request_path}")
    print(f"FULL_LOOP_BASH={bash_executable}")
    subprocess.run([bash_executable, "-lc", wrapper_cmd], check=True, env=env)
    return locate_latest_report()


def publish_state(target_url: str, report_path: Path, out_dir: str) -> None:
    command = [
        sys.executable,
        str(SESSION_STATE_HELPER),
        "publish",
        "--target-url",
        target_url,
        "--run-report",
        str(report_path),
        "--out-dir",
        out_dir,
    ]
    subprocess.run(command, check=True)


def read_report(report_path: Path) -> dict[str, Any]:
    return json.loads(report_path.read_text(encoding="utf-8"))


def run_full(args: argparse.Namespace) -> int:
    entry_action = args.entry_action.strip().upper()
    if entry_action not in {"START", "NEXT"}:
        fail(f"invalid FULL entry action: {entry_action!r}")

    current_action = entry_action
    current_session_id = args.session_id.strip() or None
    completed_batches = 0
    last_report: Path | None = None

    for iteration in range(1, args.max_batches + 1):
        print(f"FULL_LOOP_ITERATION={iteration}")
        print(f"FULL_LOOP_AUDIT_ACTION={current_action}")
        if current_session_id:
            print(f"FULL_LOOP_SESSION_ID={current_session_id}")

        request_path = write_request(args.target_url, current_action, current_session_id)
        try:
            last_report = run_wrapper(request_path)
        finally:
            request_path.unlink(missing_ok=True)

        publish_state(args.target_url, last_report, args.state_out_dir)
        report = read_report(last_report)
        audit_session = report.get("audit_session") or {}
        session_summary = report.get("session_summary") or {}

        current_session_id = str(audit_session.get("session_id") or current_session_id or "") or None
        next_action = str(audit_session.get("next_action") or "UNKNOWN")
        total_audited = int(audit_session.get("total_audited_count") or 0)
        total_pending = int(audit_session.get("total_pending_count") or 0)
        coverage = audit_session.get("coverage_percent")
        completed_batches = int(session_summary.get("batches_completed") or iteration)

        print(f"FULL_LOOP_REPORT={last_report}")
        print(f"FULL_LOOP_NEXT_ACTION={next_action}")
        print(f"FULL_LOOP_TOTAL_AUDITED={total_audited}")
        print(f"FULL_LOOP_TOTAL_PENDING={total_pending}")
        print(f"FULL_LOOP_COVERAGE={coverage}")

        if next_action == "NEXT_BATCH" and total_pending > 0:
            current_action = "NEXT"
            if not current_session_id:
                fail("runtime requested NEXT_BATCH but no session_id is available")
            continue

        if next_action == "FINAL_SUMMARY" and total_pending == 0:
            print("FULL_LOOP_STATUS=COMPLETED")
            print(f"FULL_LOOP_COMPLETED_BATCHES={completed_batches}")
            print(f"FULL_LOOP_FINAL_REPORT={last_report}")
            return 0

        if next_action == "STOP_NEEDS_REPAIR":
            fail("audit session stopped because runtime reported STOP_NEEDS_REPAIR")

        fail(f"unexpected audit-session state: next_action={next_action!r}, total_pending={total_pending}")

    fail(f"max batch limit reached before completion: {args.max_batches}")
    return 2


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Site Auditor V3 FULL workflow batch loop")
    parser.add_argument("--target-url", required=True)
    parser.add_argument("--entry-action", required=True, choices=["START", "NEXT"])
    parser.add_argument("--session-id", default="")
    parser.add_argument("--state-out-dir", required=True)
    parser.add_argument("--max-batches", type=int, default=1000)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return run_full(args)


if __name__ == "__main__":
    raise SystemExit(main())
