# Measurement Validation

## Provenance on every value

| Provenance | Meaning |
|---|---|
| API Exposed | reported by a public API (screen scale, thermal state, accessibility flags) |
| Measured | read directly from captured pixels or timestamps |
| Derived | computed deterministically from measured values |
| Estimated | the result of fitting a model; depends on the model's assumptions |
| Theoretical | a value or relation from theory |
| Unavailable | not obtainable through public interfaces |
| User Entered | entered by the operator because no API exposes it |
| Recorded | a configuration value recorded at acquisition time |

Every `Measurement` stores: name, value (nil = N/A), unit, provenance, algorithm, algorithm version,
confidence level with a written justification, uncertainty (half-width + kind: SD, SE, 95% CI, quantization,
fit interval, range), sample count, pixel region, timestamp, validity (status + reasons), significant digits,
source frame names, notes and optional series. Values are shown with the significant digits the method
justifies. A value that cannot be computed is N/A with a reason, never a default.

## Validation steps built into the pipeline

| Check | Where | Effect |
|---|---|---|
| Reference capture verification | Capture Validation (per method, device, OS) | failed method invalidates its experiments |
| Pixel scale validation | Capture Validation, ReplayKit aspect check | mismatch fails validation / refuses capture |
| Color space validation | color space name stored per frame; decoding through Core Graphics | untagged frames are labelled |
| Frame timestamp validation | median ReplayKit delivery delay; frame interval statistics in Motion | reported with results |
| Image registration check | surround residual after integer alignment | > 5% marks the pair "not matched" |
| Settle check | residual between consecutive captures | unsettled frames are warnings |
| File integrity | SHA-256 per frame, verified before every analysis and on bundle import | mismatches abort |
| Match confidence | NCC threshold, ambiguity ratio, boundary hits | rejected vectors excluded and counted |
| Model adequacy | R^2 of the blur model, transfer-fit residual | low values downgrade confidence or warn |
| Repeatability | repeated acquisitions: mean, CI, CV, outliers | low confidence when CV > 15% |
| Failure reporting | every module | N/A with reason; failed acquisitions are not stored as successful |

## Tests

`GlassLabTests` (simulator) cover: transfer functions, CIELAB, CIEDE2000 against nine Sharma et al. reference
pairs, WCAG contrast, HEX/HSV; statistics, CI, outliers, OLS; Nelder-Mead on Rosenbrock, golden section, DFT;
step response and spring fit against analytic responses; Gaussian blur, crop, shift, sRGB decoding, 16-bit
round trip; SDF signs and mask partition; blur fit recovering sigma/gain/offset on synthetic data;
displacement recovering a known 3 px shift; a full analysis checking that every N/A carries a reason;
image metrics; serialization including NaN series; DataStore save/reload/delete and interrupted-acquisition
detection; CSV quoting; ZIP CRC-32 known value, write/list/extract; bundle export + verified import; tampered
bundle rejection; matrix pairwise coverage; reconstruction fitting on model-generated data; display-link
statistics.

Simulator success shows the code is correct on synthetic inputs. It does not show that captures on a
physical iPhone or iPad match what the eye sees. See DEVICE_VALIDATION_CHECKLIST.md.
