from pathlib import Path

def run(job_dir, state):
    job_dir = Path(job_dir)

    video_path = job_dir / "outputs" / "final.mp4"

    video_path.parent.mkdir(parents=True, exist_ok=True)
    video_path.write_text("FAKE VIDEO FILE")

    return {
        "status": "done",
        "message": "video generated"
    }
