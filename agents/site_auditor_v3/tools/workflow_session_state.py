#!/usr/bin/env python3
"""GitHub Actions session-state restore/publish helper for Site Auditor V3.

The operator UI intentionally exposes only:
- target_url
- run_mode = START | NEXT | FULL

This helper keeps the workflow from leaking session internals back to the owner.
It provides:
- START guard: block a new START when an unfinished session already exists for the same URL.
- NEXT restore: recover one matching open session from prior workflow artifacts.
- FULL resolve: either restore one matching open session or declare that FULL must begin from a fresh START.
- Session publish: prepare resumable/finalized state artifacts after successful START/NEXT/FULL runs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, NoReturn

SESSION_ARTIFACT_PREFIX = "site-auditor-v3-session-state"
SESSION_STATE_FILE = "SESSION_STATE.json"
LATEST_RUN_REPORT_FILE = "LATEST_RUN_REPORT.json"
REPO_RUNS_SESSIONS = Path("agents/site_auditor_v3/runs/sessions")
FINAL_ARTIFACT_KEYS = {
    "session_aggregate": "SESSION_AGGREGATE.json",
    "final_operator_report": "FINAL_OPERATOR_REPORT.md",
    "final_action_plan": "FINAL_ACTION_PLAN.json",
    "final_findings_index": "FINAL_FINDINGS_INDEX.json",
}


class SessionStateError(RuntimeError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(frozen=True)
class SessionArtifact:
    artifact_id: int
    name: str
    created_at: str
    session_id: str
    pending_count: int
    status: str
    temp_dir: Path
    state: dict[str, Any]


def fail(code: str, message: str) -> NoReturn:
    print(f"SAFE_STOP_CODE={code}", file=sys.stderr)
    print(message, file=sys.stderr)
    raise SystemExit(2)


def normalize_target_url(raw: str) -> str:
    raw = (raw or "").strip()
    if not raw:
        raise SessionStateError("TARGET_URL_REQUIRED", "target_url is required")

    parts = urllib.parse.urlsplit(raw)
    if parts.scheme.lower() not in {"http", "https"} or not parts.netloc:
        raise SessionStateError("TARGET_URL_INVALID", "target_url must be an absolute http/https URL")

    scheme = parts.scheme.lower()
    netloc = parts.netloc.lower()
    path = parts.path or "/"
    if not path.startswith("/"):
        path = "/" + path
    if len(path) > 1 and path.endswith("/"):
        path = path.rstrip("/")

    return urllib.parse.urlunsplit((scheme, netloc, path, "", ""))


def scope_key_for_target(normalized_target_url: str) -> str:
    return hashlib.sha256(normalized_target_url.encode("utf-8")).hexdigest()[:20]


def session_artifact_name(scope_key: str, session_id: str) -> str:
    return f"{SESSION_ARTIFACT_PREFIX}__{scope_key}__{session_id}"


def api_json(url: str, token: str) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "site-auditor-v3-session-state",
        },
    )
    try:
        with urllib.request.urlopen(request) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SessionStateError("GITHUB_API_ERROR", f"GitHub API request failed ({exc.code}): {body}") from exc


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Keep GitHub artifact redirects visible so the signed URL can be fetched cleanly."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[override]
        return None


def _download_redirect_target(redirect_url: str) -> bytes:
    signed_request = urllib.request.Request(
        redirect_url,
        headers={"User-Agent": "site-auditor-v3-session-state"},
    )
    try:
        with urllib.request.urlopen(signed_request) as response:
            return response.read()
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SessionStateError(
            "GITHUB_ARTIFACT_SIGNED_URL_ERROR",
            f"Signed artifact URL download failed ({exc.code}): {body}",
        ) from exc


def api_bytes(url: str, token: str) -> bytes:
    """Download a workflow artifact ZIP through GitHub's signed redirect flow."""

    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "site-auditor-v3-session-state",
        },
    )
    opener = urllib.request.build_opener(_NoRedirectHandler())

    try:
        with opener.open(request) as response:
            status = getattr(response, "status", response.getcode())
            if status in {301, 302, 303, 307, 308}:
                redirect_url = response.headers.get("Location")
                if not redirect_url:
                    raise SessionStateError(
                        "GITHUB_ARTIFACT_REDIRECT_MISSING",
                        "Artifact download endpoint returned a redirect without a Location header.",
                    )
                return _download_redirect_target(redirect_url)
            return response.read()
    except urllib.error.HTTPError as exc:
        if exc.code in {301, 302, 303, 307, 308}:
            redirect_url = exc.headers.get("Location")
            if not redirect_url:
                raise SessionStateError(
                    "GITHUB_ARTIFACT_REDIRECT_MISSING",
                    "Artifact download endpoint returned a redirect without a Location header.",
                ) from exc
            return _download_redirect_target(redirect_url)

        body = exc.read().decode("utf-8", errors="replace")
        raise SessionStateError("GITHUB_ARTIFACT_DOWNLOAD_ERROR", f"Artifact download failed ({exc.code}): {body}") from exc


