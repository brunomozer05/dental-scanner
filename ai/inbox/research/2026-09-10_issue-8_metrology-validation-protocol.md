AGENT_ROLE: research
DATE_UTC: 2026-09-10
REPOSITORY: brunomozer05/dental-scanner
BRANCH_INSPECTED: main
COMMIT_INSPECTED: 4b223ae57627ee316191e03cddde8fd8a580a097
RELATED_ISSUE: #8
REPORT_STATUS: complete

# RESEARCH QUESTION

What is the smallest metrologically defensible offline/bench protocol that can determine whether DentalScanner is plausibly approaching a 100 µm dimensional-error regime, while correctly separating repeatability, intermediate precision/reassembly effects, reproducibility, trueness/bias, reference uncertainty, and internal algorithmic stability?

# CURRENT DENTALSCANNER BEHAVIOR

## Roadmap and issue state

At `main` commit `4b223ae57627ee316191e03cddde8fd8a580a097`, GitHub Issue #19 explicitly allows Issue #8 to advance in parallel and makes repeatability/trueness benchmarking a required promotion step before geometry changes are treated as real precision improvements.

Issue #8 currently requires:

- a rigid fixture;
- a reference method significantly better than 100 µm;
- marker-marker distances/poses;
- fixed lighting, distance, device, profile and operator;
- at least 10 scans per candidate configuration;
- repeatability without remounting;
- a second experiment after remounting, currently called reproducibility;
- mean/std/P95/max and ground-truth error.

This direction is correct, but three metrology-critical items remain underspecified:

1. the exact measurand behind the statement `<=100 µm` is not defined;
2. no quantitative requirement is assigned to reference uncertainty;
3. `n >= 10` is too small if empirical P95 is intended as a decision metric rather than a pilot diagnostic.

## Existing validation spec

`specs/15_validation_protocol_and_accuracy.md` correctly states that app-vs-app STL comparisons measure repeatability/consistency rather than absolute accuracy, and that a professional reference scan, industrial scanner or known-dimension object is needed for absolute evidence. It also proposes surface metrics such as mean/median/P90/P95/P99/max after a reference STL exists.

However, the current spec does not define:

- the direction of the surface comparison;
- the comparison mask/overlap region;
- a datum-based versus best-fit registration policy;
- uncertainty of the reference artifact;
- uncertainty of the reported reference values;
- a conformity decision rule around 100 µm.

## Current diagnostic comparator is not a ground-truth comparator

`DentalScanner/ScannerMVP/Replay/ScanSessionReplaySTLComparisonExporter.swift` currently compares `ALL` and `FILTERED` replay outputs from the same captured session. It rebases each replay to a common marker, exports diagnostic STL assemblies, and records pairwise relative geometry. This is useful A/B evidence, but the code has no independent calibrated reference input and therefore cannot establish trueness.

`DentalScanner/ScannerMVP/Export/DiagnosticMarkerAssemblySTLExporter.swift` rebases pose sets by a common rigid transform. The tests in `DentalScannerTests/ScanSessionReplaySTLComparisonTests.swift` explicitly verify that pairwise distances and pairwise rotations are preserved by this rebasing and are invariant to an arbitrary common global transform. That makes pairwise marker geometry a strong candidate for the first metrology measurand because it avoids arbitrary world-frame alignment.

Issue #10 already anticipates a future unified comparator with ground-truth input and explicitly requires anchor-independent pairwise geometry, multi-session repeatability and a distinction between internal metrics, repeatability and trueness.

# EVIDENCE FROM LITERATURE / DOCUMENTATION

## 1. JCGM 200:2012 / VIM3 — metrology vocabulary

Source: Joint Committee for Guides in Metrology, International Vocabulary of Metrology (VIM3), JCGM 200:2012, BIPM annotated online edition.

Relevant official entries:

- measurement trueness: https://jcgm.bipm.org/vim/en/2.14.html
- measurement precision: https://jcgm.bipm.org/vim/en/2.15.html
- repeatability conditions: https://jcgm.bipm.org/vim/en/2.20.html
- intermediate precision conditions: https://jcgm.bipm.org/vim/en/2.22.html
- reproducibility conditions: https://jcgm.bipm.org/vim/en/2.24.html

Relevant findings:

