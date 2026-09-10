# Red Team Report Template

```text
AGENT_ROLE: red-team
DATE_UTC: YYYY-MM-DD
REPOSITORY: brunomozer05/dental-scanner
BRANCH_INSPECTED:
COMMIT_INSPECTED:
RELATED_ISSUE: #N | none
REPORT_STATUS: complete
```

# TARGET

State the Issue, plan, proposed experiment, Codex brief, PR, or claim being reviewed.

# CURRENT CODE CHECK

Verify whether the stated problem still exists in current production code. Record exact files/symbols/commits inspected.

# CONFIRMED

Claims supported by current code, tests, physical evidence, or authoritative documentation.

# CONTRADICTIONS

List stale assumptions, recent commits that invalidate the plan, conflicting specs, or evidence that points in another direction.

# MATHEMATICAL / GEOMETRIC REVIEW

When relevant, verify:

- coordinate frames;
- transform direction/composition;
- mm vs px vs radians;
- frame identity;
- gauge/connectivity;
- determinism;
- no unjustified M0 special case;
- no Euler-based reasoning for SE(3) geometry.

# RISKS

Concrete failure modes, side effects, regressions, hidden coupling, or unsafe promotion paths.

# MISSING EVIDENCE

What is not yet known and what evidence would resolve it.

# MISSING TESTS

Tests or fixtures required before implementation/merge.

# SIMPLER ALTERNATIVE

Look for a smaller offline experiment or narrower change that could answer the question before accepting new architecture.

# REQUIRED CHANGES

Changes needed in the Issue, plan, acceptance criteria, or Codex brief.

# VERDICT

Choose exactly one:

```text
APPROVE
REVISE
BLOCK
```

Explain the decision briefly.

# CODEX BRIEF

Only when `VERDICT: APPROVE`, provide a short implementation brief referencing the GitHub Issue and repository instructions. Do not duplicate the entire Issue/spec.
