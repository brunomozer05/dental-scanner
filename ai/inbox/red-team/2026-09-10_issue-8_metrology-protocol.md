AGENT_ROLE: red-team
DATE_UTC: 2026-09-10
REPOSITORY: brunomozer05/dental-scanner
BRANCH_INSPECTED: main
COMMIT_INSPECTED: 4b223ae57627ee316191e03cddde8fd8a580a097
RELATED_ISSUE: #8
REPORT_STATUS: complete

# TARGET

Independent red-team review of GitHub Issue #8, `[P1][Metrology] Criar benchmark de repetibilidade e trueness para meta de 100 µm`.

The review asks whether the proposed protocol is sufficient to support a future claim that DentalScanner can achieve linear errors at or below 100 µm, and what the smallest defensible experiment should be before more optimizer or camera work is promoted.

# CURRENT CODE CHECK

`main` was inspected at exactly `4b223ae57627ee316191e03cddde8fd8a580a097`.

Files/specs/tests inspected include:

- `AGENTS.md`;
- GitHub Issue #19;
- GitHub Issue #8;
- `specs/15_validation_protocol_and_accuracy.md`;
- `DentalScanner/ScannerMVP/Replay/ScanSessionReplaySTLComparisonExporter.swift`;
- `DentalScannerTests/ScanSessionReplaySTLComparisonTests.swift`;
- recent commit `7f1e48d9b88d9404fd6f527dd45285c5529c184f` (`Add diagnostic replay STL comparison`).

EVIDENCE: the current replay STL comparison normalizes two pose sets to a common marker frame and explicitly compares relative geometry. The tests verify deterministic base selection, preservation of pairwise distances/rotations under rebase, invariance to arbitrary global rigid transforms, deterministic artifact bytes, and non-overwrite of production STL.

EVIDENCE: current code search found no production or test path that consumes calibrated ground-truth values, reference-measurement uncertainty, trueness/bias metadata, or a metrology uncertainty budget. The diagnostic replay comparison is therefore useful for internal relative comparisons, but it is not a trueness benchmark.

EVIDENCE: `specs/15_validation_protocol_and_accuracy.md` already states that app-vs-app STL comparisons measure repeatability/stability rather than absolute accuracy. Its current absolute-accuracy section remains a draft and only says to obtain a professional/reference scan or known-dimension object before defining absolute targets.

EVIDENCE: Issue #8 is not stale. The recent replay/STL comparison commit added anchor-independent diagnostic comparison, not a calibrated reference pipeline. No recent commit removes the need for a metrology benchmark.

# CONFIRMED

## 1. The problem in Issue #8 is real

The project currently has deterministic and relative geometric diagnostics but no evidence path capable of proving 100 µm trueness.

Lower reprojection, lower app-vs-app surface distance, a visually improved STL, stable pairwise geometry in one session, or deterministic replay are all insufficient to establish absolute error.

## 2. The existing relative-geometry tooling is useful input

`DiagnosticMarkerPoseNormalizer` rebases pose sets to a common marker frame without changing their internal pairwise geometry. This is appropriate for comparing relative marker distances and rotations without assigning physical significance to an arbitrary global gauge.

This also means no M0 special case is required for metrology. A deterministic base marker may be used as an output coordinate convention, but primary pairwise measurands should remain anchor-independent.

## 3. Relevant metrology terminology must be tightened

Authoritative metrology references distinguish the concepts that Issue #8 is trying to separate:

- BIPM VIM: measurement precision is closeness among replicate values under specified conditions; repeatability, intermediate precision and reproducibility are different precision conditions.
- BIPM VIM: measurement trueness concerns agreement of the mean of replicate results with a reference quantity value and is associated with systematic error/bias; trueness itself is not a single numerical quantity.
- BIPM VIM: reproducibility requires specified changed measurement conditions; a simple fixture remount under otherwise identical conditions should not automatically be labeled full reproducibility.
- ISO 5725-1:2023 provides the general trueness/precision framework; ISO 5725-2:2025 covers repeatability/reproducibility study design; ISO 5725-4:2020 covers bias/trueness estimation.