- precision concerns closeness among replicate measured values and is usually summarized numerically by standard deviation/variance;
- repeatability conditions hold procedure, operator, measuring system, operating conditions and location constant over a short time;
- intermediate precision keeps the measurement procedure and location but may allow changes over an extended period, including calibration/operator/system changes;
- reproducibility conditions include different locations, operators and measuring systems;
- trueness concerns closeness between the average of replicate results and a reference quantity value and is inversely related to systematic error.

Application to DentalScanner:

Issue #8's same-fixture/same-device/same-operator block is appropriately a repeatability study. A fixture remount with the same operator/device/location is not, by itself, full VIM reproducibility. It is better described as a reassembly/remount robustness study or an intermediate-precision condition unless additional factors are deliberately changed.

## 2. ISO 20896-1:2019 — Dentistry, digital impression devices, accuracy assessment

Source: ISO 20896-1:2019, `Dentistry — Digital impression devices — Part 1: Methods for assessing accuracy`.

Official page: https://www.iso.org/standard/69402.html
Official OBP preview: https://www.iso.org/obp/ui#iso:std:iso:20896:-1:ed-1:v1:en

Status observed in 2026: the 2019 edition remains published/confirmed while edition 2 is under development.

Relevant publicly visible findings:

- the standard is specifically about accuracy assessment of 3D numerical descriptions acquired by a manually guided hand-held dental scanner;
- it defines a `dimension of interest` as a distance between object features that is measured independently as a reference/true value and estimated by the scanning device using a prescribed scanning procedure;
- it requires reference measurement of test objects and test conditions/reporting;
- its introduction warns that ideal bench objects and cooperative surfaces can produce better results than less ideal clinical conditions;
- precision is operationalized by standard deviation in the standard's terminology.

Application to DentalScanner:

DentalScanner should not begin Issue #8 with a single whole-STL score. A small set of predeclared dimensions of interest, measured independently on a rigid fixture, is more defensible and is directly compatible with the project's existing pairwise marker geometry.

## 3. ISO/TR 20896-2:2023 — implanted devices

Source: ISO/TR 20896-2:2023, `Dentistry — Digital impression devices — Part 2: Methods for assessing accuracy for implanted devices`.

Official page: https://www.iso.org/standard/76858.html

Relevant finding:

The report specifically addresses acquisition and analysis methods for assessing accuracy of numerical models involving implant bodies and oral geometry.

Application to DentalScanner:

The project should treat implant-axis/location accuracy as a distinct later measurand rather than assuming that a low surface STL deviation automatically proves implant-pose trueness.

## 4. ISO 10360-13:2021 — optical 3D coordinate measuring systems

Source: ISO 10360-13:2021, `Geometrical product specifications (GPS) — Acceptance and reverification tests for coordinate measuring systems (CMS) — Part 13: Optical 3D CMS`.

Official page: https://www.iso.org/standard/74957.html

Relevant findings from the official abstract/preview:

- the standard defines acceptance and reverification testing for optical 3D coordinate measuring systems;
- performance includes length measurement in the measuring volume;
- applicability assumes object surface characteristics such as gloss and colour are restricted to a cooperative range;
- the table of contents includes distortion characteristics, probing characteristics and volumetric length-measurement error.

Application to DentalScanner:

A calibrated optical reference system can be suitable, but its own measurement uncertainty and surface dependence must be documented. A laboratory saying only `scanner accuracy = X µm` is not enough; the fixture-specific measurement procedure and uncertainty are needed.

## 5. JCGM 100 / JCGM 106 — uncertainty and conformity decisions

Sources:

- JCGM 100:2008, `Evaluation of measurement data — Guide to the expression of uncertainty in measurement`, current BIPM publication set includes a 2026 Amendment 1: https://www.bipm.org/en/committees/jc/jcgm/publications
- JCGM 106:2012, `The role of measurement uncertainty in conformity assessment`: https://www.bipm.org/en/doi/10.59161/jcgm106-2012

Relevant findings:

- a measurement result is incomplete without relevant uncertainty information when a conformity decision is required;
- standard uncertainty characterizes dispersion associated with the estimate;
- expanded uncertainty is `U = k u`, with the coverage factor selected for a desired coverage probability;
- JCGM 106 describes guarded acceptance: an acceptance limit may be placed inside the tolerance limit to reduce false acceptance risk;
- JCGM 106 gives one legal-metrology example where an expanded uncertainty limit of one third of the maximum permissible error is used. This is an example, not a universal requirement.

