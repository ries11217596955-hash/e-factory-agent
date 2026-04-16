import argparse
import importlib
import json
from pathlib import Path

NEXT = {
    "brief": "script",
    "script": "video",
    "video": "audit",
    "audit": None
}

def read_json(p):
    return json.loads(p.read_text())

def write_json(p, d):
    p.write_text(json.dumps(d, indent=2))

def run_stage(job_dir, stage, state):
    mod = importlib.import_module(f"stages.{stage}")
    return mod.run(str(job_dir), state)

def process(job_dir):
    state_path = job_dir / "state.json"
    state = read_json(state_path)

    while state["stage"]:
        stage = state["stage"]
        result = run_stage(job_dir, stage, state)

        if stage == "audit":
            state["verdict"] = result.get("verdict")

            if state["verdict"] == "FAIL":
                state["status"] = "fail"
                write_json(state_path, state)
                return

            if state["verdict"] == "HOLD":
                state["status"] = "hold"
                write_json(state_path, state)
                return

            print("DECISION: READY FOR PUBLISH")

        state["stage"] = NEXT[stage]
        write_json(state_path, state)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--job-dir", required=True)
    args = parser.parse_args()

    process(Path(args.job_dir))

if __name__ == "__main__":
    main()
