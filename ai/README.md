# DentalScanner AI Intelligence Bridge

This branch is a research/review inbox for AI agents. It is **not** production truth, the executable backlog, or a branch that should be merged automatically into `main`.

## Purpose

The branch connects three roles:

1. **Research / Geometry & Metrology** writes technical investigations to `ai/inbox/research/`.
2. **Reviewer / Red Team** writes independent reviews to `ai/inbox/red-team/`.
3. **Main / Orchestrator** reads both, checks them against current code/tests/issues/physical evidence, and writes accepted syntheses to `ai/synthesized/`.

Codex should normally receive only promoted GitHub Issues/specs plus a short implementation brief, not the entire raw inbox.

## Canonical source hierarchy

For executable decisions, prefer:

1. current production code and tests;
2. validated physical/metrology evidence;
3. current GitHub Issues and accepted specs;
4. accepted orchestrator synthesis;
5. raw agent reports.

Raw reports may contain hypotheses, mistakes, stale assumptions, or contradictory findings.

## Branch rules

- Do not modify production code in this branch.
- Do not copy `_local_reference/`, scans, STLs, NDJSON, credentials, private URLs, models, binaries, or sensitive artifacts here.
- Do not merge this branch automatically into `main`.
- Research and Red Team should normally **append a new report file**, not edit another agent's report.
- The Orchestrator owns `ai/synthesized/`.
- Every factual claim must distinguish `EVIDENCE`, `INFERENCE`, and `HYPOTHESIS` where applicable.
- Link the related GitHub Issue when one exists.
- Include exact repository commit/ref inspected.
- Prefer small focused reports over giant notebooks.
- A report is not an implementation authorization.

## File naming

Use lowercase ASCII slugs and UTC date:

```text
ai/inbox/research/YYYY-MM-DD_issue-N_short-topic.md
ai/inbox/red-team/YYYY-MM-DD_issue-N_short-topic.md
ai/synthesized/YYYY-MM-DD_issue-N_decision.md
```

If no Issue exists yet, use:

```text
YYYY-MM-DD_no-issue_short-topic.md
```

If a same-day filename already exists, append `_02`, `_03`, etc. Never overwrite another report.

## Required metadata header

Every report starts with:

```text
AGENT_ROLE:
DATE_UTC:
REPOSITORY:
BRANCH_INSPECTED:
COMMIT_INSPECTED:
RELATED_ISSUE:
REPORT_STATUS: draft | complete | superseded
```

## Promotion gate

A finding is promoted to the executable backlog only after the Main / Orchestrator checks:

- current code;
- tests and recent commits;
- mathematical conventions and units when relevant;
- supporting evidence;
- contradictions from the Red Team;
- whether a simpler experiment can answer the question first.

Promoted work belongs in GitHub Issues. Durable design contracts belong in specs. Production code belongs on normal implementation branches/PRs, never here.
