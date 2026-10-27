# Experiment Protocols

## 1. Reference / native-glass still pair (Optics)

Implemented in `CaptureCoordinator.acquire`.

1. Fix the background: the procedural background is deterministic for its spec; animated backgrounds are
   frozen at `frozenPhase` for both frames.
2. Fix the geometry: the subject is laid out with `.position` in a named coordinate space; element frames are
   reported by preference keys.
3. Render the reference: `Glass.identity` on the same view tree (content stays, material removed) or the
   subject hidden at opacity 0 (`ReferenceMode`). UIKit references use `UIVisualEffectView(effect: nil)`.
4. Wait `settleMilliseconds`, then capture repeatedly every ~90 ms until two consecutive frames differ by less
   than 0.0015 mean |dY| (encoded, 160-px thumbnails) or 3 s pass. The final residual and wait are stored.
5. Enable the native glass and repeat step 4.
6. Store both crops as PNG (pixels untouched, embedded profile, SHA-256), the element frames in points, the
   pixels-per-point factor, the capture method, pipeline notes and an environment snapshot.
7. Validity: invalid if the crops differ in size, if the method failed validation, or if no subject frame was
   reported; warning if a frame did not settle or the method was never validated.

The region model (interior / rim / surround masks) is derived from recorded frames, not from the configured
numbers, so content-sized subjects (buttons, bars) are measured where they actually are.

### Capture methods

| Method | Pixels | When to use |
|---|---|---|
| System Screenshot | Lossless PNG from the compositor, Display P3 | Highest fidelity. The operator presses side + volume when told; Glass Lab reads the new screenshot from Photos. |
| ReplayKit Frame | YCbCr 4:2:0 buffer converted to Display P3 | Automated runs (matrix) and video. Chroma is half resolution. |
| View Snapshot | `drawHierarchy` into 8-bit Display P3 | Fast; accepted only after Capture Validation passes on the device and OS. |

## 2. Capture validation

`CaptureCoordinator.validate`: a fixed scene (regular capsule 240x96 pt on Random Dots) is captured with
glass off and on. The method passes when the mean |dY| inside the glass is above both 0.01 and 5x the mean
|dY| in the background ring, and the crop width matches the canvas width x scale within 2 px. The result is
stored per method, device and OS version. A failed method marks every later experiment with it invalid.

## 3. Multi-background transfer

Acquire the same subject over several solid backgrounds (Black, White, 18% Gray, saturated colors) with no
other change, then run Compare > Multi-background transfer fit. Two backgrounds give an exact fit; three or
more test whether the composite is linear in the background.

## 4. Blur and MTF

- General textures (Random Dots, Noise, Checkerboard): Gaussian+affine fit of sigma.
- Step Edge background with a vertical edge through the glass: measured ESF, LSF and MTF50.
- Periodic patterns of known period: Local Contrast Retention equals the modulation transfer at that
  frequency only if the response is linear (stated with the result).

## 5. Refraction

Use Random Dots or Checker + Fiducials (aperiodic). Periodic patterns are flagged because block matching can
lock onto the wrong period.

## 6. Motion

Motion > Record interaction:
1. ReplayKit capture starts (system consent the first time); one frame gives the buffer size.
2. AVAssetWriter records HEVC (or ProRes 4444) with the presentation time of every written frame.
3. A gesture recognizer on the window logs every touch with `UITouch.timestamp`; programmatic interactions
   (appear, disappear, merge, split, morph, container spacing) log state-change markers on the same clock.
4. Analysis streams the movie, crops the canvas, and measures optical change, changed-region size and
   centroid per frame; onset, rise, settling, overshoot, oscillation, damping and a spring fit follow.

## 7. Test matrix

Choose factor levels, a generation mode, ordering and batch size. Each case applies its configuration (and
the window's appearance override), runs protocol 1 `repetitions` times and optionally analyses. Case status
is persisted after every case; cases left "Running" by a crash are marked "Incomplete" on next launch and can
be retried. Only settings the app controls are varied: system accessibility settings are recorded, never
forced.

## 8. Repeatability

Acquire with Repetitions > 1 (same configuration name), then Compare > Repeatability: mean, 95% CI (Student
t), SD, range, coefficient of variation and modified-z outliers for every shared measurement.
