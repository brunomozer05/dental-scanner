# Automation Inbox

Recurring code-health automation writes here only when it finds a meaningful new issue that is not already represented by an existing report or GitHub Issue.

Use:

```text
YYYY-MM-DD_no-issue_code-health-audit.md
YYYY-MM-DD_issue-N_code-health-audit.md
```

Reports are append-only. They inspect `main`, cite the exact inspected commit, and never modify production code from this branch.

Use `ai/templates/code_health_audit.md`.
