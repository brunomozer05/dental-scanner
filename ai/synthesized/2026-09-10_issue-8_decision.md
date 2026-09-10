AGENT_ROLE: orchestrator
DATE_UTC: 2026-09-10
REPOSITORY: brunomozer05/dental-scanner
BRANCH_INSPECTED: main
COMMIT_INSPECTED: 4b223ae57627ee316191e03cddde8fd8a580a097
RELATED_ISSUE: #8
REPORT_STATUS: complete

# INPUT REPORTS

- `ai/inbox/research/2026-09-10_issue-8_metrology-validation-protocol.md`
- `ai/inbox/red-team/2026-09-10_issue-8_metrology-protocol.md`
- GitHub Issue #8
- GitHub Issue #10
- GitHub Issue #19
- `AGENTS.md`
- `specs/15_validation_protocol_and_accuracy.md`
- `DentalScanner/ScannerMVP/Replay/ScanSessionReplaySTLComparisonExporter.swift`
- `DentalScannerTests/ScanSessionReplaySTLComparisonTests.swift`
- External validation against BIPM/JCGM VIM, JCGM GUM publication set, ISO 20896-1:2019, ISO/TR 20896-2:2023, ISO 5725-1:2023, ISO 5725-2:2025, ISO 5725-4:2020, NIST 4:1 TUR historical guidance, and published dental-scanner literature.

# SUPPORTED FINDINGS

1. The need for Issue #8 is confirmed. Current `main` has deterministic replay and anchor-independent relative-geometry diagnostics but no calibrated ground-truth input, traceable reference-value uncertainty, bias/trueness model, or uncertainty budget. Existing app-vs-app replay/STL comparison cannot establish absolute dimensional correctness.

2. The metrology terminology in the reports is substantially correct. VIM distinguishes repeatability, intermediate precision, reproducibility, trueness and measurement precision; trueness itself is not a numerical quantity. Signed bias/error should be reported instead of calling a scalar value `trueness`.

3. ISO 20896-1:2019 is a relevant methodological reference because it explicitly concerns hand-held dental digital-impression devices and independently measured dimensions of interest. The 2019 edition remains current in 2026 while a replacement edition is under development. ISO/TR 20896-2:2023 is directly relevant to later implant-body/implant-pose validation. Neither document should be represented as automatic DentalScanner compliance.

4. Pairwise marker-origin distances are a strong first bench measurand because they are invariant to an arbitrary common rigid output transform and are already natural to the current DentalScanner output. Current tests independently confirm rebase/global-transform invariance of pairwise geometry.

5. The current `n >= 10` requirement is adequate only as a pilot, not as strong evidence for a P95 gate. The research report's calculation is correct: with n=10, the probability of observing at least one sample above the population P95 is only about 40.1%; n=59 raises that probability just above 95%. This does NOT mean 59 is automatically sufficient to estimate P95 accurately; final sample size must follow the intended statistical claim and confidence/tolerance-interval method.

6. External standards/literature reinforce the sample-size concern. Publicly available text of ISO 20896-1 reports a 30-scan procedure for its own accuracy test method. DentalScanner is not being declared compliant with that standard, but this is additional evidence that 10 scans should not be treated as a confirmatory tail-accuracy study.

7. The reports are correct that reference uncertainty matters. JCGM/GUM and conformity-assessment principles do not support treating a nominal reference value as exact. A reference system described only as `better than 100 um` is underspecified.

8. The proposed `U_ref(k≈2) <= 25 um` target is reasonable as a conservative project-design objective for a 100 um linear-error goal, and the reports correctly classify it as an engineering target rather than an ISO/JCGM requirement. NIST's 4:1 TUR material is historical guidance, not a universal rule.

9. The proposed guarded rule `|estimated bias| + U <= 0.100 mm` is reasonable only for a predeclared mean-bias claim. It does not prove that 95% of individual scans are within 100 um, does not prove surface accuracy, and does not prove implant-axis/location accuracy.

10. Surface STL metrics must remain secondary until comparison direction, overlap mask, datum/registration policy and reference uncertainty are frozen. Published dental-scanner work confirms that changing which mesh is treated as reference/test can materially change reported trueness metrics.

11. Failed/export-incomplete/disconnected scans must remain visible in the denominator/failure statistics. Excluding them after acquisition would create selection bias.

# REJECTED OR WEAK CLAIMS

1. Do not automatically label a same-device/same-operator fixture remount as `intermediate precision`. The safest project term is `remount/reassembly robustness study`. It may be classified as intermediate precision only when the complete changed/unchanged conditions satisfy the chosen VIM study definition, including the time/condition design. Likewise it is not full reproducibility merely because the fixture was remounted.

