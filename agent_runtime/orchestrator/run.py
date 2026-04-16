cd /workspaces/e-factory-agent

cat > agent_runtime/orchestrator/run.py <<'PY'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import importlib
import json
import shutil
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

PUBLISH_ENABLED = False


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
    with log_path.open("a", encoding="utf-8") as f:
        f.write(f"[{utc_now()}] {message}\n")


def build_initial_state(job_dir: Path) -> Dict[str, Any]:
    return {
        "job_id": job_dir.name,
        "stage": "brief",
        "status": "pending",
        "verdict": None,
        "error": None,
        "history": [],
    }


def ensure_job_structure(job_dir: Path) -> None:
    for d in ("outputs", "reports", "logs"):
        (job_dir / d).mkdir(parents=True, exist_ok=True)

    if not (job_dir / "input.json").exists():
        raise FileNotFoundError("Missing input.json")

    if not (job_dir / "state.json").exists():
        write_json(job_dir / "state.json", build_initial_state(job_dir))


def reset_job(job_dir: Path) -> Dict[str, Any]:
    for d in ("outputs", "reports", "logs"):
        p = job_dir / d
        if p.exists():
            shutil.rmtree(p)
        p.mkdir(parents=True, exist_ok=True)

    state = build_initial_state(job_dir)
    write_json(job_dir / "state.json", state)
    return state


def load_stage(stage: str):
    return importlib.import_module(f"stages.{stage}")


def run_stage(job_dir: Path, stage: str, state: Dict[str, Any]) -> Dict[str, Any]:
    mod = load_stage(stage)
    return mod.run(str(job_dir), state)


def process_job(job_dir: Path, restart: bool) -> int:
    ensure_job_structure(job_dir)

    state = reset_job(job_dir) if restart else read_json(job_dir / "state.json")
    log = job_dir / "logs" / "run.log"

    if state["status"] == "done" and not restart:
        append_log(log, "NOOP: already done")
        return 0

    while state["stage"]:
        stage = state["stage"]

        state["status"] = "running"
        write_json(job_dir / "state.json", state)

        try:
            result = run_stage(job_dir, stage, state)

            if stage == "audit":
                state["verdict"] = result.get("verdict")

                if state["verdict"] == "FAIL":
                    state["status"] = "fail"
                    write_json(job_dir / "state.json", state)
                    return 1

                if state["verdict"] == "HOLD":
                    state["status"] = "hold"
                    write_json(job_dir / "state.json", state)
                    return 0

            state["stage"] = NEXT_STAGE[stage]
            state["status"] = "pending"
            write_json(job_dir / "state.json", state)

            if state["stage"] is None:
                return 0

        except Exception as e:
            state["status"] = "fail"
            state["error"] = str(e)
            write_json(job_dir / "state.json", state)
            return 1

    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--job-dir", required=True)
    parser.add_argument("--restart", action="store_true")

    args = parser.parse_args()

    return process_job(Path(args.job_dir), args.restart)


if __name__ == "__main__":
    sys.exit(main())
PY

# ПРОВЕРКА
python agent_runtime/orchestrator/run.py --help
