#!/usr/bin/env python3
"""Validate completed-session finalization outputs for Site Auditor V3."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any


REQUIRED_FINAL_ARTIFACTS = {
    "session_aggregate": "SESSION_AGGREGATE.json",
    "final_operator_report": "FINAL_OPERATOR_REPORT.md",
    "final_action_plan": "FINAL_ACTION_PLAN.json",
    "final_findings_index": "FINAL_FINDINGS_INDEX.json",
}


def fail(message: str) -> "NoReturn":
    print(f"FINALIZATION_VALIDATION_FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        fail(f"missing JSON file: {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")
    return {}


def require(mapping: dict[str, Any], key: str, owner: str) -> Any:
    if key not in mapping:
        fail(f"{owner} missing key: {key}")
    return mapping[key]


def main() -> int:
    report_path = Path(os.environ.get("RUN_REPORT_PATH") or "").resolve()
    if not report_path.is_file():
        fail("RUN_REPORT_PATH must point to an existing RUN_REPORT.json")

    report = read_json(report_path)
    run_root = report_path.parent
    audit_session = report.get("audit_session") or {}
    finalization = report.get("finalization") or {}
    next_action = str(audit_session.get("next_action") or "UNKNOWN")
    pending = int(audit_session.get("total_pending_count") or 0)

    if pending > 0:
        print("FINALIZATION_VALIDATION=SKIPPED_PENDING")
        return 0

    if finalization.get("status") != "FINALIZED":
        fail(
            "completed session must expose report.finalization.status=FINALIZED "
            f"(next_action={next_action!r}, pending={pending})"
        )

    artifacts = finalization.get("artifacts") or {}
    for key, relative_path in REQUIRED_FINAL_ARTIFACTS.items():
        declared = str(artifacts.get(key) or "")
        if declared != relative_path:
            fail(f"finalization.artifacts.{key} must equal {relative_path!r}, got {declared!r}")
        if not (run_root / relative_path).is_file():
            fail(f"declared final artifact missing: {relative_path}")

    aggregate = read_json(run_root / REQUIRED_FINAL_ARTIFACTS["session_aggregate"])
    if aggregate.get("artifact") != "SESSION_AGGREGATE":
        fail("SESSION_AGGREGATE.json artifact marker mismatch")
    if aggregate.get("finalization_status") != "FINALIZED":
        fail("SESSION_AGGREGATE.json finalization_status must be FINALIZED")

    coverage = aggregate.get("coverage_truth") or {}
    if int(coverage.get("total_pending_count") or -1) != 0:
        fail("SESSION_AGGREGATE coverage total_pending_count must be 0")
    if str(coverage.get("coverage_gate") or "") != "PASS":
        fail("SESSION_AGGREGATE coverage_gate must be PASS")

    streams = aggregate.get("report_streams") or []
    stream_ids = {str(item.get("stream_id") or "") for item in streams if isinstance(item, dict)}
    required_stream_ids = {
        "coverage_truth",
        "cumulative_findings",
        "remediation_actions",
        "batch_execution_history",
    }
    if not required_stream_ids.issubset(stream_ids):
        fail(f"SESSION_AGGREGATE report_streams missing required IDs: {sorted(required_stream_ids - stream_ids)}")

    decision = aggregate.get("final_decision") or {}
    require(decision, "verdict", "SESSION_AGGREGATE.final_decision")
    require(decision, "one_next_action", "SESSION_AGGREGATE.final_decision")

    action_plan = read_json(run_root / REQUIRED_FINAL_ARTIFACTS["final_action_plan"])
    if action_plan.get("artifact") != "FINAL_ACTION_PLAN":
        fail("FINAL_ACTION_PLAN.json artifact marker mismatch")

    findings_index = read_json(run_root / REQUIRED_FINAL_ARTIFACTS["final_findings_index"])
    if findings_index.get("artifact") != "FINAL_FINDINGS_INDEX":
        fail("FINAL_FINDINGS_INDEX.json artifact marker mismatch")

    operator_report = run_root / REQUIRED_FINAL_ARTIFACTS["final_operator_report"]
    report_text = operator_report.read_text(encoding="utf-8")
    for required_heading in ("# FINAL_OPERATOR_REPORT", "## Final verdict", "## One next action"):
        if required_heading not in report_text:
            fail(f"FINAL_OPERATOR_REPORT.md missing heading: {required_heading}")

    print("FINALIZATION_VALIDATION=PASS")
    print(f"FINALIZATION_SESSION_ID={audit_session.get('session_id')}")
    print(f"FINALIZATION_VERDICT={decision.get('verdict')}")
    print(f"FINALIZATION_STREAM_COUNT={len(streams)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
