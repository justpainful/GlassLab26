# Limitations

## Imposed by Apple's platform

- **No internal parameters.** Apple publishes no blur radius, refraction index, alpha or lighting model for
  Liquid Glass. Every optical number is an apparent or effective quantity derived from pixels.
- **Capture paths.** iOS apps can capture their own composited output via ReplayKit, render their own view
  hierarchy via `drawHierarchy`, or read screenshots the user takes. ScreenCaptureKit is not in the iOS 26.5
  SDK. Each path must be validated per device and OS; a failed path is rejected.
- **ReplayKit** delivers YCbCr 4:2:0 frames (half-resolution chroma), only when the screen changes, at up
  to the display rate. Video encodings (HEVC, ProRes 4444) are lossy.
- **System screenshots** are lossless but need the operator's button press and Photos access.
- **Display-referred values.** Captured pixels do not include display brightness, True Tone, Night Shift or
  panel characteristics. No luminance in nits is reported without an external photometer.
- **System UI** (Notification Center, Control Center, Lock Screen, Dynamic Island, keyboard process,
  banners) cannot be created at will or captured in-app; see the Unsupported Native Surfaces list.
- **Settings.** Accessibility and appearance settings cannot be changed by apps. The app reads them and the
  operator sets them in Settings; appearance can be applied to the app's own window.
- **Performance.** GPU time per frame and power draw are not available to apps; display-link callbacks are
  not rendered frames. Use Instruments and MetricKit.

## Imposed by this build

- **iOS 27.** The CI image has Xcode 26.6 with the iOS 26.5 SDK, so iOS 27 APIs are not compiled. The app
  runs on iOS 27 devices using iOS 26 APIs; behaviour changes in iOS 27 are what the lab is meant to record.
- **Rounded corners.** The lab uses circular-corner rounded rectangles so the analysis mask is exact.
- **UIKit outlines.** UIKit glass views support corner configurations only; ellipse and star fall back to a
  capsule, and the mask follows the actual outline.
- **ESF** uses a straight vertical edge (not a slanted edge), limiting sub-pixel sampling.
- **Displacement** needs aperiodic texture and degrades where blur is strong.
- **Motion region** is the bounding box of thresholded change against the first frame, a proxy for the glass
  outline, not a segmentation.
- **Reconstruction** runs on the CPU at <= 160 px per sample; it is not a real-time engine. A Metal
  implementation is a future step.
- **Simulator** renders Liquid Glass differently; simulator captures are labelled and must not be used as
  visual references. CI tests run only on the simulator.
- **Signing.** The repository has no signing secrets, so CI produces an unsigned IPA until they are added.

## Not verified yet (needs a physical device)

- Which capture methods pass validation on each device/OS.
- Settle thresholds for every subject type on device.
- ReplayKit orientation handling on iPad in all orientations and in Stage Manager (refused when the window
  is not full screen).
- The behaviour of every catalog demo on iPhone and iPad hardware.
