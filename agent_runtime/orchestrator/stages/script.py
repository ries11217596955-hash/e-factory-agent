from pathlib import Path

def run(job_dir, state):
    job_dir = Path(job_dir)

    brief_path = job_dir / "outputs" / "brief.txt"
    script_path = job_dir / "outputs" / "script.txt"

    text = brief_path.read_text() + "\n\nSCRIPT:\nHook → Content → CTA"

    script_path.write_text(text)

    return {
        "status": "done",
        "message": "script created"
    }
