# SERIAL_EXECUTION_PROTOCOL — AGENTOPS

## Purpose
Replace turn-by-turn operational bureaucracy with bounded serial execution packs.

The project lead should not operate like:

```text
sync repo -> report -> wait
one patch -> report -> wait
one validation -> report -> wait
```

The default mode is:

```text
select one bottleneck
→ build one serial execution pack
→ execute the full safe series
→ validate in-batch
→ return one consolidated result or fail-report
```

## Core rule
If a connected body of useful work can be completed safely in one session without losing accuracy, close it in one session.

This protocol is a working method for AGENTOPS execution. It does not weaken artifact-first truth, root-cause-first diagnosis, or scope control.

## Serial pack eligibility
Use a serial pack when all conditions hold:
1. one bottleneck is already selected;
2. root cause is known or the pack is explicitly a diagnostic sweep;
3. the allowed scope is bounded;
4. validation gates are known;
5. the chosen tool can execute more than one related action safely.

Do **not** use a serial pack when:
- the necessary artifact has not been inspected;
- the bottleneck is not selected;
- the task mixes unrelated layers;
- destructive action requires owner approval;
- repo or environment truth is uncertain enough to block safe continuation.

## Tool choice
### ChatGPT / Project Lead
Owns:
- bottleneck selection;
- serial pack design;
- tool split;
- stop/go decision after evidence.

### Codex
Use for known-scope repo work that benefits from plan-first execution.

Codex should receive:
1. **READ FIRST**
2. **OBJECTIVE**
3. **EXECUTION MODE: PLAN → EXECUTE**
4. **BATCH SCOPE**
5. **FILES ALLOWED**
6. **FORBIDDEN**
7. **SERIAL TASKS**
8. **VALIDATION**
9. **CONTINUE-ON-SAFE-FAIL RULE**
10. **TASK_REPORT.md EXPECTATION**

Codex should:
- first write a short internal implementation plan;
- execute that plan without asking for intermediate approval;
- continue across recoverable defects inside the same scope;
- stop only on an explicit hard gate;
- return one report with:
  - completed tasks;
  - failed tasks;
  - skipped/deferred tasks;
  - validation results;
  - files changed.

## CodeSpace / terminal serial sweep
Use when truth must be produced by execution.

A terminal serial sweep may include:
- repo sync;
- branch checkout;
- parser/lint guard;
- targeted tests;
- FULL workflow run;
- artifact listing;
- extraction of key proof markers.

The block should:
- continue through non-fatal diagnostics;
- preserve full output;
- print explicit PASS / FAIL markers;
- avoid aborting early unless continuing would corrupt the result.

## GitHub serial use
When evidence already closes a gate, GitHub work should also be batched:
- comment proof into PR;
- merge if proof satisfies the declared gate;
- open the next branch when the next bottleneck is already decided;
- sync docs/truth if the same proof changes status.

Do not split safe GitHub admin into several turns.

## Serial pack shape
Every pack should state:

```text
PACK GOAL:
ONE BOTTLENECK:
EXECUTION MODE:
TOOL:
READ FIRST:
SERIAL TASKS:
VALIDATION:
CONTINUE IF:
STOP IF:
FINAL REPORT:
```

## Continue-on-safe-fail rule
A pack may continue after a defect if:
- the defect is inside the same selected bottleneck;
- a bounded fix is obvious from evidence;
- continuing does not expand scope;
- the next step produces more truth, not noise.

A pack must stop if:
- root cause becomes uncertain;
- the required artifact is absent;
- permission / destructive boundary is hit;
- the next repair would change layer or product scope.

## Acceptance standard
Serial execution is successful only when the final output is one of:
1. a completed verified pack;
2. a consolidated fail-report that pinpoints exactly what completed, what failed, and the next strongest move.

## Anti-bureaucracy examples
### Weak
```text
Run test A. Send log.
Now run test B. Send log.
Now patch file C. Send diff.
```

### Strong
```text
Run full diagnostic sweep:
1. sync branch;
2. run parser guard;
3. run targeted validators;
4. run FULL proof;
5. extract proof markers;
6. if validator A fails with already-known bounded contract drift, patch the named file and rerun the same validation once;
7. return one consolidated report.
```

## Current project use
This protocol is active for:
- capability packs;
- proof sweeps;
- bounded repair sequences;
- repo/docs truth sync after proven milestones.

It is not a license for blind refactor or speculative multi-layer work.
