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

It must not:
- invent findings
- hide weak coverage
- replace evidence files
- become a vague summary
