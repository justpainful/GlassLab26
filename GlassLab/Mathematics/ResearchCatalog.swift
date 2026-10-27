import Foundation

/// The models used by the analysers, each tied to the code and the experiment that exercises it.
struct ResearchModel: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var equation: String
    var symbols: [(String, String)]
    var usage: String
    var limits: String
    /// Where the model is computed in the app.
    var implementation: String
    /// A preset that produces data for it.
    var presetName: String?

    static func == (a: ResearchModel, b: ResearchModel) -> Bool { a.title == b.title }
    func hash(into h: inout Hasher) { h.combine(title) }
}

enum ResearchCatalog {
    static let models: [ResearchModel] = [
        ResearchModel(title: "Linear compositing (over operator)",
                      equation: "C = a F + (1 - a) B      (linear light, per channel)",
                      symbols: [("C", "observed color"), ("F", "foreground (material) color"), ("B", "background color"), ("a", "blend factor of the simplified model")],
                      usage: "The multi-background transfer fit estimates T = a R + b per channel from solid-background pairs. Here a is an effective transmission of the background and b = a_F F an effective additive term.",
                      limits: "Exact only for a spatially uniform, non-adaptive layer. Liquid Glass blurs, warps, adapts contrast to what is behind it and adds rim lighting, so a and b change with the background. Residuals over 3+ backgrounds measure that departure. a is not Apple's internal alpha.",
                      implementation: "ComparisonEngine.transferFit", presetName: "Clear Glass on Black"),
        ResearchModel(title: "Spatial blur (convolution)",
                      equation: "I_b(x, y) = (I * K)(x, y),   K_G(r) = exp(-r^2 / 2 s^2) / (2 pi s^2)",
                      symbols: [("I", "background image"), ("K", "kernel"), ("s", "Gaussian sigma")],
                      usage: "Blur analysis fits T ~ g (G_s * R) + o inside the glass interior and reports s as an apparent blur radius with a fit interval. Box, anisotropic or spatially varying kernels show up as a low R^2 and as tile-to-tile sigma variation.",
                      limits: "A Gaussian fit describes the apparent smoothing; it does not establish which kernel the system uses. Refraction inside the region inflates the residual.",
                      implementation: "OpticalAnalyzer.fitBlur, tileBlur", presetName: "Glass on Checkerboard"),
        ResearchModel(title: "Edge spread, line spread and MTF",
                      equation: "LSF(x) = d ESF(x) / dx,    MTF(f) = |F{LSF}(f)| / |F{LSF}(0)|",
                      symbols: [("ESF", "edge profile across a step edge"), ("f", "spatial frequency, cycles/pt")],
                      usage: "With the Step Edge background, rows crossing the edge are aligned on the reference edge position and averaged; the 10-90% width, LSF peak and MTF50 are reported.",
                      limits: "Straight (non-slanted) edge: sub-pixel sampling is limited to the capture grid. Differentiation amplifies noise; a Hann window limits frequency resolution.",
                      implementation: "OpticalAnalyzer.edgeSpread", presetName: "Edge Refraction Calibration"),
        ResearchModel(title: "Snell's law (interpretive)",
                      equation: "n1 sin(t1) = n2 sin(t2)",
                      symbols: [("n", "refractive index"), ("t", "angle from the surface normal")],
                      usage: "Used to interpret measured displacement fields: a thin lens-like rim with a curved profile displaces background content toward or away from the outline.",
                      limits: "Liquid Glass is computed, not a physical slab. A displacement field alone cannot identify n without a surface-height model; the app never reports an index of refraction.",
                      implementation: "Theory only (Reconstruction model uses a rim-weighted normal displacement)", presetName: nil),
        ResearchModel(title: "Schlick Fresnel approximation (interpretive)",
                      equation: "F(t) = F0 + (1 - F0)(1 - cos t)^5",
                      symbols: [("F0", "reflectance at normal incidence"), ("t", "view angle")],
                      usage: "A reference shape for rim brightening: reflectance rises steeply toward grazing angles, i.e. toward the outline of a curved surface.",
                      limits: "The rim highlight profile is measured as excess luminance versus distance from the outline; fitting Schlick to it would need an assumed surface profile.",
                      implementation: "Theory only; compare with Highlights edge profile", presetName: nil),
        ResearchModel(title: "Block-matching displacement field",
                      equation: "d*(p) = argmax_d NCC(T[p + W], R_s[p + d + W])",
                      symbols: [("W", "15x15 patch"), ("R_s", "reference blurred by the fitted sigma"), ("NCC", "normalised cross-correlation")],
                      usage: "Estimates where each test patch's content comes from. Vectors with NCC < 0.6, ambiguous peaks (second peak > 95%) or boundary hits are rejected. Statistics, components and the deformation gradient |grad u| are derived.",
                      limits: "Needs aperiodic texture (Random Dots, Noise, fiducial checker). Strong blur and brightening reduce NCC. Sub-pixel accuracy is limited to roughly 0.1-0.25 px.",
                      implementation: "OpticalAnalyzer.displacementField", presetName: "Glass on Random Dots"),
        ResearchModel(title: "CIE colorimetry and CIEDE2000",
                      equation: "XYZ = M_P3 * RGB_lin;  L* = 116 f(Y/Yn) - 16;  dE00 (Sharma et al. 2005)",
                      symbols: [("RGB_lin", "linear Display P3 after decoding the embedded profile"), ("Yn", "D65 white")],
                      usage: "All color differences, chroma ratios, hue shifts and WCAG contrast ratios are computed on linear values decoded through Core Graphics color management.",
                      limits: "Values are relative to display white; they are not photometric. Without an external photometer no nits are reported.",
                      implementation: "ColorScience", presetName: "Tinted Glass on Photography"),
        ResearchModel(title: "Image error metrics",
                      equation: "MAE, RMSE, PSNR = 10 log10(1/MSE), SSIM (Wang et al. 2004), edge alignment error",
                      symbols: [("MSE", "mean squared error of sRGB-encoded channels")],
                      usage: "Quantify how much the glass changes the image, and how far a reconstruction is from Apple's rendering.",
                      limits: "PSNR alone is not a similarity verdict; SSIM, dE00 and edge alignment are reported with it.",
                      implementation: "ImageMetrics", presetName: nil),
        ResearchModel(title: "Second-order step response",
                      equation: "x(t) = 1 - e^(-z w t)(cos(w_d t) + z / sqrt(1 - z^2) sin(w_d t)),  w_d = w sqrt(1 - z^2)",
                      symbols: [("w", "natural angular frequency"), ("z", "damping ratio")],
                      usage: "Fitted to the apparent width of a glass element after a press to describe overshoot and settling; damping is also estimated from the logarithmic decrement.",
                      limits: "A descriptive fit to the captured motion, limited by the capture frame interval. It is not the system's animation implementation.",
                      implementation: "TimeSeries.fitSpring, MotionAnalyzer", presetName: "Interactive Glass Press Test"),
    ]

