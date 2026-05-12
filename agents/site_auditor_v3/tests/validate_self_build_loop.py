import json, os, sys
from pathlib import Path

p = Path(os.environ.get("RUN_REPORT_PATH", ""))
if not p.exists():
    print("FAIL: RUN_REPORT_PATH missing")
    sys.exit(1)

j = json.loads(p.read_text(encoding="utf-8"))
errors = []

if not j.get("decision_action"):
    errors.append("decision_action missing")
if not j.get("execution"):
    errors.append("execution missing")
if not j.get("route_discovery_result"):
    errors.append("route_discovery_result missing")
if not j.get("task"):
    errors.append("task missing")

data = j.get("route_discovery_result") or {}
if data.get("capability_id") != "route_discovery":
    errors.append("route_discovery_result wrong capability")
if data.get("mode") != "READ_ONLY":
    errors.append("route_discovery_result not READ_ONLY")
if "discovered_routes" not in data:
    errors.append("discovered_routes missing")
if "rejected_routes" not in data:
    errors.append("rejected_routes missing")
if data.get("checked_count", 0) < 1:
    errors.append("checked_count < 1")
if not data.get("discovery_sources") or not isinstance(data.get("discovery_sources"), list):
    errors.append("discovery_sources missing/invalid")
if not data.get("scope_status"):
    errors.append("scope_status missing")
if "pages_discovered_count" not in data and "discovered_count" not in data:
    errors.append("page/discovered count missing")
if "rejected_routes" in data and not isinstance(data.get("rejected_routes"), list):
    errors.append("rejected_routes invalid shape")

if errors:
    print("FAIL: SELF_BUILD_LOOP_V1:", errors)
    sys.exit(1)

print("PASS: SELF_BUILD_LOOP_V1")