def list_matching_artifacts(repo: str, token: str, scope_key: str) -> list[dict[str, Any]]:
    owner, name = repo.split("/", 1)
    prefix = f"{SESSION_ARTIFACT_PREFIX}__{scope_key}__"
    matches: list[dict[str, Any]] = []
    page = 1

    while True:
        payload = api_json(
            f"https://api.github.com/repos/{owner}/{name}/actions/artifacts?per_page=100&page={page}",
            token,
        )
        artifacts = payload.get("artifacts") or []
        for artifact in artifacts:
            artifact_name = str(artifact.get("name") or "")
            if artifact_name.startswith(prefix) and not artifact.get("expired", False):
                matches.append(artifact)
        if len(artifacts) < 100:
            break
        page += 1

    return matches


def read_state_from_artifact(artifact: dict[str, Any], token: str) -> SessionArtifact:
    artifact_id = int(artifact["id"])
    name = str(artifact["name"])
    created_at = str(artifact.get("created_at") or artifact.get("updated_at") or "")
    zip_bytes = api_bytes(str(artifact["archive_download_url"]), token)

    temp_dir = Path(tempfile.mkdtemp(prefix="site_auditor_v3_session_artifact_"))
    zip_path = temp_dir / "artifact.zip"
    zip_path.write_bytes(zip_bytes)

    with zipfile.ZipFile(zip_path) as archive:
        archive.extractall(temp_dir / "payload")

    state_path = temp_dir / "payload" / SESSION_STATE_FILE
    if not state_path.is_file():
        raise SessionStateError("SESSION_STATE_ARTIFACT_INVALID", f"{SESSION_STATE_FILE} missing in artifact {name}")

    state = json.loads(state_path.read_text(encoding="utf-8"))
    session_id = str(state.get("session_id") or "")
    if not session_id:
        raise SessionStateError("SESSION_STATE_ARTIFACT_INVALID", f"session_id missing in artifact {name}")

    pending_count = int(state.get("pending_count") or 0)
    status = str(state.get("status") or "UNKNOWN")

    return SessionArtifact(
        artifact_id=artifact_id,
        name=name,
        created_at=created_at,
        session_id=session_id,
        pending_count=pending_count,
        status=status,
        temp_dir=temp_dir,
        state=state,
    )


def latest_per_session(artifacts: Iterable[SessionArtifact]) -> list[SessionArtifact]:
    chosen: dict[str, SessionArtifact] = {}
    for artifact in artifacts:
        previous = chosen.get(artifact.session_id)
        if previous is None or artifact.created_at >= previous.created_at:
            chosen[artifact.session_id] = artifact
    return list(chosen.values())


def load_latest_matching_sessions(repo: str, token: str, scope_key: str) -> list[SessionArtifact]:
    artifact_records = list_matching_artifacts(repo, token, scope_key)
    extracted = [read_state_from_artifact(record, token) for record in artifact_records]
    return latest_per_session(extracted)