Authoritative links reviewed:

- https://jcgm.bipm.org/vim/en/2.14.html
- https://jcgm.bipm.org/vim/en/2.15.html
- https://jcgm.bipm.org/vim/en/2.20.html
- https://jcgm.bipm.org/vim/en/2.24.html
- https://www.iso.org/standard/69418.html
- https://www.iso.org/standard/90054.html
- https://www.iso.org/standard/69421.html

## 4. The hand-held scanner standard reference should be chosen carefully

EVIDENCE: ISO 20896-1:2019 is explicitly for assessing accuracy of three-dimensional descriptions acquired directly with a hand-held scanning device, and ISO reports that the 2019 edition was reviewed and confirmed in 2025. It is a relevant methodological reference for a hand-held dental scanning validation program.

EVIDENCE: ISO 12836:2015 explicitly says its methods require a fixed or mechanically guided digitizing device and do not apply to hand-held scanning devices.

Therefore ISO 20896-1 is a better methodological starting reference than ISO 12836 for the capture modality, while neither standard should be claimed as automatic DentalScanner compliance because DentalScanner's primary marker/implant geometry output is not identical to the intra-oral surface-scanner use case described by ISO 20896-1.

References:

- https://www.iso.org/standard/69402.html
- https://www.iso.org/standard/68414.html

## 5. Measurement uncertainty must be part of a 100 µm decision

EVIDENCE: the BIPM/JCGM GUM framework requires measurement results to account for uncertainty components from the information used. JCGM 100:2008 remains the core uncertainty guide and has a 2026 amendment addressing nonlinearity; JCGM 101 provides a Monte Carlo propagation route where appropriate.

References:

- https://www.bipm.org/en/publications/guides
- https://www.bipm.org/en/doi/10.59161/jcgm101-2008

INFERENCE: for a 0.100 mm acceptance target, the Issue should not merely require a reference described as `significantly better than 100 µm`. A quantitative uncertainty objective and decision rule are necessary.

A conservative starting design target is to seek expanded reference/measurement uncertainty around `U(k≈2) <= 0.025 mm` for the primary linear measurands, corresponding to a 4:1 test-uncertainty ratio relative to 0.100 mm. NIST documents the historical 4:1 TUR convention, but this is a recommended project design rule, not a universal law. If that uncertainty is not achievable, the protocol should use an uncertainty-aware guard band or report an inconclusive zone rather than silently treating the nominal reference value as exact.

Reference:

- https://www.nist.gov/publications/guidelines-expressing-measurement-uncertainties-and-41-test-uncertainty-ratio

# CONTRADICTIONS

## 1. `At least 10 scans` is not sufficient by itself for a P95 acceptance claim

Issue #8 asks for at least 10 scans per configuration and also asks for P95 reporting.

INFERENCE: ten observations are acceptable as a pilot batch for estimating gross behavior, but they provide extremely weak information about the 95th-percentile tail. With ten scans, an empirical P95 is effectively driven by the largest observed values and has very large sampling uncertainty.

The Issue should not use `n = 10` plus an empirical P95 as a confirmatory pass/fail criterion without a sample-size rationale and confidence interval/uncertainty treatment.

## 2. `Remounting = reproducibility` is too broad

Issue #8 currently says to repeat after remounting for reproducibility.

EVIDENCE: the VIM requires changed conditions to be specified for reproducibility.

REVISE: fixture remount under the same device/operator/location/day should be described as a specific remount or intermediate-precision component. Full reproducibility should state which conditions change, for example device, operator, day, location, camera profile, or fixture rebuild.

## 3. `Reference STL` alone is not a complete ground-truth definition

A professional STL can itself contain scanning, meshing, registration and datum-definition uncertainty.

HYPOTHESIS: if the project relies only on unconstrained best-fit surface registration, systematic scale or geometry errors can be partially hidden by the registration. This must be falsified or controlled before interpreting best-fit surface distances as trueness.

The primary ground truth should therefore be tied to explicitly defined physical measurands/datum features with traceable reference values. Surface best-fit metrics can remain secondary diagnostics.

# MATHEMATICAL / GEOMETRIC REVIEW

