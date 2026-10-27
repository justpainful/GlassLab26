# Optical Methodology

All pixel math runs on **linear Display P3** floats. Frames are decoded by drawing them into a 32-bit float
`extendedLinearDisplayP3` Core Graphics context, so the embedded ICC profile and transfer function of each
PNG are honoured (sRGB, Display P3 or untagged). Encoded RGB values are never treated as linear.

Relative luminance is CIE Y of linear P3 (`0.22897 R + 0.69174 G + 0.07929 B`). It is display-relative
(1 = display white), never nits.

## Regions

A signed distance field is built from the recorded element frames and shape (exact for rectangles, rounded
rectangles with circular corners, capsules, circles and the star polygon; first-order for ellipses):

- **interior**: sdf <= -max(3 px, 4 pt)
- **rim / edge band**: -max(4 px, 6 pt) <= sdf <= max(3 px, 3 pt)
- **surround ring**: 6 pt to 14 pt outside the outline
- **full**: sdf <= 0

Regions larger than 600 / 900 px are box-downsampled by 2 / 3 before analysis; every length is converted back
to capture pixels and points, and the factor is logged.

## Registration check

The reference is shifted by the integer offset (within +/-4 px) that minimises mean |dY| over the surround
ring; zero shift is preferred unless another is at least 2% better. The remaining surround residual is
reported as a measurement. Over 5% relative residual flags the pair as not matched.

## Translucency

| Measurement | Definition | Provenance |
|---|---|---|
| Mean relative luminance (glass, reference) | mean Y in the interior | Measured |
| Local luminance difference | mean Y_test - mean Y_ref | Derived |
| Local contrast retention | SD(Y_test) / SD(Y_ref) | Derived |
| Texture retention | mean Sobel magnitude ratio | Derived |
| Background visibility | R^2 of T ~ g (G_s * R) + o | Estimated |
| Effective background transmission g, additive term o | coefficients of that fit | Estimated |
| Spatial variation of transmission | SD of per-tile g (24 pt tiles) | Estimated |
| Color transfer R/G/B | ratio of linear channel means | Derived |

These are effective, composite-level quantities. They are not Apple's alpha, which is not public and which
an adaptive material need not have.

## Blur

`fitBlur` evaluates RMSE of T ~ g (G_s * R) + o over the interior at sigma in {0 ... 48 px}, then refines with a
golden-section search between the neighbours of the best grid point. Reported: sigma (pt), FWHM = 2.3548 sigma,
a fit interval (sigma range within 2% of the minimum RMSE), the residual, and the RMSE-vs-sigma curve. R^2 < 0.9
is reported as "single-Gaussian assumption inadequate". Per-tile fits give blur variation across the surface.

Edge Spread (Step Edge background): for each interior row, the edge column is the strongest horizontal
gradient of the reference; +/-24 px test profiles around it are averaged, normalised, and the 10-90% width,
LSF (derivative) and MTF (|DFT| of the Hann-windowed LSF, normalised at DC) with MTF50 are reported.

## Refraction & distortion

Normalised cross-correlation block matching between the test frame and the reference blurred by the fitted
sigma (15x15 px patches on an 8 px grid, search radius up to 36 capture px), with parabolic sub-pixel
refinement. A vector is rejected when peak NCC < 0.6, when a second peak at least 3 px away exceeds 95% of
the best (ambiguity), when the patch has no texture, or when the best match is on the search boundary.

Reported: p95 ("maximum") and mean apparent displacement, rim vs interior means, mean |dx| and |dy|,
local distortion magnitude (Frobenius norm of the finite-difference deformation gradient), rejected share,
a magnified vector-field image and a magnitude heatmap. The displacement field is not converted to a
refractive index (see MATHEMATICAL_MODELS.md).

## Highlights & edge lighting

Excess luminance E = Y_test - (g G_s * Y_ref + o), with g and o fitted on the interior only, is binned by
signed distance to the outline (1 px bins) overall and in eight direction sectors. Reported: peak excess,
its depth inside the outline, FWHM width, falloff at 2x FWHM, sector asymmetry ((max - min) / mean, with the
brightest and dimmest directions), and the mean gradient magnitude in the rim band. Profiles are stored as
series for plotting.

## Color science

Per pixel: linear P3 -> XYZ (D65) -> CIELAB; CIEDE2000 (Sharma 2005, verified against the published test
pairs in the unit tests). Reported: mean, p95 and max dE00 with a heatmap; dE00 of mean colors; L*; chroma
ratio; hue shift (N/A below C* = 5); WCAG contrast ratio between glass and surround on digital luminance.

## Error metrics

MAE, RMSE (sRGB-encoded channels), PSNR (peak 1), SSIM (Gaussian window sigma 1.5 on Rec.709 luma of
encoded values), edge alignment error between the blur model and the capture. PSNR is never used alone.