def write_github_output(path: str | None, values: dict[str, str]) -> None:
    if not path:
        for key, value in values.items():
            print(f"{key}={value}")
        return

    out_path = Path(path)
    with out_path.open("a", encoding="utf-8") as handle:
        for key, value in values.items():
            handle.write(f"{key}={value}\n")


def restore_ledger_from_artifact(chosen: SessionArtifact) -> Path:
    payload_root = chosen.temp_dir / "payload"
    ledger_source = payload_root / "sessions" / chosen.session_id / "AUDIT_SESSION_LEDGER.json"
    if not ledger_source.is_file():
        fail(
            "SESSION_STATE_NOT_RESTORABLE",
            f"Stored session artifact {chosen.name} does not contain the ledger for {chosen.session_id}.",
        )

    ledger_target = REPO_RUNS_SESSIONS / chosen.session_id / "AUDIT_SESSION_LEDGER.json"
    ledger_target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ledger_source, ledger_target)
    return ledger_target


def guard_start(args: argparse.Namespace) -> int:
    try:
        normalized_target = normalize_target_url(args.target_url)
    except SessionStateError as exc:
        fail(exc.code, exc.message)

    scope_key = scope_key_for_target(normalized_target)
    token = args.token or os.environ.get("GITHUB_TOKEN") or ""
    if not token:
        fail("GITHUB_TOKEN_REQUIRED", "GITHUB_TOKEN is required to check whether an audit session is already open")

    try:
        latest = load_latest_matching_sessions(args.repo, token, scope_key)
    except SessionStateError as exc:
        fail(exc.code, exc.message)

    open_sessions = [item for item in latest if item.status == "OPEN" and item.pending_count > 0]
    if open_sessions:
        session_ids = ", ".join(sorted(item.session_id for item in open_sessions))
        fail(
            "OPEN_SESSION_ALREADY_EXISTS_FOR_URL",
            f"An unfinished audit session already exists for this URL: {session_ids}. Use NEXT or FULL instead of START.",
        )

    print(f"START_GUARD_OK_TARGET_URL={normalized_target}")
    print("START_GUARD_OPEN_SESSIONS=0")
    write_github_output(
        args.github_output,
        {
            "scope_key": scope_key,
            "normalized_target_url": normalized_target,
        },
    )
    return 0


def restore_next(args: argparse.Namespace) -> int:
    try:
        normalized_target = normalize_target_url(args.target_url)
    except SessionStateError as exc:
        fail(exc.code, exc.message)

    scope_key = scope_key_for_target(normalized_target)
    token = args.token or os.environ.get("GITHUB_TOKEN") or ""
    if not token:
        fail("GITHUB_TOKEN_REQUIRED", "GITHUB_TOKEN is required to restore a prior audit session")

    try:
        latest = load_latest_matching_sessions(args.repo, token, scope_key)
    except SessionStateError as exc:
        fail(exc.code, exc.message)

    open_sessions = [item for item in latest if item.status == "OPEN" and item.pending_count > 0]
    completed_sessions = [
        item
        for item in latest
        if item.pending_count <= 0 or item.status in {"READY_FOR_FINAL", "FINALIZED", "COMPLETED"}
    ]

    if not open_sessions:
        if completed_sessions:
            fail(
                "SESSION_ALREADY_COMPLETED",
                "No unfinished audit session exists for this URL. The latest matching session is already completed/finalized. Run START for a new audit.",
            )
        fail(
            "NO_OPEN_SESSION_FOR_URL",
            "No unfinished audit session exists for this URL. Run START first.",
        )

    if len(open_sessions) > 1:
        session_ids = ", ".join(sorted(item.session_id for item in open_sessions))
        fail(
            "AMBIGUOUS_OPEN_SESSIONS_FOR_URL",
            f"More than one unfinished audit session exists for this URL: {session_ids}. Automatic NEXT is blocked.",
        )

    chosen = open_sessions[0]
    ledger_target = restore_ledger_from_artifact(chosen)

    print(f"RESTORED_SESSION_ID={chosen.session_id}")
    print(f"RESTORED_TARGET_URL={normalized_target}")
    print(f"RESTORED_PENDING_COUNT={chosen.pending_count}")
    print(f"RESTORED_LEDGER={ledger_target.as_posix()}")

    write_github_output(
        args.github_output,
        {
            "session_id": chosen.session_id,
            "scope_key": scope_key,
            "normalized_target_url": normalized_target,
            "pending_count": str(chosen.pending_count),
        },
    )
    return 0


