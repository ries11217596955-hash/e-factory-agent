from pathlib import Path


def run(job_dir, state):
    job_dir = Path(job_dir)

    brief_path = job_dir / "outputs" / "brief.txt"
    script_path = job_dir / "outputs" / "script.txt"

    if not brief_path.exists():
        return {
            "status": "fail",
            "message": "brief.txt missing",
        }

    brief_text = brief_path.read_text(encoding="utf-8").strip()

    script_text = (
        f"{brief_text}\n\n"
        "SCRIPT:\n"
        "HOOK: Most websites do not lose conversions because of traffic. They lose conversions because of friction.\n"
        "BODY: Show the three biggest mistakes, explain the loss, and give one fix for each mistake.\n"
        "CTA: Audit your page before you buy more traffic.\n"
    )

    script_path.parent.mkdir(parents=True, exist_ok=True)
    script_path.write_text(script_text, encoding="utf-8")

    return {
        "status": "done",
        "message": "script created",
        "artifacts": {
            "script": "outputs/script.txt",
        },
    }