Application to DentalScanner:

The phrase `reference significantly better than 100 µm` needs to become a numerical uncertainty requirement or a decision rule. Without that, a measured 80 µm error and a measured 110 µm error may be statistically indistinguishable if the reference method itself has large uncertainty.

## 6. Reference/test mesh selection can materially change reported surface trueness

Source: Schlenz et al./Journal of Dentistry, `Trueness evaluation of digital impression: The impact of the selection of reference and test object`, 2021, DOI 10.1016/j.jdent.2021.103706, PubMed PMID 34077800.

PubMed: https://pubmed.ncbi.nlm.nih.gov/34077800/

Relevant finding:

The study showed large differences in reported 3D trueness metrics when the ground-truth mesh versus the intraoral-scan mesh was chosen as the reference object in surface comparison. The authors concluded that reference-object choice and compared regions must be defined carefully.

Application to DentalScanner:

Whole-STL mean/P95/heatmap should be secondary validation outputs unless the reference direction, overlap mask and registration policy are fixed in advance. Pairwise calibrated dimensions avoid much of this ambiguity for the first benchmark.

## 7. Recent dental scanner studies commonly vary examiner/model and use CMM/reference models

Examples:

- Hauschild et al., Journal of Dentistry 2024, DOI 10.1016/j.jdent.2024.105336, PMID 39260468: complete-arch implant trueness study using a coordinate measuring machine to establish a reference model.
- Buhl et al., Scientific Reports 2025, PMID 41266533: factorial in-vitro study evaluating model configuration and examiner as accuracy factors.

Application to DentalScanner:

Operator and fixture/model configuration are credible influence quantities. They should be introduced only after the fixed-condition repeatability baseline is established, so their effects are not confounded with the initial measurement-system noise.

# MATHEMATICAL IMPLICATION

## Coordinate frames and transformations

For the physical reference fixture, define a fixture coordinate frame `F` only if needed for datum-based 6-DoF analysis.

For physical marker `i`, define:

`T_FMi = fixture-from-marker-i`

such that

`p_F = R_FMi * p_Mi + t_FMi`.

Units:

- translations and distances: millimetres;
- final reported small errors may also be displayed in micrometres using `1 mm = 1000 µm`;
- rotations: matrices in SO(3) for geometric reasoning; angular error may be reported in degrees after computation.

No Euler-angle representation is required.

A DentalScanner session may produce marker poses in an arbitrary common output frame `G`. Primary distance measurands should therefore avoid needing `G` to be registered to `F`.

## Primary distance measurand

For four markers there are six unordered pairs `(i,j)`.

Reference pairwise distance:

`d_ref_ij = || t_FMi - t_FMj ||`.

Scanner pairwise distance for session `k`, in any common scanner output frame `G`:

`d_scan_ij,k = || t_GMi,k - t_GMj,k ||`.

Because Euclidean distance is invariant under a common rigid transform, no global alignment is needed to compare these values.

Per-session dimensional error:

`e_ij,k = d_scan_ij,k - d_ref_ij`.

This is signed error in millimetres. Report absolute error separately as `|e_ij,k|`; do not discard the sign when estimating systematic bias.

Repeatability standard deviation under fixed repeatability conditions:

`s_r,ij = sqrt( sum_k (d_scan_ij,k - mean(d_scan_ij))^2 / (n-1) )`.

Estimated bias for the pair:

`b_hat_ij = mean(d_scan_ij) - d_ref_ij = mean(e_ij)`.

`b_hat` is a numerical estimate of systematic error/bias; it is preferable to saying `trueness = 42 µm`, because VIM treats trueness itself as a qualitative property.

## Relative orientation, later stage

If the physical reference procedure can establish complete marker coordinate frames, use a relative rotation that is invariant to the common fixture/world frame:

`T_MiMj = inverse(T_FMi) * T_FMj`.

For scanner and reference relative rotations, define

`R_delta = transpose(R_ref_MiMj) * R_scan_MiMj`.

Geodesic angular error:

`theta = acos( clamp((trace(R_delta)-1)/2, -1, 1) )`.