def resolve_full(args: argparse.Namespace) -> int:
    try:
        normalized_target = normalize_target_url(args.target_url)
    except SessionStateError as exc:
        fail(exc.code, exc.message)

    scope_key = scope_key_for_target(normalized_target)
    token = args.token or os.environ.get("GITHUB_TOKEN") or ""
    if not token:
        fail("GITHUB_TOKEN_REQUIRED", "GITHUB_TOKEN is required to resolve FULL session state")

    try:
        latest = load_latest_matching_sessions(args.repo, token, scope_key)
    except SessionStateError as exc:
        fail(exc.code, exc.message)

    open_sessions = [item for item in latest if item.status == "OPEN" and item.pending_count > 0]
    if len(open_sessions) > 1:
        session_ids = ", ".join(sorted(item.session_id for item in open_sessions))
        fail(
            "AMBIGUOUS_OPEN_SESSIONS_FOR_URL",
            f"More than one unfinished audit session exists for this URL: {session_ids}. Automatic FULL is blocked.",
        )

    if not open_sessions:
        print("FULL_ENTRY_ACTION=START")
        print(f"FULL_TARGET_URL={normalized_target}")
        write_github_output(
            args.github_output,
            {
                "entry_action": "START",
                "session_id": "",
                "scope_key": scope_key,
                "normalized_target_url": normalized_target,
                "pending_count": "0",
            },
        )
        return 0

    chosen = open_sessions[0]
    ledger_target = restore_ledger_from_artifact(chosen)

    print("FULL_ENTRY_ACTION=NEXT")
    print(f"FULL_RESTORED_SESSION_ID={chosen.session_id}")
    print(f"FULL_RESTORED_PENDING_COUNT={chosen.pending_count}")
    print(f"FULL_RESTORED_LEDGER={ledger_target.as_posix()}")

    write_github_output(
        args.github_output,
        {
            "entry_action": "NEXT",
            "session_id": chosen.session_id,
            "scope_key": scope_key,
            "normalized_target_url": normalized_target,
            "pending_count": str(chosen.pending_count),
        },
    )
    return 0


def _final_artifacts_from_report(report: dict[str, Any]) -> dict[str, str]:
    finalization = report.get("finalization") or {}
    artifacts = finalization.get("artifacts") or {}
    return {
        key: str(artifacts.get(key) or "")
        for key in FINAL_ARTIFACT_KEYS
        if str(artifacts.get(key) or "")
    }


