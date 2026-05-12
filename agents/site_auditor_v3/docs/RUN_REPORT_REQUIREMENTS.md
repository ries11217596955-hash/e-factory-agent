# RUN_REPORT_REQUIREMENTS

RUN_REPORT.json is the first file to read in every runpack.

It must guide:
- human operator
- ChatGPT/operator assistant
- agent itself

It must include:
- identity
- mission
- current run status
- read order
- if_problem_then_read map
- pipeline status
- audit result
- evidence summary
- diagnostic summary
- capability state
- one next step
- forbidden steps
- operator control / re-entry guidance
- tool recommendation for the next move
- reason for that tool recommendation

Tool recommendation must be explicit enough to answer:
- should the next move be terminal/runtime verification?
- should it be a direct local patch?
- should it be a bounded Codex task?
- should execution stop until artifacts are inspected?

If the next move depends on the Windows execution contour, RUN_REPORT should point the operator to:
- `agents/site_auditor_v3/docs/EXECUTION_CONTOUR.md`

It must not:
- invent findings
- hide weak coverage
- replace evidence files
- become a vague summary
- claim a tool is appropriate without a stated reason