## Coordinate frames and gauge

For metrology, absolute world gauge is not itself a physical measurand. Pairwise marker geometry is naturally gauge-independent.

Recommended primary pose-derived quantities include:

```text
for marker pair (i,j):
T_i_j = inverse(T_world_i) * T_world_j

d_ij = ||t_i_j||                         [mm]
rotation error = geodesic(R_ij_measured, R_ij_reference) [rad or deg]
```

The output frame may be normalized to a deterministic marker for visualization, but acceptance should not depend on choosing M0 or any other marker as a privileged physical truth.

If implant centers/axes are the actual clinical target, those should be declared as primary measurands rather than relying on arbitrary STL surface vertices.

## Units

The 100 µm target is exactly `0.100 mm`.

Keep separate:

- linear error: mm or µm;
- angular error: radians internally, degrees may be used for reporting;
- image reprojection: pixels;
- surface residual: mm;
- uncertainty for each measurand: same unit as that measurand.

A pixel reprojection threshold cannot be compared numerically with a 0.100 mm metrology threshold without an explicit measurement model.

## Frame identity and determinism

Algorithmic determinism is already separately testable through replay and must not be pooled into physical capture repeatability.

Recommended decomposition:

1. **Algorithm determinism:** identical persisted session/configuration -> identical result/artifact.
2. **Capture repeatability:** same fixture, device, operator, procedure, location and short time interval.
3. **Intermediate precision / remount:** deliberately remount/rebuild or vary day while documenting what changed.
4. **Reproducibility:** explicitly vary defined conditions such as device/operator/location when the study reaches that phase.
5. **Trueness/bias:** compare the mean measured value for a declared measurand against a traceable reference value with uncertainty.

## Connectivity

A scan missing expected markers or yielding disconnected marker support must not receive invented identities. Such scans should be retained as failures/missing results in the denominator, not silently omitted from the metrology dataset.

# RISKS

1. **Reference too weak for the target.** A nominally `better than 100 µm` scanner could have uncertainty large enough that the DentalScanner-vs-reference difference cannot resolve a 100 µm claim.

2. **Post-hoc measurand selection.** Choosing whichever pairwise distance or surface region looks best after data collection creates optimistic bias. Primary measurands must be declared first.

3. **ICP hides systematic error.** Unrestricted best-fit registration can absorb some rigid misalignment and can make a distorted result appear better. Datum-aligned and best-fit results should be reported separately.

4. **Tail metric overclaim.** `P95` from ten scans is too unstable to be treated as strong evidence.

5. **Correlated surface points treated as independent samples.** Thousands of STL vertices are not thousands of independent captures. Statistical replication unit should normally be the scan/session (or declared physical replicate), not each vertex.

6. **Failure exclusion bias.** Scans with missing/disconnected markers, export failure or solver failure must remain visible in failure-rate statistics instead of disappearing from accuracy calculations.

7. **Translation-only success criterion.** A 100 µm linear target says nothing about orientation. Angular measurands need separate criteria if orientation is clinically relevant.

8. **Fixture definition error.** Marker manufacturing tolerance, adhesive/remount movement, datum localization and thermal/mechanical fixture drift can dominate a 100 µm budget.

# MISSING EVIDENCE

Before a confirmatory 100 µm study, the project still needs:

- the actual physical fixture design and material;
- which marker/implant datums are the primary measurands;
- traceable reference values for those measurands;
- calibration certificate or equivalent reference-system uncertainty;
- uncertainty contribution from fixture/datum definition;
- environmental range, especially temperature if dimensions are sensitive at the required scale;
- a predeclared acceptance/guardband rule;
- a sample-size justification for any percentile/tail claim;
- evidence that the chosen STL registration procedure does not hide the error mode being tested.

# MISSING TESTS

For the software/tooling side of Issue #8 or the related comparator work, add fixtures/tests that demonstrate:

