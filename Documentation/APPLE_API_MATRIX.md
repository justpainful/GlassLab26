# Apple API Matrix

Verified against the iOS 26.5 SDK shipped with Xcode 26.6 on the GitHub `macos-26` runner (the SwiftUI and
SwiftUICore `.swiftinterface` files and UIKit headers were inspected by a probe workflow before coding).

| API | Framework | Availability (SDK) | Used in Glass Lab |
|---|---|---|---|
| `Glass.regular`, `.clear`, `.identity` | SwiftUI(Core) | iOS 26.0 | `NativeGlass.glass` |
| `Glass.tint(_:)`, `Glass.interactive(_:)` | SwiftUI(Core) | iOS 26.0 | tint and interactive settings |
| `View.glassEffect(_:in:)` | SwiftUI(Core) | iOS 26.0 | every SwiftUI glass surface |
| `GlassEffectContainer(spacing:content:)` | SwiftUI(Core) | iOS 26.0 | groups, merge/split, performance lab |
| `glassEffectID(_:in:)` | SwiftUI(Core) | iOS 26.0 | morph, appear/disappear |
| `glassEffectUnion(id:namespace:)` | SwiftUI(Core) | iOS 26.0 | "glassEffectUnion (all)" option |
| `glassEffectTransition(_:)` with `.matchedGeometry`, `.materialize`, `.identity` | SwiftUI(Core) | iOS 26.0 | transitions demo |
| `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)` | SwiftUI | iOS 26.0 | glass button subjects and app actions |
| `.buttonStyle(.glass(_:))` / `GlassButtonStyle.init(_:)` | SwiftUI | **iOS 26.1** | `.glass(.clear)` subject, guarded by `#available(iOS 26.1, *)` |
| `ToolbarSpacer`, `sharedBackgroundVisibility(_:)` | SwiftUI | iOS 26.0 | toolbar grouping demo |
| `tabBarMinimizeBehavior(_:)`, `tabViewBottomAccessory(content:)` (the `isEnabled:` form is iOS 26.1) | SwiftUI | iOS 26.0 | tab bar demos |
| `scrollEdgeEffectStyle(_:for:)` | SwiftUI | iOS 26.0 | scroll edge demo |
| `backgroundExtensionEffect()` | SwiftUI | iOS 26.0 | not used (documented) |
| `UIGlassEffect(style: .regular/.clear)`, `tintColor`, `isInteractive` | UIKit | iOS 26.0 | `UIKitGlassSurface` |
| `UIGlassContainerEffect.spacing` | UIKit | iOS 26.0 | UIKit groups |
| `UIView.cornerConfiguration`, `UICornerConfiguration` | UIKit | iOS 26.0 | UIKit glass outlines |
| `UIVisualEffectView` | UIKit | iOS 8 | host of UIKit glass |
| `UINavigationBar`, `UIToolbar`, `UITabBar`, `UISegmentedControl` | UIKit | system | standalone lab subjects |
| `UINavigationController`, `UITabBarController.tabBarMinimizeBehavior` | UIKit | iOS 26 | navigation demos |
| `UISheetPresentationController`, `UIAlertController`, `UIPopoverPresentationController` | UIKit | system | presentation demos |
| `UNUserNotificationCenter` | UserNotifications | system | notification lab |
| `RPScreenRecorder.startCapture` / `stopCapture` | ReplayKit | iOS 11 (not deprecated in 26.5) | ReplayKit capture and recording |
| `UIWindow.drawHierarchy(in:afterScreenUpdates:)` | UIKit | system | view snapshot capture (must pass validation) |
| `UIApplication.userDidTakeScreenshotNotification` + PhotoKit | UIKit / Photos | system | system screenshot capture |
| `CADisplayLink`, `CACurrentMediaTime` | QuartzCore | system | timing |
| ScreenCaptureKit (`SCStream`, `SCContentSharingPicker`) | ScreenCaptureKit | **absent from the iOS 26.5 SDK** | not used; see LIMITATIONS |

## Not used, on purpose

- No private API, no private selector lookups, no reading of system processes.
- No Metal shader or blur/gradient imitation of Liquid Glass in reference experiments. The only custom
  renderer is `ReconstructionRenderer`, confined to the Reconstruction section and labelled as Glass Lab's model.
- Custom composites (progress overlay, toast) use native `glassEffect` and are labelled "custom".

## iOS 27

The runner image provides no Xcode 27 / iOS 27 SDK, so iOS 27-only APIs cannot be compiled or verified in CI.
The deployment target is iOS 26.0. When an Xcode 27 image is available, set `XCODE_VERSION` in the workflow,
re-run the probe in the workflow history, and add `#available(iOS 27, *)` paths.