Internal unit: radians. Reported unit may be degrees.

This orientation test should be deferred if the fixture reference only establishes center distances. It is better to have a strong scalar distance ground truth than to invent poorly observed 6-DoF ground truth.

## Uncertainty model

For the mean bias estimate of a pair, a first-order independent-component model is:

`u_b^2 = u_ref^2 + s_r^2/n + u_fixture^2 + u_environment^2 + u_analysis^2`.

Important caveats:

- `u_ref` does not decrease merely because DentalScanner repeats the scan; the same reference value is common to all sessions;
- if components are correlated, covariance terms must be included rather than root-sum-squared blindly;
- the uncertainty of the mean bias is not the same as prediction uncertainty for one future scan;
- thermal expansion, reference feature localization, fixture remounting, reference scanner/CMM calibration, mesh fitting and datum extraction can all enter the budget depending on the chosen procedure.

Expanded uncertainty may be reported as

`U_b = k * u_b`

with the chosen coverage factor and intended coverage probability documented.

## 100 µm must be attached to a specific claim

At least three different claims are possible and they are not equivalent:

1. `|mean bias| <= 100 µm` for predeclared marker-pair distances under fixed bench conditions;
2. `95% of individual scan errors <= 100 µm` under fixed conditions;
3. a surface/implant-point 3D error criterion `<=100 µm` after a defined registration.

The project should select the claim before data collection. The first claim is the simplest defensible starting point because the current system already exposes pairwise marker geometry and it minimizes registration ambiguity.

## Why n=10 cannot support a robust empirical P95 gate

If `q_0.95` is the true 95th percentile of an error distribution, any one observation has probability `0.95` of falling at or below it. With `n=10`, the probability that all ten observations lie below the true P95 is

`0.95^10 = 0.5987`.

Therefore the probability of observing even one value above the true P95 is only

`1 - 0.95^10 = 0.4013`.

So an empirical P95 from ten scans is mostly an interpolated near-maximum statistic, not a well-supported tail estimate.

Solving

`1 - 0.95^n >= 0.95`

gives

`n >= 59`.

Thus about 59 independent observations are required merely to have at least a 95% chance of seeing one observation above the true P95. This does not by itself provide a narrow confidence interval for the percentile; it only shows why ten scans are inadequate for a P95 pass/fail claim.

Under a normal-distribution assumption, the 95% confidence interval for the true standard deviation when `n=10` is also very wide: approximately `[0.69 s, 1.83 s]`, where `s` is the observed sample standard deviation. The project should not rely on this normal assumption for acceptance unless diagnostics support it; the calculation is included only to illustrate sampling uncertainty.

# EVIDENCE

1. **EVIDENCE — current project lacks independent ground truth in the replay STL comparator.** The current code compares replay policies from the same session and does not ingest a calibrated fixture/reference value.

2. **EVIDENCE — current pairwise geometry is designed to be rigid-frame invariant.** The diagnostic normalizer and tests explicitly preserve pairwise distances/rotations under rebasing and arbitrary common global transforms.

3. **EVIDENCE — Issue #8 currently sets `>=10 scans` while also requiring P95.** This sample size is not sufficient for a robust empirical 95th-percentile decision.

4. **EVIDENCE — Issue #8's remount experiment is not full VIM reproducibility if operator, device and location remain unchanged.** It is more appropriately classified as remount/reassembly robustness or intermediate precision depending on the full condition set.

5. **EVIDENCE — ISO 20896-1 supports independently measured dimensions of interest under prescribed scanning procedures.** This aligns closely with pairwise marker distances.

6. **EVIDENCE — JCGM guidance requires uncertainty to be considered in conformity decisions.** A nominal reference value without an uncertainty statement is not enough for a defensible 100 µm decision.

7. **EVIDENCE — surface-comparison direction/reference choice can materially change reported dental scan trueness.** The cited 2021 study demonstrated this experimentally.

# INFERENCE

1. **INFERENCE — the fastest path to real metrology is not a reference STL first.** A small calibrated fixture with six marker-pair distances is sufficient to answer whether the current geometry is even in the correct dimensional regime before building a complex surface-comparison pipeline.

