import json
import os
import sys
from pathlib import Path
import re

ASSET_RE = re.compile(r"\.(css|js|webmanifest|png|jpg|jpeg|svg|ico|woff|woff2|gif)$", re.I)

def resolve_report_path():
    if len(sys.argv) >= 2:
        return Path(sys.argv[1])
    env_path = os.environ.get("LATEST_REPORT")
    if env_path:
        return Path(env_path)
    reports = sorted(Path("agents/site_auditor_v3/runs").glob("*/RUN_REPORT.json"))
    if reports:
        return reports[-1]
    return None

p = resolve_report_path()
if not p or not p.exists():
    print("FAIL: RUN_REPORT missing")
    sys.exit(1)

j = json.loads(p.read_text(encoding="utf-8"))

required = [
    "read_me_first",
    "identity",
    "mission",
    "operator_instruction",
    "read_order",
    "audit_result",
    "evidence_summary",
    "diagnostic_summary",
    "agent_capability_state",
    "decision_action",
    "next_step",
    "forbidden_steps",
]

missing = [k for k in required if k not in j]
if missing:
    print("FAIL: missing RUN_REPORT keys:", missing)
    sys.exit(1)

decision_action = str(j.get("decision_action", {}).get("action", "")).lower()
next_action = str(j.get("next_step", {}).get("action", "")).lower()

if not decision_action or next_action != decision_action:
    print("FAIL: next_step not tied to decision_action")
    print("decision_action:", decision_action)
    print("next_step.action:", next_action)
    sys.exit(1)

forbidden = j.get("forbidden_steps", [])
if not isinstance(forbidden, list) or not forbidden:
    print("FAIL: forbidden_steps missing or empty")
    sys.exit(1)

build = j.get("build") or {}
if isinstance(build, dict):
    if "decision_action" in build:
        print("FAIL: build must not emit decision_action")
        sys.exit(1)

    if build.get("next_action") and not build.get("build_recommendation"):
        print("FAIL: build next_action missing build_recommendation")
        sys.exit(1)

    if build.get("next_action") and build.get("build_recommendation") != build.get("next_action"):
        print("FAIL: build next_action must remain a compatibility alias of build_recommendation")
        sys.exit(1)

    gate = j.get("build_truth_gate") or {}
    if build.get("build_status") and not gate:
        print("FAIL: build_truth_gate missing for build_status")
        sys.exit(1)

    if gate and not isinstance(gate, dict):
        print("FAIL: build_truth_gate must be an object")
        sys.exit(1)

    if gate and (gate.get("checked") is not True or not str(gate.get("reason", "")).strip()):
        print("FAIL: build_truth_gate must be checked with a non-empty reason")
        sys.exit(1)

    if build.get("build_status") == "ALREADY_AVAILABLE":
        if gate.get("passed") is not True:
            print("FAIL: ALREADY_AVAILABLE build_truth_gate must pass")
            sys.exit(1)
        if not gate.get("target_file") or not gate.get("existing_function") or gate.get("mode") != "EXISTING_HANDLER":
            print("FAIL: ALREADY_AVAILABLE build_truth_gate missing target/function/mode proof")
            sys.exit(1)
        if gate.get("command_available") is not True and gate.get("function_in_target") is not True:
            print("FAIL: ALREADY_AVAILABLE existing_function not verified")
            sys.exit(1)

    if build.get("build_status") == "SKIPPED" and (gate.get("passed") is not True or gate.get("reason") != "no build task"):
        print("FAIL: SKIPPED build_truth_gate invalid")
        sys.exit(1)

    if build.get("build_status") == "FAILED" and gate.get("passed") is not False:
        print("FAIL: FAILED build_truth_gate must fail")
        sys.exit(1)

    if (
        build.get("build_status") == "GENERATED"
        and build.get("build_recommendation")
        and isinstance(gate, dict)
        and gate.get("passed") is True
        and j.get("decision_action") != build.get("build_recommendation")
    ):
        print("FAIL: generated build recommendation was not promoted by post_build_decision")
        sys.exit(1)


# Route feedback contract: if execution discovered more routes than baseline audit,
# RUN_REPORT must expose that gap in evidence_summary.route_feedback.
ev = j.get("evidence_summary") or {}
rf = ev.get("route_feedback")
execution = j.get("execution") or {}
er = ((execution.get("execution_result") or {}).get("data") or {})
baseline = ev.get("routes_discovered") or 0
discovered = er.get("discovered_count") or 0

try:
    baseline_i = int(baseline)
    discovered_i = int(discovered)
except Exception:
    baseline_i = 0
    discovered_i = 0

if discovered_i > baseline_i:
    if not isinstance(rf, dict):
        print("FAIL: evidence_summary.route_feedback missing while execution discovered more routes than route_audit")
        sys.exit(1)
    if rf.get("available") is not True:
        print("FAIL: route_feedback.available must be true when execution discovered more routes than baseline")
        sys.exit(1)
    if int(rf.get("baseline_routes_discovered") or 0) != baseline_i:
        print("FAIL: route_feedback.baseline_routes_discovered mismatch")
        sys.exit(1)
    if int(rf.get("execution_routes_discovered") or 0) != discovered_i:
        print("FAIL: route_feedback.execution_routes_discovered mismatch")
        sys.exit(1)
    if len(rf.get("discovered_routes") or []) != discovered_i:
        print("FAIL: route_feedback.discovered_routes count mismatch")
        sys.exit(1)
    if rf.get("next_owner_module") != "route_audit":
        print("FAIL: route_feedback.next_owner_module must be route_audit")
        sys.exit(1)

if isinstance(rf, dict):
    ds = rf.get("discovery_sources") or []
    if not isinstance(ds, list) or not ds:
        print("FAIL: route_feedback.discovery_sources must be a non-empty list")
        sys.exit(1)
    if rf.get("scope_status") not in ("COMPLETE", "PARTIAL"):
        print("FAIL: route_feedback.scope_status invalid")
        sys.exit(1)
    page_details = rf.get("page_route_details") or []
    asset_details = rf.get("asset_route_details") or []
    if page_details and int(rf.get("pages_discovered_count") or 0) != len(page_details):
        print("FAIL: pages_discovered_count mismatch against page_route_details")
        sys.exit(1)
    if asset_details and int(rf.get("assets_excluded_count") or 0) != len(asset_details):
        print("FAIL: assets_excluded_count mismatch against asset_route_details")
        sys.exit(1)
    for pr in rf.get("promoted_routes") or []:
        path = str(pr.get("path") or "")
        if ASSET_RE.search(path) or path.endswith("/sitemap.xml") or path.endswith("/feed.xml"):
            print("FAIL: promoted_routes contains asset/feed path:", path)
            sys.exit(1)
    if bool(er.get("truncated")) and rf.get("scope_status") != "PARTIAL":
        print("FAIL: truncated discovery must report PARTIAL scope")
        sys.exit(1)

print("PASS: RUN_REPORT contract")