2. Do not promote `~60 scans` into a universal final requirement. The n=59 calculation only establishes a tail-observation probability result. A P95 release claim requires a predeclared estimator/tolerance or confidence interval and a sample-size calculation tied to that method.

3. Do not treat the six marker-pair distances as six independent statistical replicates. They share four estimated marker poses and common reference geometry. They can be six separate measurands, but the physical scan/session is the primary replication unit and covariance may matter.

4. Do not assume a CMM can directly provide the DentalScanner ArUco marker origin merely by measuring a holder. The virtual marker coordinate origin must be physically realized or tied to measurable datums with a characterized transform and uncertainty. Print scale, corner/edge realization, lamination, cutting and mounting can otherwise dominate the desired 100 um budget.

5. Pairwise marker-origin distance is not the final clinical claim. It is an excellent stage-1 diagnostic for dimensional geometry. If implant center/axis is the actual product target, a later reference must characterize the marker-to-implant transform and 3D position/orientation measurands; ISO/TR 20896-2 is relevant there.

# UNRESOLVED QUESTIONS

- Exact primary product claim: mean marker-pair bias, individual-scan error, implant-center error, implant-axis error, or surface deviation.
- Physical fixture design/material and how marker coordinate origins will be realized for metrology.
- Available reference laboratory/method and achievable uncertainty for those exact measurands.
- Whether all six marker pairs are equally critical or whether specific/long-baseline pairs should be predeclared as primary.
- Final statistical claim and sample-size method for any P95/tolerance requirement.
- Environmental/thermal contribution for the selected fixture material and dimensions.
- Later mapping from marker-frame metrology to clinically relevant implant geometry.

# DECISION

Issue #8 should be revised and advanced in parallel, but no production scanner code should change for it yet.

The best next metrology step is a measurement-contract/fixture-design phase, not a generalized STL comparator and not another optimizer. Define the measurands, physical datums, reference uncertainty representation, failure handling and decision rule before collecting confirmatory scans.

Recommended sequence:

- Phase 8A: measurement contract + fixture/reference design, no scanner behavior change.
- Phase 8B: n=10 pilot under strict fixed conditions to validate procedure/tooling and estimate gross bias/repeatability.
- Phase 8C: confirmatory study with sample size chosen from the final statistical claim; P95 remains descriptive until this design is fixed.
- Phase 8D: remount/reassembly robustness as a separately named study.
- Phase 8E: broader intermediate-precision/reproducibility factors only after the baseline is understood.
- Phase 8F: implant/surface metrology after scalar marker-geometry ground truth is working.

# ISSUE ACTION

UPDATE_ISSUE #8

Refine the Issue to:

- define pairwise marker-origin distances as the first-stage candidate measurands, conditional on physical realization of the marker origins;
- require per-measurand reference value and uncertainty, method/date/provenance and datum-realization description;
- make n=10 explicitly pilot-only;
- prohibit a P95 pass/fail claim without predeclared sample-size/confidence/tolerance method;
- rename the simple remount test to remount/reassembly robustness;
- preserve signed errors and failure-rate accounting;
- keep STL/best-fit metrics secondary until registration semantics are frozen;
- treat <=25 um expanded reference uncertainty as a preferred engineering target, not a mandatory standards requirement;
- keep mean-bias, individual-scan, implant-pose and surface claims distinct.

# RECOMMENDED CODEX SCOPE

No Codex implementation is justified yet for the scanner itself.

After the physical measurement contract is decided, a small offline tooling task may be given to Codex to add a versioned fixture-ground-truth schema and deterministic report/comparator support, preferably coordinated with Issue #10. Codex should be free to choose the simplest architecture that preserves gauge-independence, units, uncertainty provenance and failed-scan accounting.

# CODEX EFFORT

HIGH

The future software task is nontrivial because of schemas/statistics/provenance, but it should not require ULTRA unless 6-DoF uncertainty propagation or a generalized metrology framework is added.

# VALIDATION GATE

Before any `<=100 um` claim:

- predeclared measurand(s) and claim semantics;
- traceable/characterized reference values with uncertainty;
- physical realization of marker/implant datums documented;
- deterministic software aggregation tests;
- fixed-condition pilot;
- confirmatory sample-size/statistical method chosen before data collection;
- failed scans retained in failure statistics;
- bias/repeatability/reference uncertainty reported separately;
- no use of reprojection, internal geometry score or app-vs-app STL agreement as substitute for ground truth;
- implant/surface claims validated separately from marker-center distance claims.