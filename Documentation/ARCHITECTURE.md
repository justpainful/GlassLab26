# Architecture

Glass Lab separates **native rendering** (what Apple draws) from **measurement** (what the app computes
from captured pixels). The rendering layer never reads analysis state, and analysis never draws glass.

```
GlassLab/
  App/              AppModel (object graph), AppShell (tab bar / iPad sidebar), app delegate
  Core/             Formatting, logging, errors, DeviceEnvironmentMonitor, MemoryProbe, ResourceGuard
  Models/           Provenance & Measurement, SceneConfiguration, BackgroundSpec, Session records, EnvironmentSnapshot
  NativeComponents/ NativeGlassRenderer (all subjects), UIKit components, ComponentCatalog, ComponentDemos, NotificationLab
  Experiments/      ExperimentCanvas (StageState, CanvasProbe), Presets, TestMatrix, InteractionDriver
  Backgrounds/      BackgroundEngine: deterministic procedural, imported image and video backgrounds
  Capture/          CaptureCoordinator (protocol, settle detection, validation), ReplayKitCapture, ScreenshotIngest
  Recording/        TouchObserverRecognizer, DisplayLinkLogger, InteractionRecorder
  Analysis/         LinearImage/Plane/Mask, RegionModel (SDF masks), OpticalAnalyzer, ImageMetrics, Heatmap,
                    MotionAnalyzer, MeasurementEngine (off-main orchestration), ComparisonEngine
  Mathematics/      ColorScience, Statistics, Optimization, TimeSeries, ResearchCatalog
  Reconstruction/   ReconstructionModel (independent renderer), ParameterEstimator
  Storage/          DataStore (file-based session database), FrameWriter (PNG + SHA-256)
  Export/           ExportManager (CSV/JSON/bundle/import), ZipArchive, ReportGenerator (PDF)
  UI/               One view per section plus shared components and the measurement inspector
GlassLabTests/      Unit and integration tests (simulator)
GlassLabUITests/    Navigation and flow tests (simulator)
```

The requested component names map as follows: AppShell, ComponentCatalog, NativeGlassRenderer
(`NativeGlass`, `NativeSubjectView`, `UIKitGlassSurface`), ExperimentScene (`ExperimentCanvas` + `StageState`),
SceneConfiguration, BackgroundEngine, MeasurementEngine, OpticalAnalyzer (translucency, blur, ESF/MTF,
refraction, highlights), ColorAnalyzer (`ColorScience` + `OpticalAnalyzer.colorMeasurements`), MotionAnalyzer,
InteractionAnalyzer (`InteractionRecorder` + motion step-response), CaptureCoordinator, ExperimentRecorder
(`CaptureCoordinator.acquire` + `FrameWriter`), ComparisonEngine, ParameterEstimator, ReportGenerator,
DataStore, ExportManager, DeviceEnvironmentMonitor, AccessibilityEnvironmentMonitor (part of
`DeviceEnvironmentMonitor`, which observes every public accessibility notification), ReconstructionLab.

## Data flow of one experiment

1. `StageState.config` (a `SceneConfiguration`) drives `ExperimentCanvas`, which draws `BackgroundView` and
   `NativeSubjectView`. The canvas reports its window frame (`WindowFrameReader`) and each glass element's
   frame (`ElementFramesKey`) into `CanvasProbe`.
2. `CaptureCoordinator.acquire` freezes the background phase, renders the reference (identity glass or hidden
   subject), waits until two consecutive captures differ by less than 0.0015 mean |dY|, captures, enables the
   native glass, waits again, captures. Frames are cropped to the canvas and written as PNG with their
   embedded color profile and SHA-256.
3. `MeasurementEngine.analyze` verifies the SHA-256 of both frames, decodes them to linear Display P3 floats
   off the main thread, builds a `GlassRegionModel` from the recorded element frames, and runs
   `OpticalAnalyzer.analyze`. Results are appended as an `AnalysisRun` with algorithm versions; derived
   images (heatmaps, vector fields) are saved next to the session.
4. The session JSON is written atomically after every change, so a crash leaves the last complete state.

## Concurrency and resources

- UI state classes are `@MainActor @Observable`. Image decoding, analysis, export and fitting run in
  detached tasks and check `Task.isCancelled` inside their loops.
- `ResourceGuard` refuses heavy work when the thermal state is Serious/Critical or an operation would need
  more than half of `os_proc_available_memory()`.
- Video is never decoded into memory: `MotionAnalyzer` streams frames with `AVAssetReader`, keeping two
  downsampled luma frames at a time.
- Captures stop when less than 200 MB of storage is free.
- Moving to the background cancels analysis and stops ReplayKit capture.

## Why the measurement layer cannot disturb the reference

- The instruction/status strip is laid out above the canvas, never over it, so it is outside every crop.
- Only the visible canvas reports geometry (`ExperimentCanvas.reports`), so focus mode and the inline canvas
  never disagree.
- Live analysis does not run while capturing; analysis starts after both frames are stored.
