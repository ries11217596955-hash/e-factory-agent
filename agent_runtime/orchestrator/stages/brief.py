import json
from pathlib import Path


REQUIRED_FIELDS = ["topic", "target_channel"]


def _write_diag(job_dir: Path, payload: dict) -> None:
    reports_dir = job_dir / "reports"
    reports_dir.mkdir(parents=True, exist_ok=True)
    (reports_dir / "brief_diagnostic.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def run(job_dir, state):
    job_dir = Path(job_dir)

    input_path = job_dir / "input.json"
    output_path = job_dir / "outputs" / "brief.txt"

    if not input_path.exists():
        diag = {
            "stage": "brief",
            "status": "fail",
            "reason": "INPUT_MISSING",
            "path": str(input_path),
        }
        _write_diag(job_dir, diag)
        return {
            "status": "fail",
            "message": f"brief input missing: {input_path.name}",
            "artifacts": {"diagnostic": "reports/brief_diagnostic.json"},
        }

    raw = input_path.read_text(encoding="utf-8-sig").strip()

    if not raw:
        diag = {
            "stage": "brief",
            "status": "fail",
            "reason": "INPUT_EMPTY",
            "path": str(input_path),
        }
        _write_diag(job_dir, diag)
        return {
            "status": "fail",
            "message": "brief input is empty",
            "artifacts": {"diagnostic": "reports/brief_diagnostic.json"},
        }

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        diag = {
            "stage": "brief",
            "status": "fail",
            "reason": "INPUT_JSON_INVALID",
            "path": str(input_path),
            "error": str(exc),
            "raw_preview": raw[:500],
        }
        _write_diag(job_dir, diag)
        return {
            "status": "fail",
            "message": f"invalid input.json: {exc}",
            "artifacts": {"diagnostic": "reports/brief_diagnostic.json"},
        }

    missing = [key for key in REQUIRED_FIELDS if not data.get(key)]
    if missing:
        diag = {
            "stage": "brief",
            "status": "fail",
            "reason": "INPUT_SCHEMA_INVALID",
            "missing_fields": missing,
            "received_keys": sorted(list(data.keys())),
        }
        _write_diag(job_dir, diag)
        return {
            "status": "fail",
            "message": f"missing required fields: {', '.join(missing)}",
            "artifacts": {"diagnostic": "reports/brief_diagnostic.json"},
        }

    text = (
        "BRIEF:\n"
        f"Topic: {data['topic']}\n"
        f"Channel: {data['target_channel']}\n"
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(text, encoding="utf-8")

    return {
        "status": "done",
        "message": "brief created",
        "artifacts": {
            "brief": "outputs/brief.txt"
        }
    }