    static let limitations: [String] = [
        "Liquid Glass is rendered by the system compositor. Apple publishes no internal parameters; every optical value here is an apparent or effective quantity derived from captured pixels.",
        "Captured pixel values are digital, display-referred values relative to display white. Brightness in nits, True Tone and Night Shift are not reflected in captures and are not measured.",
        "View snapshots (drawHierarchy) may not include every system compositing effect; each capture method must pass Capture Validation on each device and OS version, otherwise its measurements are rejected.",
        "ReplayKit frames are YCbCr 4:2:0: chroma resolution is half of luma, which affects fine color edges. System screenshots are lossless.",
        "ReplayKit delivers frames when the screen changes; the timing resolution of motion analysis is the capture interval, usually 1/60 s, and short responses are flagged.",
        "CADisplayLink callbacks show when the app could draw, not how many frames the render server produced. GPU time and power in watts are not available to apps and are not shown.",
        "Accessibility and appearance settings cannot be changed by the app. They are read through public APIs and recorded; the operator sets them in Settings.",
        "The simulator renders Liquid Glass with a different pipeline; simulator captures are marked and must not be used as visual references.",
        "Rounded rectangles use circular corners in the lab so the analysis mask matches the outline exactly; continuous-corner shapes differ by under a pixel near corners for typical radii.",
        "iOS 27 SDK APIs (for example ScreenCaptureKit on iOS) are not compiled into this build because the CI toolchain ships the iOS 26.5 SDK.",
    ]
}
