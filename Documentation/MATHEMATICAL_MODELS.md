# Mathematical Models

The same catalog is in the app (Models section, `ResearchCatalog.swift`), each entry linked to the code
that computes it and a preset that produces data for it. Plots in the app are Theoretical.

## Compositing

C = a F + (1 - a) B, per channel, in linear light.

Glass Lab fits T = a R + b across solid backgrounds (`ComparisonEngine.transferFit`). `a` is an effective
background transmission and `b = a_F F` an effective additive term. The model is exact for a uniform,
non-adaptive layer only. Liquid Glass blurs, warps, adapts to the luminance behind it and adds rim light;
with three or more backgrounds the residual measures how far the composite departs from linear. `a` is never
reported as Apple's alpha.

## Spatial blur

I_b = I * K. Kernels: Gaussian (fitted), box, anisotropic and spatially varying (detected indirectly through
low R^2 and tile-to-tile sigma spread). The fit T ~ g (G_s * R) + o is descriptive.

## Edge, line and modulation transfer

LSF = d ESF / dx; MTF(f) = |F{LSF}(f)| / |F{LSF}(0)|; for a Gaussian, 10-90% width = 2.563 sigma.

## Refraction (interpretive)

Snell: n1 sin t1 = n2 sin t2. Schlick: F(t) = F0 + (1 - F0)(1 - cos t)^5.

Liquid Glass is a computed effect. Measured displacement depends on an unknown "surface profile" and on how
the renderer maps it; without a defined and verified height model, n is not identifiable from images, so no
refractive index is reported. The Reconstruction model uses a rim-weighted displacement along the outline
normal, d(p) = k (1 + s/w)^2 n(p) for -w <= s <= 0 (s = signed distance), as an empirical description.

## Image error metrics

| Metric | Use | Caveat |
|---|---|---|
| MAE / RMSE | overall magnitude of change | not perceptual |
| PSNR | comparability with literature | never used alone |
| SSIM | structure retention | defined on encoded luma |
| dE00 | perceptual color difference per pixel | reference viewing conditions |
| Edge alignment error | geometric warping vs a blur-only model | depends on edge threshold |
| Warp field error | difference of two displacement fields (Compare, Reconstruction) | needs accepted vectors in both |
| Temporal error | RMS difference of two motion time series | resampled to A's time base |

## Time series

Onset (first sample leaving 4x baseline noise), 10-90% rise by linear interpolation, settling into a 5% band,
overshoot (peak - final) / step, oscillation frequency from the median half-period between extrema, damping
from the logarithmic decrement z = d / sqrt(4 pi^2 + d^2), and a second-order step response fitted by
Nelder-Mead:

x(t) = 1 - e^(-z w t) (cos w_d t + z / sqrt(1 - z^2) sin w_d t), w_d = w sqrt(1 - z^2).

All are limited by the capture frame interval; values below three intervals are flagged. A fitted spring
describes the observed motion; it does not reveal the system's animation implementation.

## Statistics

Mean, median, sample SD, min/max, 95% CI of the mean with Student t (tabulated to df = 30, interpolated to
120, 1.96 beyond), modified z-score outliers (|z| > 3.5 with MAD x 1.4826), ordinary least squares.

## Reconstruction fitting

Loss: mean squared error over glass pixels plus a 2 pt band (linear RGB). Optimiser: bounded Nelder-Mead
from two starts. Sensitivity: relative loss increase for a +10% step. Standard error (approximate):
SE_i = sqrt(2 L / (N H_ii)) from the diagonal Hessian (ignores correlations). A parameter is "not
identifiable" when the loss is flat in its direction. Generalisation: leave-one-out over samples.
