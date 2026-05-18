#!/usr/bin/env python3
"""Validate repair-execution outputs for finalized Site Auditor V3 sessions."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any, NoReturn


REQUIRED_ARTIFACTS = {
    "repair_execution_plan": "REPAIR_EXECUTION_PLAN.json",
    "repair_execution_report": "REPAIR_EXECUTION_REPORT.md",
}


def fail(message: str) -> NoReturn:
    print(f"REPAIR_EXECUTION_VALIDATION_FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        fail(f"missing JSON file: {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")
    return {}


def main() -> int:
    report_path = Path(os.environ.get("RUN_REPORT_PATH") or "").resolve()
    if not report_path.is_file():
        fail("RUN_REPORT_PATH must point to an existing RUN_REPORT.json")

    report = read_json(report_path)
    run_root = report_path.parent
    finalization = report.get("finalization") or {}
    finalization_status = str(finalization.get("status") or "")

    if finalization_status != "FINALIZED":
        print("REPAIR_EXECUTION_VALIDATION=SKIPPED_NOT_FINALIZED")
        return 0

    repair_execution = report.get("repair_execution") or {}
    status = str(repair_execution.get("status") or "")
    if status not in {"PLAN_READY", "NO_ACTIONS"}:
        fail(f"repair_execution.status must be PLAN_READY or NO_ACTIONS, got {status!r}")

    artifacts = repair_execution.get("artifacts") or {}
    for key, relative_path in REQUIRED_ARTIFACTS.items():
        declared = str(artifacts.get(key) or "")
        if declared != relative_path:
            fail(f"repair_execution.artifacts.{key} must equal {relative_path!r}, got {declared!r}")
        if not (run_root / relative_path).is_file():
            fail(f"declared repair execution artifact missing: {relative_path}")

    plan = read_json(run_root / REQUIRED_ARTIFACTS["repair_execution_plan"])
    if plan.get("artifact") != "REPAIR_EXECUTION_PLAN":
        fail("REPAIR_EXECUTION_PLAN artifact marker mismatch")
    if str(plan.get("status") or "") != status:
        fail("REPAIR_EXECUTION_PLAN status must match RUN_REPORT.repair_execution.status")
    if str(plan.get("source_final_action_plan") or "") != "FINAL_ACTION_PLAN.json":
        fail("REPAIR_EXECUTION_PLAN source_final_action_plan mismatch")

    plan_contract = plan.get("plan_contract") or {}
    if str(plan_contract.get("contract_id") or "") != "site_auditor_v3_repair_execution_layer":
        fail("REPAIR_EXECUTION_PLAN plan_contract.contract_id mismatch")

    safety_gate = plan.get("safety_gate") or {}
    if str(safety_gate.get("status") or "") != "PASS":
        fail("repair execution safety_gate.status must be PASS")
    if safety_gate.get("allow_target_mutation") is not False:
        fail("repair execution allow_target_mutation must be false")
    if safety_gate.get("allow_repo_mutation") is not False:
        fail("repair execution allow_repo_mutation must be false")
    if safety_gate.get("auto_apply_enabled") is not False:
        fail("repair execution auto_apply_enabled must be false")

    queue_summary = plan.get("queue_summary") or {}
    execution_queue = plan.get("execution_queue") or []
    if int(queue_summary.get("total_actions") or 0) != len(execution_queue):
        fail("queue_summary.total_actions must equal execution_queue length")

    one_next = plan.get("one_next_execution_action") or {}
    if not one_next.get("action_id"):
        fail("one_next_execution_action.action_id missing")
    if not one_next.get("disposition"):
        fail("one_next_execution_action.disposition missing")

    report_md = run_root / REQUIRED_ARTIFACTS["repair_execution_report"]
    report_text = report_md.read_text(encoding="utf-8")
    for heading in (
        "# REPAIR_EXECUTION_REPORT",
        "## Safety gate",
        "## Queue summary",
        "## One next execution action",
    ):
        if heading not in report_text:
            fail(f"REPAIR_EXECUTION_REPORT.md missing heading: {heading}")

    print("REPAIR_EXECUTION_VALIDATION=PASS")
    print(f"REPAIR_EXECUTION_STATUS={status}")
    print(f"REPAIR_EXECUTION_ACTION_COUNT={len(execution_queue)}")
    print(f"REPAIR_EXECUTION_NEXT_CLASS={one_next.get('execution_class')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
