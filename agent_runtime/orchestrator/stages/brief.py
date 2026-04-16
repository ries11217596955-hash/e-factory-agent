import json
from pathlib import Path

def run(job_dir, state):
    job_dir = Path(job_dir)

    input_path = job_dir / "input.json"
    output_path = job_dir / "outputs" / "brief.txt"

    data = json.loads(input_path.read_text())

    text = f"BRIEF:\nTopic: {data['topic']}\nChannel: {data['target_channel']}"

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(text)

    return {
        "status": "done",
        "message": "brief created"
    }
