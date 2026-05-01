import json
import re
import sys
from pathlib import Path

ROOT = Path("agents/site_auditor_v3")
REGISTRY = ROOT / "contracts/module_registry.json"
RUN = ROOT / "run.ps1"
MODULES = ROOT / "modules"
REPORT = ROOT / "runs/manual-smoke/RUN_REPORT.json"

errors = []

def fail(code, msg):
    errors.append(f"{code}: {msg}")

def read(p):
    return p.read_text(encoding="utf-8", errors="replace")

# === REGISTRY GUARD ===
if not REGISTRY.exists():
    fail("REGISTRY_MISSING", str(REGISTRY))
else:
    reg = json.loads(read(REGISTRY))
    modules = reg.get("modules", [])
    ids = [m.get("module_id") for m in modules]
    ords = [m.get("ordinal") for m in modules]

    if len(ids) != len(set(ids)):
        fail("REGISTRY_DUPLICATE_MODULE_ID", str(ids))

    if sorted(ords) != list(range(1, len(ords) + 1)):
        fail("REGISTRY_ORDINAL_DRIFT", str(ords))

    writers = [m for m in modules if m.get("writes_final_outputs") is True]
    if len(writers) != 1:
        fail("REGISTRY_OUTPUT_WRITER_COUNT", str([m.get("module_id") for m in writers]))
    elif writers[0].get("module_id") != "07_output":
        fail("REGISTRY_OUTPUT_WRITER_NOT_07", writers[0].get("module_id"))

    if writers and writers[0].get("ordinal") != max(ords):
        fail("REGISTRY_OUTPUT_NOT_LAST", writers[0].get("module_id"))

    for m in modules:
        if m.get("enabled") and not Path(m.get("file_path", "")).exists():
            fail("REGISTRY_ENABLED_MODULE_MISSING", f"{m.get('module_id')} -> {m.get('file_path')}")

        for dep in m.get("depends_on", []):
            if dep not in ids:
                fail("REGISTRY_BAD_DEPENDENCY", f"{m.get('module_id')} depends on {dep}")

# === ORCHESTRATOR GUARD ===
if not RUN.exists():
    fail("RUN_MISSING", str(RUN))
else:
    s = read(RUN)

    if "module_registry.json" not in s:
        fail("RUN_NOT_REGISTRY_DRIVEN", "run.ps1 must load module_registry.json")

    forbidden_module_literals = [
        "01_input", "02_route_audit", "03_selection", "04_capture",
        "05_reconcile", "06_decision", "07_output"
    ]
    for lit in forbidden_module_literals:
        if lit in s:
            fail("RUN_HARDCODED_MODULE_ID", lit)

    if re.search(r"\bInvoke-.*Module\b", s):
        fail("RUN_HARDCODED_MODULE_CALL", "run.ps1 must call entry_function from registry")

    if s.count("foreach") > 3 or len(s.splitlines()) > 120:
        fail("RUN_MONOLITH_RISK", "run.ps1 too large or too procedural")

# === MODULE PURITY GUARD ===
write_cmds = [
    "Set-Content", "Add-Content", "Out-File", "New-Item",
    "Copy-Item", "Move-Item", "Remove-Item", "Start-Transcript"
]
bad_quality_words = [
    "TODO", "PLACEHOLDER", "STUB", "MOCK", "hardcoded",
    "pipeline executed"
]

for p in sorted(MODULES.glob("*.ps1")):
    s = read(p)
    name = p.name

    if "function " not in s:
        fail("MODULE_NO_FUNCTION", name)

    if name != "07_output.ps1":
        for cmd in write_cmds:
            if re.search(rf"\b{re.escape(cmd)}\b", s):
                fail("MODULE_WRITES_FILES", f"{name}: {cmd}")

    if name != "07_output.ps1" and "Write-Host" in s:
        fail("MODULE_WRITE_HOST", name)

    for word in bad_quality_words:
        if word.lower() in s.lower():
            fail("QUALITY_FLOOR_FORBIDDEN_WORD", f"{name}: {word}")

    if re.search(r"status\s*=\s*[\"']OK[\"']\s*[\r\n\s]*data\s*=\s*@\{\s*\}", s, re.I):
        fail("QUALITY_EMPTY_CAPABILITY", name)

# === RUN_REPORT GUARD ===
if not REPORT.exists():
    fail("RUN_REPORT_MISSING", str(REPORT))
else:
    j = json.loads(read(REPORT))

    required_top = [
        "read_me_first", "identity", "mission", "operator_instruction",
        "read_order", "if_problem_then_read", "pipeline_status",
        "audit_result", "evidence_summary", "diagnostic_summary",
        "agent_capability_state", "next_step", "forbidden_steps"
    ]
    for k in required_top:
        if k not in j:
            fail("RUN_REPORT_MISSING_KEY", k)

    d = j.get("diagnostic_summary", {})
    diag_required = [
        "failed_stage", "what_worked", "what_failed", "limitations",
        "evidence_gaps", "confidence", "next_debug_step",
        "next_build_step", "forbidden_next_steps"
    ]
    for k in diag_required:
        if k not in d:
            fail("RUN_REPORT_DIAGNOSTIC_MISSING_KEY", k)

    cap = str(j.get("agent_capability_state", {}).get("next_capability_to_build", "")).lower()
    action = str(j.get("next_step", {}).get("action", "")).lower()
    if cap and cap not in action:
        fail("RUN_REPORT_NEXT_STEP_NOT_TIED_TO_CAPABILITY", f"cap={cap}; action={action}")

    if "already" in action or "verify generated run_report" in action:
        fail("RUN_REPORT_STALE_NEXT_STEP", action)

# === DIRTY ARTIFACT GUARD ===
runtime_bad = [
    ROOT / "RUN_REPORT.json",
    ROOT / "AGENT_MAP.json",
    ROOT / "SELF_DIAGNOSTIC.json",
    ROOT / "AUDIT_RESULT.json",
]
for p in runtime_bad:
    if p.exists():
        fail("ROOT_RUNTIME_ARTIFACT", str(p))

if errors:
    print("V3_BUILD_GUARD_FAIL")
    for e in errors:
        print("-", e)
    sys.exit(1)

print("V3_BUILD_GUARD_PASS")