2. **INFERENCE — pairwise distance should be the primary first-pass trueness measurand.** It is already natural to the DentalScanner architecture, avoids arbitrary global-frame registration, is easy to trace to CMM/optical reference measurements, and is interpretable in micrometres.

3. **INFERENCE — n=10 should remain a pilot/debug minimum, not a final evidence threshold.** It can reveal gross bias and estimate order-of-magnitude repeatability, but it should not support a P95 conformity statement.

4. **INFERENCE — a candidate configuration that looks stable internally can still fail this benchmark.** Reprojection, geometry score, capture maturity and app-vs-app agreement can all be excellent while `b_hat_ij` remains systematically wrong.

5. **INFERENCE — the fixture itself can dominate the error budget if marker physical geometry is not characterized.** Mechanical distances between marker holders are not automatically equal to distances between the actual fiducial coordinate origins used by PnP. The reference procedure must characterize the actual marker-origin geometry or a calibrated transform from mechanical datums to marker frames.

# HYPOTHESIS

1. **HYPOTHESIS — an expanded reference uncertainty target of `U_ref(k≈2) <= 25 µm` is practical enough to discriminate a 100 µm DentalScanner target.** This is an engineering target, not an ISO/JCGM mandate. If only a larger uncertainty is achievable, a formal guarded decision rule should replace a simple `measured error <=100 µm` threshold.

2. **HYPOTHESIS — some current configurations may show low repeatability spread but non-negligible signed distance bias.** This would indicate a systematic scale/intrinsic/marker-size/geometric calibration problem rather than frame-selection noise.

3. **HYPOTHESIS — remounting the same physical markers may add a measurable fixture/marker-placement component even if scanner software is unchanged.** This should be measured separately before attributing the effect to the camera or pose estimator.

# POTENTIAL BENEFIT

A correct Issue #8 protocol would provide the first evidence capable of distinguishing these failure classes:

- random scan-to-scan variation;
- persistent dimensional scale bias;
- pair-specific geometric bias;
- marker fabrication/mounting variation;
- operator/path sensitivity;
- device/profile sensitivity;
- reference-system uncertainty;
- later BA improvement versus merely lower reprojection.

It would also create a stable external yardstick for Issues #2, #3, #9, #13 and future BA work: every candidate could be compared against the same calibrated scalar dimensions before any production promotion.

# RISKS / FAILURE MODES

1. **Undefined measurand.** `100 µm accuracy` without specifying distance, point, axis, surface or confidence level is not testable.

2. **Reference uncertainty too large.** A nominal CMM/scanner specification is not the same as uncertainty for the actual fixture measurement procedure.

3. **Marker-origin mismatch.** CMM measurements of holders or screws can be precise while the actual ArUco coordinate origin is displaced by print, cutting, lamination or mounting error.

4. **Fixture deformation/thermal drift.** A rigid fixture is not perfectly invariant. Temperature and remount stress must either be controlled or included in uncertainty.

5. **Pseudo-replication.** Six marker pairs from one scan share the same four marker poses and are statistically correlated. They must not be treated as six independent scans when computing confidence.

6. **P95 with too few sessions.** Ten-session P95 can look reassuring by chance.

7. **Best-fit registration masking.** Surface ICP may distribute local error or hide datum-relevant pose error.

8. **Asymmetric mesh support.** Holes, occlusions and unequal surface coverage can bias one-way nearest-surface statistics.

9. **Changing too many factors at once.** Device, profile, distance, operator, fixture remount and algorithm version should not all vary in the first benchmark.

10. **Reference artifact itself changes.** Printed markers, adhesive layers and carrier material can age or move. Reference measurement must have an identifier/date and reverification plan.

11. **Using mean absolute error as bias.** Absolute values remove the sign and can conceal a systematic scale direction. Signed error and absolute error must both be preserved.

12. **Averaging pairs into one headline score too early.** A single mean can hide one clinically/geometrically bad long-baseline pair.

# PROPOSED OFFLINE EXPERIMENT

## Phase A — metrology fixture characterization, no app change

Create or select one rigid four-marker fixture.

Before any DentalScanner validation, independently characterize the six actual marker-center pairwise distances:

`d01, d02, d03, d12, d13, d23`.

Preferred reference hierarchy:

