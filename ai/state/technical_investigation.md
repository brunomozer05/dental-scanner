# Technical Investigation checkpoint

- main examined: `3312a54bcf7f5d6fa0cd618a2de40ad50bce0315`
- baseline established: 2026-09-24 UTC
- issues: #2 active P0 investigation; #19 roadmap; #8 metrology remains ground-truth dependency; #25/#26 preserved as parallel research
- active hypothesis: planar IPPE candidate selection contributes materially to severe per-marker temporal discontinuities in the existing physical replay, but temporal smoothness alone does not identify the metrically true branch.
- competing hypotheses: corner/localization noise or blur; calibration/intrinsics/distortion mismatch; real camera motion; marker fabrication/datum error. Existing multi-marker disagreement evidence weakens pure real-motion explanations for isolated jumps but does not establish trueness.
- attempts without new information: 0
- observations/results: baseline preserves Issue #2 evidence from the 2026-07-16 session: two IPPE candidates in 3554/3554 observations, persisted pose essentially candidate 0, near-tied reprojection in some cases, and severe isolated per-marker discontinuities. No new physical data were available in this run; no replay was re-executed.
- rejected hypotheses: object-point ordering bug for current IPPE_SQUARE path was previously checked and not found; do not reopen without code delta.
- blockers: the authorized physical NDJSON is not available to this scheduled task, so the discriminating candidate-aware replay cannot be executed here; trueness/100 µm remains blocked on external ground truth under #8.
- latest delta gate: Agent A checkpoint reports same main HEAD, no newer product PR, and passing deterministic/unsigned-build checks; Issue metadata/labels changed on 2026-09-23 but no new experimental evidence was found.
- last radar monthly: not run; baseline work prioritized the proven #2 bottleneck and no broad novelty search was needed.
- reports: none created in this baseline run; existing synthesized Issue #2 decision remains historical context, not production proof.
- next experiment: when the existing authorized schema-1 replay artifact is available, run one deterministic read-only comparison of RAW_PERSISTED vs LOWEST_REPROJECTION_CANDIDATE vs TEMPORAL_CONTINUITY vs MULTI_MARKER_CONSENSUS, predeclaring temporal jump/reversal counts, cross-marker camera-motion disagreement, relative marker-marker stability, and maturity changes; do not infer trueness from smoothness or reprojection alone.
