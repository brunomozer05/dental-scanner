# Reference Scanner Pipeline Findings

This document records reusable technical concepts observed in an external technical reference. It is not a source-code specification and does not authorize copying external implementation details, models, assets, or geometry.

## Status and evidence rules

- **CONFIRMED BY CONFIG** — an explicit configuration value or switch supports the statement.
- **CONFIRMED BY SYMBOL** — a focused binary symbol identifies the component or data relationship.
- **STRONG INDICATION** — multiple independent observations support the conclusion, but the exact implementation was not inspected.
- **INFERENCE** — a technically reasonable interpretation of confirmed evidence.
- **HYPOTHESIS** — a candidate explanation or design direction requiring validation.

The presence of a framework, model, function, or resource does not by itself prove that a configured runtime path uses it.

## Executive findings

- An AI/keypoint path exists, but the configured reference pipeline has AI disabled. **CONFIRMED BY CONFIG.**
- Physical wide-camera selection and high-resolution capture support are present. **CONFIRMED BY SYMBOL.**
- Frame intrinsics are extracted from camera sample buffers. **CONFIRMED BY SYMBOL.**
- Device-class camera configuration exists as reference or fallback data. **CONFIRMED BY CONFIG.**
- Marker processing uses more known geometric constraints than four ArUco corners. **CONFIRMED BY SYMBOL.**
- Frame validity is evaluated before observations become optimization inputs. **STRONG INDICATION.**
- Observations retain frame identity. **CONFIRMED BY SYMBOL.**
- A separate camera pose exists per frame. **CONFIRMED BY SYMBOL.**
- Marker pose exists in shared/global state across frames. **CONFIRMED BY SYMBOL.**
- Angular diversity is evaluated per marker using a history of viewing directions. **CONFIRMED BY SYMBOL.**
- Minimum valid-observation and optimization targets exist. **CONFIRMED BY CONFIG.**
- Robust loss and explicit outlier removal are present. **CONFIRMED BY CONFIG/SYMBOL.**
- A relative marker graph exists. **CONFIRMED BY SYMBOL.**
- Frame-indexed reprojection optimization exists. **CONFIRMED BY SYMBOL.**

## Camera and intrinsics

The reference pipeline distinguishes three related concepts:

1. camera device and capture-format selection;
2. intrinsics delivered with the current camera sample buffer;
3. device-class matrices used as reference or fallback configuration.

The most transferable rule is to keep image coordinates, processing dimensions, and intrinsics in the same coordinate system. If a frame is resized, either image points must be mapped back to the source resolution or intrinsics must be scaled to the processing resolution.

Real frame intrinsics should remain primary when available. Device-class matrices are useful for diagnostics, sanity checking, and controlled fallback experiments, but should not silently replace frame intrinsics.

Physical wide-camera selection, zoom, focus point, exposure point, lens position, frame rate, and high-resolution capture are explicit concerns. High resolution should remain capability-checked and should have a safe fallback because throughput, focus behavior, and supported formats vary by device.

## Marker detection and geometric points

The reference pipeline contains:

- ArUco initial geometry for marker identity and initial pose;
- additional known geometric points associated with the marker coordinate system;
- local ROI normalization around expected features;
- classical vision refinement using thresholding, blur, contour/center refinement, perspective normalization, and subpixel processing.

The useful concept is not a particular external geometry. It is that pose robustness can improve when more independently measurable, versioned object points are available and each detected point carries validity and residual information.

DentalScanner must define and validate any future extra geometry independently. Four coplanar ArUco corners should not be treated as if they automatically satisfy the conditions for multipoint RANSAC.

## Frame indexed observation model

The transferable data model is:

```txt
Frame i
  intrinsics Ki
  camera pose Ci
  marker observations Oij
  image points uij

Marker j
  global/shared pose Mj
```

An observation belongs to one frame and one marker. Its image points are interpreted with that frame's intrinsics and camera pose. The marker pose is shared across all frames that observe it.

This model prevents a known invalid construction: concatenating image points captured from different camera poses and solving them as if one camera extrinsic generated every point.

## Observation validity and angle diversity

The reference design separates raw detections from valid optimization observations. Relevant concepts include:

- frame validity before optimization;
- finite pose and projection checks;
- focus, distance, ROI/frame-mask, and reprojection quality;
- per-marker angular history;
- minimum angular separation;
- target angular dispersion;
- minimum valid-observation count;
- a larger optimization target;
- controlled relaxation when progress or graph connectivity would otherwise stall.

Current DentalScanner specs already document experimental starting values of 1.5 degrees minimum separation, 4.5 degrees target angular dispersion, 65 useful observations per marker, and 300 optimization observations. These are experimental parameters, not accuracy guarantees.

Angle diversity should initially be measured and compared before it controls readiness or export. Relaxation must be bounded, observable in diagnostics, and incapable of accepting invalid geometry merely to advance progress.

## Multi-frame optimization

The reference architecture exposes these concepts:

- one camera pose per accepted frame;
- one shared marker pose per physical marker;
- a two-dimensional reprojection residual for each usable observation;
- robust loss around reprojection residuals;
- relative marker edges used as graph constraints or initialization support;
- explicit outlier removal and per-marker reprojection statistics.

A likely pipeline includes pose initialization, relative constraints, reprojection optimization, and outlier handling. **INFERENCE:** the exact call order is not confirmed and should not be reproduced as fact.

DentalScanner should first establish frame-indexed observation data and deterministic replay. The optimizer backend is secondary to a geometrically correct state and residual model.

## Comparison with DentalScanner

| Concept | DentalScanner state | Gap | Recommended phase |
|---|---|---|---|
| Per-frame intrinsics | Implemented | Preserve coordinate consistency through any resize | Existing behavior |
| Per-frame PnP | Implemented | Preserve as the only valid initial pose path | Existing behavior |
| Physical wide/zoom profiles | Implemented | Continue device/profile validation | Existing validation |
| Frame-indexed persistent observation entity | Partial/not implemented | Observation data is not retained as a first-class frame record | Spec 16 |
| Primary pre-accumulation gate | Not implemented | Primary accumulation can precede the complete quality classification | Spec 17 |
| Real per-marker angle diversity | Partial | Primary accumulator uses a simpler global/anchor rule; richer fields are diagnostic | After specs 16–18 |
| Session replay | Not implemented | The same accepted geometry cannot yet be replayed deterministically | Spec 18 |
| Frame-indexed bundle adjustment | Not implemented | No joint per-frame camera/shared-marker optimization | Spec 19 |
| Relative marker pose graph | Not implemented | No graph-based initialization or optimization | Future, after spec 19 |
| Extra marker geometry | Future | Requires an independently designed and measured marker profile | Marker v3 phase |

DentalScanner already performs robust relative-pose aggregation and tracks a best final pose candidate. These mechanisms should remain the control path during experiments.

## Do not adopt blindly

- Do not enable AI only because model resources or inference symbols exist.
- Do not copy proprietary models, assets, geometries, coordinates, or code.
- Do not replace real frame intrinsics with hardcoded matrices.
- Do not make 4K mandatory across devices.
- Do not apply multipoint RANSAC to four coplanar corners without suitable geometry.
- Do not add bundle adjustment before frame-indexed observations exist.
- Do not optimize focal length or distortion online before offline validation demonstrates observability and stability.
- Do not reactivate concatenated multi-frame PnP.
- Do not let a new optimizer control export before controlled A/B evidence exists.
