# AGENTS.md

## Purpose
Execution discipline for work inside `e-factory-agent`.

## Active AGENTOPS line
- Active build/test focus: `agents/site_auditor_v3/`
- Product target: universal audit engine
- Current website audits are an execution lane, not the whole product definition
- Current next universal product pack after merged repair-execution proof: selected from the agent's next capability truth, not guessed manually

## Architecture law
- `run.ps1` = orchestrator only
- owner logic lives in `modules/`, `lib/`, `tools/`, and explicit contracts
- no blind refactor
- no hidden fallback that fabricates truth
- artifact/report truth outranks memory and speculation

## Operator run modes
The GitHub Actions operator surface is intentionally simple:
- `START`
- `NEXT`
- `FULL`

The operator chooses intent.
Session IDs, restore mechanics, batch state, and ledger transport remain internal.

## Current proven contour
SITE_AUDITOR_V3 already proves:
- long-run FULL orchestration
- bounded batch continuation
- session ledger continuity
- 100% session finalization
- final aggregate/operator/action outputs
- self-build truth alignment
- capability discovery selecting the next universal pack
- repair execution planning layer producing safe PLAN_ONLY repair artifacts after finalization

## Serial execution discipline
The default operating mode is **series, not drip-feed**.

When the next move is sufficiently bounded and the tools allow execution:
1. plan the whole safe batch first;
2. execute the full batch without stopping for routine status updates;
3. validate every completed tranche;
4. continue through recoverable defects when the next repair is still inside the same approved scope;
5. stop only on a real gate: missing artifact, scope expansion, permission boundary, destructive action, or root-cause uncertainty that blocks safe continuation.

Do not waste owner time with:
- pull repo -> report -> wait;
- patch one file -> report -> wait;
- run one validator -> report -> wait;
- asking for confirmation when the scope, contract, and validation gate are already clear.

## Tool role discipline
Choose the tool by execution role.

### ChatGPT / Project Lead
Use for:
- selecting the bottleneck;
- defining the execution pack;
- deciding the tool split;
- reviewing artifacts and fail reports;
- cutting weak branches of work.

### Codex
Use for:
- bounded repo changes when the root cause and scope are known;
- multi-step implementation packs that begin with plan-first reasoning and then execute the fixed plan;
- producing `TASK_REPORT.md` / equivalent change report with completed, failed, and deferred items.

Codex tasks must be explicit:
- READ FIRST
- OBJECTIVE
- EXECUTION PLAN
- SCOPE
- FILES ALLOWED
- FORBIDDEN
- VALIDATION
- CONTINUE-ON-SAFE-FAIL RULE
- EXPECTED REPORT

### CodeSpace / terminal execution
Use for:
- diagnostics;
- environment proof;
- workflow/full-loop runs;
- shell-based validation batches;
- artifact collection.

Terminal blocks should run as a coherent diagnostic/validation sweep, not as single isolated commands unless one narrow proof is the only task.

### GitHub / repo tooling
Use for:
- branch creation;
- bounded file rewrites;
- PR creation;
- PR comments with proof;
- merge after evidence.

Do not delay a safe repo-documentation or proof-comment action into another turn when it can be closed now.

## Serial pack contract
Every non-trivial execution pack should define:
- batch goal;
- allowed scope;
- forbidden scope;
- tranche list;
- validation after each tranche or at the final gate;
- continuation rule for recoverable failures;
- hard stop conditions;
- final report shape.

A pack may contain 5, 10, or more tightly related steps if they serve one bottleneck and stay inside one layer.

## Output truth
A useful run must produce either:
- usable result; or
- explicit diagnostic output.

## Forbidden drift
- treating website fixture runs as the product boundary
- promoting target-specific findings into the universal product roadmap
- reviving legacy paths as active truth
- permanent tracked task-report clutter
- broad refactor under a cleanup label
- green-run claims without evidence
- unnecessary turn-by-turn bureaucracy when a safe serial execution pack is available