1. CMM with a documented procedure and uncertainty for the actual fiducial/datums;
2. calibrated optical 3D CMS with documented fixture-specific uncertainty;
3. another reference method only if traceability and uncertainty are documented.

The laboratory output should include, for each dimension:

- reference value in mm;
- standard or expanded uncertainty;
- coverage factor/coverage probability when available;
- measurement date;
- fixture temperature/environment when relevant;
- how the ArUco/marker origin was physically realized from measured features.

Do not accept only a generic instrument datasheet accuracy number.

## Phase B — fixed-condition pilot repeatability, n=10

Keep Issue #8's ten scans, but explicitly label this a **pilot**.

Hold constant:

- fixture and marker mounting;
- iPhone 16 device;
- camera profile;
- zoom/focus configuration;
- nominal working-distance band;
- illumination;
- operator;
- prescribed scan path;
- application commit;
- marker profile/version.

For each scan, export the existing production/replay artifacts needed to recover final marker poses. Compute all six signed pair errors.

Pilot outputs per pair:

- `mean(d_scan)`;
- signed bias estimate `b_hat`;
- absolute mean error;
- sample SD;
- min/max;
- raw per-scan error vector;
- reference uncertainty metadata.

P95 may be shown as `exploratory`, but must not be a pass/fail metric at n=10.

## Phase C — candidate validation with enough sessions for tail evidence

Only configurations that survive Phase B should proceed.

If empirical P95 remains a required decision metric, target at least ~60 independent scans per final fixed configuration as a minimum tail-observation regime; preferably define the exact confidence/quantile method before collecting data.

A practical structure could be multiple independent blocks rather than 60 scans in one uninterrupted run, for example:

- 20 scans block A;
- 20 scans block B after a time interval/restart;
- 20 scans block C after another interval;

while keeping the declared repeatability factors fixed inside each block. This allows drift/block effects to be inspected without silently mixing them into one distribution.

## Phase D — remount/intermediate precision

Remount the marker fixture or marker carriers according to a documented procedure and repeat the measurement block.

Call this `remount/reassembly intermediate precision` unless the test deliberately satisfies broader VIM reproducibility conditions.

Compare:

- within-mount repeatability;
- between-mount shift in each `d_ij`;
- combined variance components if enough blocks exist.

## Phase E — true reproducibility only when useful

After the baseline is understood, deliberately vary specified factors such as:

- operator;
- device unit;
- location/environment;
- potentially measurement system/profile.

Record exactly which factors changed. Do not collapse all changes into a single unexplained `reproducibility` number.

## Phase F — surface/implant comparison later

Once scalar dimensional metrology works:

- add reference STL or reference 6-DoF marker/implant datums;
- define the reference mesh as reference explicitly;
- define valid overlap/mask regions;
- define registration method and datums before seeing results;
- report one-way and/or symmetric surface metrics with exact semantics;
- preserve marker-pair scalar results as the sanity-check baseline.

# SUCCESS METRIC

## Required reporting layers

### Internal stability

Examples: reprojection, capture maturity, geometry score, accumulator variation.

Purpose: diagnose behavior only.

These are not evidence of absolute dimensional correctness.

### Repeatability

Under fixed conditions, report for each pair:

- `s_r` in µm;
- distribution of signed errors;
- exploratory quantiles;
- session count.

### Intermediate precision / remount robustness

Report within-mount and between-mount components separately.

### Reproducibility

Use that label only when the changed conditions satisfy the explicitly declared reproducibility design.

### Trueness / systematic error evidence

Primary quantity:

`b_hat_ij = mean(d_scan_ij) - d_ref_ij`.

Report:

- signed bias in µm;
- absolute bias in µm;
- uncertainty/coverage interval for the bias estimate;
- reference uncertainty.

## Proposed first 100 µm decision rule

For the initial **mean dimensional-bias** claim only, a defensible guarded criterion is:

`|b_hat_ij| + U_bias,95 <= 0.100 mm`

for every predeclared critical marker pair, where `U_bias,95` is the expanded/coverage uncertainty assigned to the bias estimate under the chosen measurement model.

This is a proposed DentalScanner engineering decision rule, not a quoted ISO requirement.

Do not average six pairs and declare success if one critical pair fails.

If the intended product claim is instead `95% of individual scans are within 100 µm`, define a separate percentile/tolerance-interval design with adequate sample size; the mean-bias rule is not sufficient for that claim.

