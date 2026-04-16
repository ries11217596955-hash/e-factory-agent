import argparse
from pathlib import Path
import json
import shutil
import importlib

NEXT = {
    "brief": "script",
    "script": "video",
    "video": "audit",
    "audit": None,
}

def read_json(p):
    return json.loads(p.read_text())

def write_json(p, d):
    p.write_text(json.dumps(d, indent=2))

def reset(job_dir):
    for d in ["outputs", "reports", "logs"]:
        p = job_dir / d
        if p.exists():
            shutil.rmtree(p)
        p.mkdir(parents=True)

    state = {
        "job_id": job_dir.name,
        "stage": "brief",
        "status": "pending",
        "verdict": None,
        "error": None,
        "history": []
    }
    write_json(job_dir / "state.json", state)
    return state

def run_stage(job_dir, stage, state):
    mod = importlib.import_module(f"stages.{stage}")
    return mod.run(str(job_dir), state)

def process(job_dir, restart):
    state = reset(job_dir) if restart else read_json(job_dir/"state.json")

    while state["stage"]:
        stage = state["stage"]

        result = run_stage(job_dir, stage, state)

        if stage == "audit":
            verdict = result.get("verdict")
            state["verdict"] = verdict

            if verdict == "FAIL":
                state["status"] = "fail"
                write_json(job_dir/"state.json", state)
                return

            if verdict == "HOLD":
                state["status"] = "hold"
                write_json(job_dir/"state.json", state)
                return

        state["stage"] = NEXT[stage]
        state["status"] = "pending"
        write_json(job_dir/"state.json", state)

    return

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--job-dir", required=True)
    parser.add_argument("--restart", action="store_true")

    args = parser.parse_args()

    process(Path(args.job_dir), args.restart)

if __name__ == "__main__":
    main()