def publish_state(args: argparse.Namespace) -> int:
    try:
        normalized_target = normalize_target_url(args.target_url)
    except SessionStateError as exc:
        fail(exc.code, exc.message)

    report_path = Path(args.run_report)
    if not report_path.is_file():
        fail("RUN_REPORT_NOT_FOUND", f"RUN_REPORT not found: {report_path}")

    report = json.loads(report_path.read_text(encoding="utf-8"))
    audit_session = report.get("audit_session") or {}
    finalization = report.get("finalization") or {}
    session_id = str(audit_session.get("session_id") or "")
    if not session_id:
        fail("SESSION_ID_MISSING", "RUN_REPORT.audit_session.session_id is missing")

    ledger_path = REPO_RUNS_SESSIONS / session_id / "AUDIT_SESSION_LEDGER.json"
    if not ledger_path.is_file():
        fail("LEDGER_NOT_FOUND", f"Session ledger missing after run: {ledger_path}")

    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    pending_count = len(ledger.get("pending_urls") or [])
    finalization_status = str(finalization.get("status") or ledger.get("finalization_status") or "")
    status = "OPEN" if pending_count > 0 else ("FINALIZED" if finalization_status == "FINALIZED" else "READY_FOR_FINAL")
    scope_key = scope_key_for_target(normalized_target)
    artifact_name = session_artifact_name(scope_key, session_id)
    final_artifacts = _final_artifacts_from_report(report)

    out_dir = Path(args.out_dir)
    if out_dir.exists():
        shutil.rmtree(out_dir)
    state_root = out_dir / artifact_name
    ledger_target = state_root / "sessions" / session_id / "AUDIT_SESSION_LEDGER.json"
    ledger_target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ledger_path, ledger_target)
    shutil.copy2(report_path, state_root / LATEST_RUN_REPORT_FILE)

    state = {
        "schema_version": "1.1",
        "artifact_name": artifact_name,
        "scope_key": scope_key,
        "normalized_target_url": normalized_target,
        "session_id": session_id,
        "status": status,
        "pending_count": pending_count,
        "total_audited_count": int(audit_session.get("total_audited_count") or 0),
        "total_pending_count": int(audit_session.get("total_pending_count") or pending_count),
        "coverage_percent": float(audit_session.get("coverage_percent") or 0),
        "next_action": str(audit_session.get("next_action") or "UNKNOWN"),
        "run_id": str(report.get("run_id") or ""),
        "ledger_relative_path": f"sessions/{session_id}/AUDIT_SESSION_LEDGER.json",
        "latest_run_report": LATEST_RUN_REPORT_FILE,
        "finalization_status": finalization_status or None,
        "final_artifacts": final_artifacts,
    }
    (state_root / SESSION_STATE_FILE).write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")

    print(f"SESSION_STATE_ARTIFACT_NAME={artifact_name}")
    print(f"SESSION_STATE_ARTIFACT_PATH={state_root.as_posix()}")
    print(f"SESSION_STATE_STATUS={status}")
    print(f"SESSION_STATE_PENDING_COUNT={pending_count}")
    print(f"SESSION_STATE_FINALIZATION_STATUS={finalization_status or 'NOT_FINALIZED'}")

    write_github_output(
        args.github_output,
        {
            "artifact_name": artifact_name,
            "artifact_path": state_root.as_posix(),
            "session_status": status,
            "pending_count": str(pending_count),
            "finalization_status": finalization_status or "NOT_FINALIZED",
        },
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Site Auditor V3 workflow session-state helper")
    subparsers = parser.add_subparsers(dest="command", required=True)

    guard = subparsers.add_parser("guard-start", help="Block START when an unfinished session already exists for target_url")
    guard.add_argument("--target-url", required=True)
    guard.add_argument("--repo", required=True, help="owner/repo")
    guard.add_argument("--token", default="")
    guard.add_argument("--github-output", default="")
    guard.set_defaults(func=guard_start)

    restore = subparsers.add_parser("restore-next", help="Restore one open session for target_url before NEXT")
    restore.add_argument("--target-url", required=True)
    restore.add_argument("--repo", required=True, help="owner/repo")
    restore.add_argument("--token", default="")
    restore.add_argument("--github-output", default="")
    restore.set_defaults(func=restore_next)

    resolve = subparsers.add_parser("resolve-full", help="Resolve whether FULL starts fresh or resumes one open session")
    resolve.add_argument("--target-url", required=True)
    resolve.add_argument("--repo", required=True, help="owner/repo")
    resolve.add_argument("--token", default="")
    resolve.add_argument("--github-output", default="")
    resolve.set_defaults(func=resolve_full)

    publish = subparsers.add_parser("publish", help="Prepare a session-state artifact after START/NEXT/FULL batch runs")
    publish.add_argument("--target-url", required=True)
    publish.add_argument("--run-report", required=True)
    publish.add_argument("--out-dir", required=True)
    publish.add_argument("--github-output", default="")
    publish.set_defaults(func=publish_state)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
