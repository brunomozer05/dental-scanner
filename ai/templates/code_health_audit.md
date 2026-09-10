# Automated Code Health Audit Template

```text
AGENT_ROLE: automation-code-health
DATE_UTC: YYYY-MM-DD
REPOSITORY: brunomozer05/dental-scanner
BRANCH_INSPECTED: main
COMMIT_INSPECTED:
PREVIOUS_COMMIT_COMPARED: <sha | unavailable>
RELATED_ISSUE: #N | none
REPORT_STATUS: complete
```

# AUDIT SCOPE

State which commits, PRs, modules, tests and CI results were inspected.

# NEW FINDINGS

For each finding use:

```text
SEVERITY: P0 | P1 | P2 | P3
CONFIDENCE: high | medium | low
CATEGORY: correctness | geometry | units | concurrency | persistence | export | camera | tests | performance | security | tooling | other
```

Then provide:

- exact file/symbol;
- observed behavior;
- why it may be wrong;
- evidence;
- likely impact;
- minimal reproduction or falsification test;
- existing Issue/report overlap.

# EVIDENCE

Only directly supported facts from current code/tests/CI/commits.

# INFERENCE

Reasonable consequences of the evidence.

# HYPOTHESIS

Unverified explanations.

# MATHEMATICAL / DATA-CONTRACT CHECK

When applicable verify explicitly:

- transform direction and composition;
- coordinate frame identity;
- mm / px / rad units;
- frame identity and ordering;
- gauge/connectivity;
- deterministic ordering;
- finite/SO(3) assumptions;
- schema and backward compatibility.

# TEST GAPS

Tests that would have detected the finding earlier.

# EXISTING ISSUE COVERAGE

State whether each finding is already covered by an open Issue. Do not duplicate work.

# RECOMMENDED ACTION

Choose for each finding:

```text
PROMOTE_TO_ORCHESTRATOR
MONITOR
ALREADY_TRACKED
DISMISS
```

Do not implement fixes and do not edit GitHub Issues from this report.

# NOISE RULE

If there is no meaningful new finding, do not create a report file.