1. a synthetic calibrated marker assembly with known pairwise translations/rotations produces the expected signed errors;
2. a global rigid transform of both measured and reference assemblies does not change gauge-independent errors;
3. no marker, including M0, is required as a special physical anchor;
4. missing/disconnected markers are reported as unavailable/failure, never identity/zero error;
5. missing ground-truth uncertainty is represented as unavailable and blocks a trueness pass claim;
6. deterministic aggregation produces identical JSON/CSV bytes for identical inputs/configuration;
7. mm/µm conversion is explicit and tested (`0.100 mm == 100 µm`);
8. angular and translational errors are not combined into a dimensionally invalid scalar;
9. best-fit surface metrics and datum-aligned metrics remain separate fields;
10. failed scans remain counted in dataset/failure-rate summaries.

Existing `ScanSessionReplaySTLComparisonTests` already provides useful gauge/rebase and deterministic-artifact coverage, but it does not exercise calibrated ground truth or uncertainty.

# SIMPLER ALTERNATIVE

Do not start by building a large generalized metrology platform or changing scanner production code.

Split #8 into a low-risk sequence:

### Phase 8A — measurement contract, no scanner change

Define a small fixture and 3-6 primary scalar measurands, for example selected pairwise marker distances and relative rotations or clinically relevant implant-center/axis quantities. Obtain traceable reference values and uncertainties. Freeze the protocol, units, registration/datum rule and pass/guardband rule before collecting candidate results.

### Phase 8B — pilot

Run about 10 repeated scans under strict repeatability conditions. The pilot answers whether the fixture, metadata, failure handling and uncertainty budget are usable. It is not sufficient to certify a P95 <=100 µm claim.

### Phase 8C — confirmatory study

Choose sample size from the intended statistical claim. If P95 is a release gate, collect enough independent scans to estimate it with a documented confidence/uncertainty interval; otherwise use mean bias + repeatability standard deviation/uncertainty as the predeclared primary decision quantities and keep P95 descriptive.

Only after the baseline fixture is proven should the matrix expand to remount/day/operator/device and compare accumulator, continuity replay, camera profiles or BA.

This sequencing is cheaper and more falsifiable than immediately testing every profile/optimizer combination against a weak reference.

# REQUIRED CHANGES

Revise Issue #8 before using it as the acceptance gate for a 100 µm claim:

1. Replace `reference significantly better than 100 µm` with a quantitative uncertainty requirement and decision rule. Recommended starting objective: seek `U(k≈2) <= 25 µm` for primary 100 µm linear measurands, or explicitly use guardband/inconclusive handling when that cannot be achieved.

2. Define the primary measurands and datum/reference frame before data collection. Pairwise marker/implant quantities should be primary where possible; surface best-fit metrics should be secondary.

3. Rename the simple remount experiment as remount/intermediate-precision unless reproducibility conditions are explicitly varied and documented.

4. Treat 10 scans as a pilot minimum, not sufficient evidence for a hard P95 gate. Require a sample-size rationale and uncertainty/confidence interval for percentile claims.

5. Require an uncertainty budget including reference calibration, fixture stability, datum/marker realization, registration/meshing where applicable, and repeatability components.

6. Add a predeclared decision rule for the 100 µm target. One conservative candidate for scalar linear measurands is a guardbanded condition such as `|estimated bias| + U <= 0.100 mm`; the exact rule must be selected before the confirmatory experiment and aligned with the intended claim.

7. Require failure-rate reporting and prohibit silently excluding missing/disconnected/export-failed scans.

8. Require datum-aligned and unconstrained best-fit surface comparisons to remain distinct if STL surface error is analyzed.

9. Reference ISO 20896-1 as the more relevant hand-held scanning methodology framework, while explicitly stating that project-specific applicability/compliance must be assessed; do not use ISO 12836 as if it covered hand-held devices.

10. Keep algorithm determinism, physical repeatability, intermediate precision/reproducibility, and trueness as separate result families in reports and datasets.

# VERDICT

REVISE

The Issue is directionally correct and should advance in parallel with the P0/P1 geometry work, but its current acceptance criteria are not rigorous enough to support a <=100 µm trueness decision. The main deficiency is not missing optimizer code; it is the absence of a quantitative uncertainty budget, defined measurands, a decision rule, and statistically defensible replication for tail claims.