## Reference uncertainty target

Preferred experiment-design target:

`U_ref(k≈2) <= 0.025 mm` for each primary distance.

Classification: **HYPOTHESIS / engineering target**.

If this cannot be achieved, do not discard the experiment automatically. Instead propagate the actual uncertainty and use a guarded acceptance rule; however, the closer the reference uncertainty gets to 100 µm, the less discriminating the experiment becomes.

# REPOSITORY IMPACT

No production-code change is recommended by this research.

If Issue #8 is approved for implementation later, likely offline/tooling work would involve:

- Issue #10 unified comparator or a dedicated metrology dataset reader;
- a versioned ground-truth fixture metadata schema;
- tests for unit conversion, pair identity, missing markers, deterministic aggregation and uncertainty fields;
- report/CSV output that keeps signed error, absolute error, repeatability and reference uncertainty separate.

Production geometry, OpenCV, `PoseEstimator`, `MultiFramePoseAccumulator`, finalization and export should remain unchanged during the benchmark implementation.

Potential data schema, conceptually:

- fixture ID/version;
- pair `(marker_i, marker_j)`;
- `referenceDistanceMm`;
- `referenceStandardUncertaintyMm` or `referenceExpandedUncertaintyMm`;
- coverage factor/probability;
- reference method/lab/date;
- temperature/environment note;
- marker-coordinate realization note.

# OPEN QUESTIONS

1. Can the chosen laboratory/CMM actually measure the current physical ArUco marker origin/plane, or only mechanical carrier features?
2. What is the current physical fabrication tolerance of marker side length, print scale, cut position and planar mounting?
3. What exact dimensional claim is meant by `100 µm`: mean bias, per-scan 95th percentile, implant point error, or surface deviation?
4. Which marker pairs are clinically/geometrically critical? Are all six equal, or should long baselines receive explicit priority?
5. What reference uncertainty can the available CMM/industrial scanner provide for this exact fixture and feature definition?
6. Is temperature logging available and necessary at the selected fixture length/material?
7. Should the first fixture use coplanar markers for simplicity, or intentionally varied planes to enable later orientation validation?
8. Does the existing external/offline comparator already have an untracked ground-truth input path not present in `main`? No such implementation was found in the inspected repository commit.
9. How should shared-reference uncertainty and correlations among six pair distances be represented in the eventual statistical model?
10. What sample size/confidence level does the project want for a final P95 claim? The current `n>=10` requirement cannot answer that robustly.

# RECOMMENDATION

EXPERIMENT

Issue #8 is technically well motivated and should proceed, but the first experiment should be narrowed to a calibrated four-marker fixture and six independently referenced pairwise distances rather than a broad STL-accuracy campaign. Keep `n=10` as a pilot, define the 100 µm measurand and uncertainty rule before collection, and increase the final sample size if P95 is retained as a decision metric. This creates a defensible external truth signal without changing any live scanner geometry.

# PROPOSED ISSUE CHANGE

Suggested amendment to Issue #8, without modifying the Issue automatically:

```text
Clarify metrology semantics before data collection:

- Define the first primary measurands as the six pairwise marker-center distances for the fixed 4-marker fixture.
- Ground truth must report the reference value AND its measurement uncertainty for each dimension; a generic instrument accuracy specification is insufficient.
- Treat n>=10 as pilot repeatability only. Do not use empirical P95 as a pass/fail metric at n=10. If P95 remains a final gate, predefine a larger sample-size/confidence method (research indicates ~60 sessions is only a minimum regime for observing the upper 5% tail reliably).
- Rename same-device/same-operator fixture-remount testing to remount/reassembly intermediate precision unless broader VIM reproducibility conditions are intentionally varied.
- Preserve signed pairwise error; do not report only absolute error.
- Define the exact 100 µm claim before testing. Proposed first claim: for every critical pair, |mean bias| + 95% expanded/coverage uncertainty <= 0.100 mm under controlled bench conditions.
- Whole-STL ICP/heatmap metrics are secondary until reference direction, overlap mask and registration/datum policy are frozen.
- Prefer a reference expanded uncertainty target near <=25 µm (k≈2) for the 100 µm experiment; this is an engineering target, not a standards mandate.
```
