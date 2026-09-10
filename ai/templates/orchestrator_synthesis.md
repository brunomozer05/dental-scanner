# Orchestrator Synthesis Template

```text
AGENT_ROLE: orchestrator
DATE_UTC: YYYY-MM-DD
REPOSITORY: brunomozer05/dental-scanner
BRANCH_INSPECTED:
COMMIT_INSPECTED:
RELATED_ISSUE: #N | none
REPORT_STATUS: complete
```

# INPUT REPORTS

List the exact Research and Red Team report paths consumed, plus relevant Issues/specs/artifacts.

# SUPPORTED FINDINGS

Findings that survive cross-checking against current code/tests/evidence.

# REJECTED OR WEAK CLAIMS

Claims rejected, contradicted, stale, or insufficiently evidenced. Explain why.

# UNRESOLVED QUESTIONS

Questions that still need experiment, physical data, or code inspection.

# DECISION

Choose the next project action and why it has the best evidence/risk/cost tradeoff.

# ISSUE ACTION

State one of:

```text
NO_ISSUE_CHANGE
CREATE_ISSUE
UPDATE_ISSUE
CLOSE_AS_RESOLVED
DEFER
```

Include the exact Issue number when applicable.

# RECOMMENDED CODEX SCOPE

Describe only the approved implementation scope, non-goals, critical invariants, and done condition.

# CODEX EFFORT

Choose one:

```text
NORMAL
HIGH
ULTRA
```

Use ULTRA only for genuinely complex multi-file mathematical/architectural work.

# VALIDATION GATE

Define required tests/CI/offline replay/shadow/physical validation before promotion.
