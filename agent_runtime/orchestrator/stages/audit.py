print("AUDIT V2 LOADED")
import json
from pathlib import Path


def run(job_dir, state):
    job_dir = Path(job_dir)

    script_path = job_dir / "outputs" / "script.txt"
    video_path = job_dir / "outputs" / "final.mp4"

    report_path = job_dir / "reports" / "audit_report.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)

    issues = []
    score = 100

    # --- CHECK 1: script exists ---
    if not script_path.exists():
        issues.append("SCRIPT_MISSING")
        score -= 40
    else:
        text = script_path.read_text(encoding="utf-8").strip()
        if len(text) < 50:
            issues.append("SCRIPT_TOO_SHORT")
            score -= 20

    # --- CHECK 2: video exists ---
    if not video_path.exists():
        issues.append("VIDEO_MISSING")
        score -= 40

    # --- CHECK 3: basic structure ---
    if script_path.exists():
        text = script_path.read_text(encoding="utf-8")
        if "HOOK" not in text.upper():
            issues.append("NO_HOOK")
            score -= 10
        if "CTA" not in text.upper():
            issues.append("NO_CTA")
            score -= 10

    # --- VERDICT LOGIC ---
    if score >= 80:
        verdict = "OK"
    elif score >= 50:
        verdict = "HOLD"
    else:
        verdict = "FAIL"

    report = {
        "stage": "audit",
        "status": "done",
        "score": score,
        "verdict": verdict,
        "issues": issues,
    }

    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2),
        encoding="utf-8"
    )

    return {
        "status": "done",
        "message": "audit complete",
        "verdict": verdict,
        "artifacts": {
            "audit_report": "reports/audit_report.json"
        }
    }
