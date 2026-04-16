import json
from pathlib import Path


def run(job_dir, state):
    job_dir = Path(job_dir)

    script_path = job_dir / "outputs" / "script.txt"
    video_path = job_dir / "outputs" / "final.mp4"
    reports_dir = job_dir / "reports"
    reports_dir.mkdir(parents=True, exist_ok=True)

    audit_report_path = reports_dir / "audit_report.json"
    production_report_path = reports_dir / "production_report.json"

    issues = []
    score = 100

    if not script_path.exists():
        issues.append("SCRIPT_MISSING")
        score -= 40
        script_text = ""
    else:
        script_text = script_path.read_text(encoding="utf-8").strip()
        if len(script_text) < 50:
            issues.append("SCRIPT_TOO_SHORT")
            score -= 20

    if not video_path.exists():
        issues.append("VIDEO_MISSING")
        score -= 40

    upper_text = script_text.upper()
    if script_text:
        if "HOOK" not in upper_text:
            issues.append("NO_HOOK")
            score -= 10
        if "CTA" not in upper_text:
            issues.append("NO_CTA")
            score -= 10

    if score >= 80:
        verdict = "OK"
    elif score >= 50:
        verdict = "HOLD"
    else:
        verdict = "FAIL"

    audit_report = {
        "stage": "audit",
        "status": "done",
        "score": score,
        "verdict": verdict,
        "issues": issues,
    }

    production_report = {
        "source_stage": "audit",
        "status": "ready" if verdict == "OK" else "blocked",
        "ready_for_publish": verdict == "OK",
        "video_artifact": "outputs/final.mp4" if video_path.exists() else None,
        "audit_verdict": verdict,
        "audit_score": score,
    }

    audit_report_path.write_text(json.dumps(audit_report, ensure_ascii=False, indent=2), encoding="utf-8")
    production_report_path.write_text(json.dumps(production_report, ensure_ascii=False, indent=2), encoding="utf-8")

    return {
        "status": "done",
        "message": "audit complete",
        "verdict": verdict,
        "artifacts": {
            "audit_report": "reports/audit_report.json",
            "production_report": "reports/production_report.json",
        },
    }
