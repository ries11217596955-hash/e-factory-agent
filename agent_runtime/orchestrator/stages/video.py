from pathlib import Path


def run(job_dir, state):
    job_dir = Path(job_dir)

    script_path = job_dir / "outputs" / "script.txt"
    video_path = job_dir / "outputs" / "final.mp4"

    if not script_path.exists():
        return {
            "status": "fail",
            "message": "script.txt missing",
        }

    video_path.parent.mkdir(parents=True, exist_ok=True)
    video_path.write_text("FAKE VIDEO FILE\nSOURCE=script.txt\n", encoding="utf-8")

    return {
        "status": "done",
        "message": "video generated",
        "artifacts": {
            "video": "outputs/final.mp4",
        },
    }
