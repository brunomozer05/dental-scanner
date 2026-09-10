# DentalScanner AI Automation Lanes

This document defines recurring automation that can feed the AI Intelligence Bridge without changing production behavior.

## 1. Deterministic Quality Watchdog

Deterministic CI belongs on normal GitHub Actions attached to `main`/pull requests. It should not require an LLM or write hypotheses into the intelligence branch.

Typical checks:

- Apple unit tests;
- simulator/app build as appropriate;
- iphoneos unsigned build where cost is justified;
- deterministic replay fixtures;
- schema/fixture integrity;
- forbidden-artifact checks;
- explicit invariant tests for safety-critical feature flags and production behavior.

A failing deterministic check is evidence. It should fail CI directly rather than being summarized as an AI opinion.

## 2. AI Code Health Audit

A recurring reasoning audit inspects the latest `main`, recent commits/PRs, tests, current Issues and CI results for likely bugs, stale assumptions, missing tests, mathematical inconsistencies, unit/coordinate mistakes, regressions and risky logic.

It is read-only with respect to production.

When a meaningful new finding exists, publish a new report under:

```text
ai/inbox/automation/YYYY-MM-DD_no-issue_code-health-audit.md
```

Use `ai/templates/code_health_audit.md`.

Do not publish a report merely to say that nothing changed. No finding is better than inbox noise.

The audit never creates a production fix directly. The Orchestrator decides whether the finding becomes a GitHub Issue.

## 3. Precision Technology Radar

A recurring research pass searches recent high-quality literature, official documentation and reputable open-source work relevant to DentalScanner precision.

Priority topics include:

- planar fiducial pose ambiguity;
- corner/subpixel localization;
- camera calibration and distortion;
- uncertainty/covariance and observability;
- viewpoint/frame selection;
- bundle adjustment and robust optimization;
- rolling shutter, focus and motion blur;
- marker fabrication/metrology;
- synthetic ground-truth benchmarking;
- repeatability, reproducibility and trueness.

When a finding is both new and plausibly relevant to the current architecture, publish:

```text
ai/inbox/research/YYYY-MM-DD_no-issue_precision-radar.md
```

Use `ai/templates/precision_radar.md`.

Do not recommend a technique because it is fashionable or AI-based. Every item must map to a current DentalScanner failure mode, measurable hypothesis and smallest useful offline experiment.

## Source of truth

All automation inspects the latest `main`. `ai/intelligence` remains an inbox and must never be treated as proof of current production behavior.

Priority remains:

1. current code/tests;
2. validated physical/metrology evidence;
3. current Issues/accepted specs;
4. orchestrator synthesis;
5. raw automated reports.
