# Research Report Template

```text
AGENT_ROLE: research
DATE_UTC: YYYY-MM-DD
REPOSITORY: brunomozer05/dental-scanner
BRANCH_INSPECTED:
COMMIT_INSPECTED:
RELATED_ISSUE: #N | none
REPORT_STATUS: complete
```

# RESEARCH QUESTION

State one focused technical question.

# CURRENT DENTALSCANNER BEHAVIOR

Describe only what current code/tests/artifacts support. Cite exact files/symbols/commits.

# EVIDENCE FROM LITERATURE / DOCUMENTATION

For each important source, record:

- source/title;
- date/version;
- relevant finding;
- why it applies or may not apply to DentalScanner.

Prefer papers, official OpenCV/Ceres/Apple docs, standards, and reputable open-source implementations.

# MATHEMATICAL IMPLICATION

Explicitly state coordinate systems, transformation direction, units, rotation convention, assumptions, and equations when relevant.

# EVIDENCE

Directly supported findings.

# INFERENCE

Reasonable conclusions derived from evidence.

# HYPOTHESIS

Ideas not yet experimentally confirmed.

# POTENTIAL BENEFIT

Explain what measurable failure mode could improve. Do not equate lower reprojection or a visually better STL with trueness.

# RISKS / FAILURE MODES

List conditions where the technique can fail, become unobservable, bias results, or create regressions.

# PROPOSED OFFLINE EXPERIMENT

Prefer the smallest deterministic experiment that could falsify or support the hypothesis before live integration.

# SUCCESS METRIC

Define measurements before the experiment. Distinguish internal stability, repeatability, reproducibility, and trueness.

# REPOSITORY IMPACT

List likely files/modules affected if the experiment is later approved. Do not implement here.

# OPEN QUESTIONS

Unknowns that still need code inspection, physical evidence, or literature.

# RECOMMENDATION

Choose exactly one:

```text
INVESTIGATE
EXPERIMENT
DEFER
REJECT
```

Explain why in 2-5 sentences.

# PROPOSED ISSUE CHANGE

If useful, propose concise text for a new Issue or amendment to an existing Issue. Do not create/modify Issues unless explicitly asked.
