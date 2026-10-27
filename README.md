# Glass Lab

A native iOS / iPadOS laboratory for observing, measuring and reconstructing Apple's **Liquid Glass**.

Glass Lab renders every reference sample with Apple's public APIs (`glassEffect`, `GlassEffectContainer`,
glass button styles, `UIGlassEffect`, `UIGlassContainerEffect`, system bars and presentations), captures
the composited pixels, and turns them into measurements that carry provenance, uncertainty, confidence and
validity. A separate Reconstruction Lab fits an independent model to those captures.

> Native rendering is the reference. Captured evidence is the source of truth. Every number has provenance.

## Sections

| Section | What it does |
|---|---|
| Explore | 94 catalog entries (glass primitives, controls, navigation, presentation, notifications) with live native demos; list of unsupported system surfaces |
| Experiment Lab | Scene builder (subject, variant, shape, geometry, tint, content, background, appearance, capture method, modules), presets, focus mode, acquisition protocol |
| Optics | Measurement inspector (pixel, region, ruler, profile, magnifier), analysis results, heatmaps |
| Motion | ReplayKit recordings with touch timestamps, frame viewer, slow motion, step-response metrics |
| Compare | Side by side, overlay, difference, split, magnified, edges, false color, dE heatmap, temporal, numerical table; transfer fit and repeatability |
| Sessions | File-based session database, re-analysis, export (ZIP bundle with SHA-256 manifest, CSV, JSON, PDF), verified import |
| Reconstruction | Independent parametric model, Nelder-Mead fitting, sensitivity, identifiability, leave-one-out validation |
| Test Matrix | Full / pairwise / sampled / selected matrices, batches, retry, interrupted-run detection |
| Performance | Display-link timing, hitches, memory footprint, thermal state |
| Models | The equations used, tied to code and presets, with interactive theoretical plots |
| Environment | Device, display, accessibility and power metadata; operator-entered fields; capture validation |

## Build

Requirements: Xcode 26 (iOS 26 SDK) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
```

```bash
xcodegen generate && open GlassLab.xcodeproj
```

CI builds, tests and exports an IPA on every push: see [Documentation/BUILD_AND_SIGNING.md](Documentation/BUILD_AND_SIGNING.md)
and [Documentation/IPA_INSTALLATION.md](Documentation/IPA_INSTALLATION.md).

## Documentation

- [ARCHITECTURE.md](Documentation/ARCHITECTURE.md)
- [COMPONENT_CATALOG.md](Documentation/COMPONENT_CATALOG.md)
- [APPLE_API_MATRIX.md](Documentation/APPLE_API_MATRIX.md)
- [EXPERIMENT_PROTOCOLS.md](Documentation/EXPERIMENT_PROTOCOLS.md)
- [OPTICAL_METHODOLOGY.md](Documentation/OPTICAL_METHODOLOGY.md)
- [MATHEMATICAL_MODELS.md](Documentation/MATHEMATICAL_MODELS.md)
- [MEASUREMENT_VALIDATION.md](Documentation/MEASUREMENT_VALIDATION.md)
- [DATA_FORMATS.md](Documentation/DATA_FORMATS.md)
- [LIMITATIONS.md](Documentation/LIMITATIONS.md)
- [BUILD_AND_SIGNING.md](Documentation/BUILD_AND_SIGNING.md)
- [IPA_INSTALLATION.md](Documentation/IPA_INSTALLATION.md)
- [DEVICE_VALIDATION_CHECKLIST.md](Documentation/DEVICE_VALIDATION_CHECKLIST.md)
