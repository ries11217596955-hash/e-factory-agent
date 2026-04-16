#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
VIDEO_ORCHESTRATOR MVP
run.py

Role:
- Reads one job folder
- Loads state.json
- Executes current stage
- Writes history/logs
- Advances state
- Stops on FAIL / HOLD
- Never allows publish without verdict=OK

Expected structure:

project_root/
  jobs/
    job_0001/
      input.json
      state.json
      outputs/
      reports/
      logs/

  orchestrator/
    run.py
    stages/
      brief.py
      script.py
      video.py
      audit.py
      publish.py

Stage contract:
Each stage module must expose:

    def run(job_dir: str, state: dict) -> dict

Expected returned payload:
{
    "status": "done" | "fail" | "hold",
    "message": "human readable",
    "artifacts": {... optional ...},
    "verdict": "OK" | "HOLD" | "FAIL" | None
}

MVP notes:
- sequential only
- one job only
- no async
- no queue
- no DB
"""

from __future__ import annotations

import argparse
import importlib
import json
import os
import sys
import traceback
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional

STAGES = ["brief", "script", "video", "audit", "publish"]

NEXT_STAGE = {
    "brief": "script",
    "script": "video",
    "video": "audit",
    "audit": "publish",
    "publish": None,
}

PUBLISH_ENABLED = False  # MVP hard gate


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def read_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: Path, data: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def append_log(log_path: Path, message: str) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    line = f"[{utc_now()}] {message}\n"
    with log_path.open("a", encoding="utf-8") as f:
        f.write(line)


def ensure_job_structure(job_dir: Path) -> None:
    required_dirs = [
        job_dir / "outputs",
        job_dir / "reports",
        job_dir / "logs",
    ]
    for d in required_dirs:
        d.mkdir(parents=True, exist_ok=True)

    if not (job_dir / "input.json").exists():
        raise FileNotFoundError(f"Missing input.json in {job_dir}")

    if not (job_dir / "state.json").exists():
        initial_state = {
            "job_id": job_dir.name,
            "stage": "brief",
            "status": "pending",
            "verdict": None,
            "error": None,
            "history": [],
        }
        write_json(job_dir / "state.json", initial_state)


def append_history(state: Dict[str, Any], event_type: str, details: Optional[Dict[str, Any]] = None) -> None:
    state.setdefault("history", [])
    state["history"].append({
        "ts": utc_now(),
        "event": event_type,
        "details": details or {},
    })


def validate_state(state: Dict[str, Any]) -> None:
    stage = state.get("stage")
    status = state.get("status")

    if stage not in STAGES and stage is not None:
        raise ValueError(f"Invalid stage: {stage}")

    if status not in {"pending", "running", "done", "fail", "hold"}:
        raise ValueError(f"Invalid status: {status}")


def load_stage_module(stage: str):
    module_name = f"stages.{stage}"
    return importlib.import_module(module_name)


def run_stage(job_dir: Path, stage: str, state: Dict[str, Any]) -> Dict[str, Any]:
    module = load_stage_module(stage)
    if not hasattr(module, "run"):
        raise AttributeError(f"Stage module stages.{stage} has no run(job_dir, state) function")
    result = module.run(str(job_dir), state)

    if not isinstance(result, dict):
        raise TypeError(f"Stage {stage} returned non-dict result")

    stage_status = result.get("status")
    if stage_status not in {"done", "fail", "hold"}:
        raise ValueError(f"Stage {stage} returned invalid status: {stage_status}")

    return result


def write_publish_skipped(job_dir: Path, reason: str) -> None:
    report = {
        "status": "skipped",
        "reason": reason,
        "ts": utc_now(),
    }
    write_json(job_dir / "reports" / "publish_report.json", report)


def hard_validate_post_audit(job_dir: Path, state: Dict[str, Any]) -> None:
    """
    Minimum truth gate after audit.
    """
    reports_dir = job_dir / "reports"
    outputs_dir = job_dir / "outputs"

    audit_report = reports_dir / "audit_report.json"
    production_report = reports_dir / "production_report.json"
    final_video = outputs_dir / "final.mp4"

    missing = []
    if not audit_report.exists():
        missing.append(str(audit_report.name))
    if not production_report.exists():
        missing.append(str(production_report.name))
    if not final_video.exists():
        missing.append(str(final_video.name))

    if missing:
        raise RuntimeError(f"Post-audit validation failed, missing required artifacts: {', '.join(missing)}")

    audit_data = read_json(audit_report)
    verdict = audit_data.get("verdict")
    if verdict not in {"OK", "HOLD", "FAIL"}:
        raise RuntimeError("Audit report missing valid verdict")


def save_state(job_dir: Path, state: Dict[str, Any]) -> None:
    write_json(job_dir / "state.json", state)


def process_job(job_dir: Path) -> int:
    ensure_job_structure(job_dir)

    log_path = job_dir / "logs" / "run.log"
    state_path = job_dir / "state.json"
    state = read_json(state_path)

    validate_state(state)

    append_log(log_path, f"JOB_START job_id={state.get('job_id')} stage={state.get('stage')} status={state.get('status')}")

    if state["status"] in {"fail", "hold"}:
        append_log(log_path, f"JOB_STOP terminal_status={state['status']}")
        return 1 if state["status"] == "fail" else 0

    while state.get("stage") is not None:
        current_stage = state["stage"]

        if current_stage == "publish" and not PUBLISH_ENABLED:
            write_publish_skipped(job_dir, "MVP no autopublish")
            append_history(state, "publish_skipped", {"reason": "MVP no autopublish"})
            state["status"] = "done"
            append_log(log_path, "PUBLISH_SKIPPED reason=MVP no autopublish")
            save_state(job_dir, state)
            return 0

        if current_stage == "publish" and state.get("verdict") != "OK":
            write_publish_skipped(job_dir, "publish blocked because verdict != OK")
            append_history(state, "publish_blocked", {"verdict": state.get("verdict")})
            state["status"] = "hold"
            append_log(log_path, f"PUBLISH_BLOCKED verdict={state.get('verdict')}")
            save_state(job_dir, state)
            return 0

        state["status"] = "running"
        state["error"] = None
        append_history(state, "stage_start", {"stage": current_stage})
        save_state(job_dir, state)
        append_log(log_path, f"STAGE_START stage={current_stage}")

        try:
            result = run_stage(job_dir, current_stage, state)
            result_status = result["status"]
            result_message = result.get("message", "")
            result_verdict = result.get("verdict")

            append_log(log_path, f"STAGE_RESULT stage={current_stage} status={result_status} message={result_message}")

            if current_stage == "audit":
                state["verdict"] = result_verdict

            append_history(
                state,
                "stage_result",
                {
                    "stage": current_stage,
                    "status": result_status,
                    "message": result_message,
                    "verdict": result_verdict,
                },
            )

            if result_status == "fail":
                state["status"] = "fail"
                state["error"] = result_message or f"Stage {current_stage} failed"
                save_state(job_dir, state)
                append_log(log_path, f"JOB_FAIL stage={current_stage} error={state['error']}")
                return 1

            if result_status == "hold":
                state["status"] = "hold"
                save_state(job_dir, state)
                append_log(log_path, f"JOB_HOLD stage={current_stage}")
                return 0

            # result_status == done
            if current_stage == "audit":
                hard_validate_post_audit(job_dir, state)

                if state["verdict"] == "FAIL":
                    state["status"] = "fail"
                    state["error"] = "Audit verdict = FAIL"
                    save_state(job_dir, state)
                    append_log(log_path, "JOB_FAIL verdict=FAIL")
                    return 1

                if state["verdict"] == "HOLD":
                    state["status"] = "hold"
                    save_state(job_dir, state)
                    append_log(log_path, "JOB_HOLD verdict=HOLD")
                    return 0

            next_stage = NEXT_STAGE[current_stage]
            state["stage"] = next_stage
            state["status"] = "pending"
            save_state(job_dir, state)

            append_log(log_path, f"STAGE_DONE stage={current_stage} next_stage={next_stage}")

            if next_stage is None:
                append_log(log_path, "JOB_DONE final_state_reached")
                return 0

        except Exception as exc:
            state["status"] = "fail"
            state["error"] = str(exc)

            append_history(
                state,
                "stage_exception",
                {
                    "stage": current_stage,
                    "error": str(exc),
                    "traceback": traceback.format_exc(),
                },
            )
            save_state(job_dir, state)

            append_log(log_path, f"STAGE_EXCEPTION stage={current_stage} error={exc}")
            append_log(log_path, traceback.format_exc())
            return 1

    append_log(log_path, "JOB_DONE stage=None")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Run one Video Agent Factory job.")
    parser.add_argument("--job-dir", required=True, help="Path to a single job folder, e.g. jobs/job_0001")
    args = parser.parse_args()

    job_dir = Path(args.job_dir).resolve()
    if not job_dir.exists():
        print(f"ERROR: job dir not found: {job_dir}", file=sys.stderr)
        return 1

    return process_job(job_dir)


if __name__ == "__main__":
    sys.exit(main())
