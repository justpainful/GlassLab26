# Component Catalog

Generated from `GlassLab/NativeComponents/ComponentCatalog.swift`. Entry names are experiment cases, not a claim that Apple ships that many glass materials. "Lab" marks entries that open directly in the Experiment Lab canvas; the others are studied through their live demos and Motion recordings.

## Glass Primitives

| Entry | API | Surface / kind | Lab |
|---|---|---|---|
| Regular Glass | `.glassEffect(.regular, in:)` | Liquid Glass rendered by the system | yes |
| Clear Glass | `.glassEffect(.clear, in:)` | Liquid Glass rendered by the system | yes |
| Identity Reference | `.glassEffect(.identity, in:)` | Reference (no material) | yes |
| Tinted Regular Glass | `Glass.regular.tint(_:)` | Liquid Glass rendered by the system | yes |
| Tinted Clear Glass | `Glass.clear.tint(_:)` | Liquid Glass rendered by the system | yes |
| Interactive Regular Glass | `Glass.regular.interactive()` | Liquid Glass rendered by the system | yes |
| Interactive Clear Glass | `Glass.clear.interactive()` | Liquid Glass rendered by the system | yes |
| Glass Button | `.buttonStyle(.glass)` | Button style | yes |
| Glass Prominent Button | `.buttonStyle(.glassProminent)` | Button style | yes |
| Disabled Glass Button | `.buttonStyle(.glass).disabled(true)` | Button style | yes |
| Glass with Text | `.glassEffect() on Text` | Liquid Glass rendered by the system | yes |
| Glass with SF Symbol | `.glassEffect() on Image(systemName:)` | Liquid Glass rendered by the system | yes |
| Glass with Mixed Content | `.glassEffect() on Label` | Liquid Glass rendered by the system | yes |
| Glass on Capsule | `.glassEffect(in: .capsule)` | Liquid Glass rendered by the system | yes |
| Glass on Circle | `.glassEffect(in: .circle)` | Liquid Glass rendered by the system | yes |
| Glass on Rounded Rectangle | `.glassEffect(in: .rect(cornerRadius:))` | Liquid Glass rendered by the system | yes |
| Glass on Supported Custom Shape | `.glassEffect(in: some Shape) with a custom Shape` | Liquid Glass rendered by the system | yes |
| Single Glass Surface | `.glassEffect()` | Liquid Glass rendered by the system | yes |
| Grouped Glass Surfaces | `GlassEffectContainer(spacing:)` | Container | yes |
| Merging Glass Surfaces | `GlassEffectContainer + spacing` | Container | yes |
| Splitting Glass Surfaces | `GlassEffectContainer + glassEffectID` | Container | yes |
| Morphing Glass Surfaces | `glassEffectID(_:in:) + withAnimation` | Transition | yes |
| Overlapping Glass Surfaces | `glassEffect + negative stack spacing` | Container | yes |
| Animated Glass Transitions | `glassEffectTransition(.matchedGeometry / .materialize / .identity)` | Transition | yes |

## Buttons & Controls

| Entry | API | Surface / kind | Lab |
|---|---|---|---|
| Button (bordered) | `Button + .buttonStyle(.bordered)` | Filled platter; not glass |  |
| Icon-only Glass Button | `Button { Image } .buttonStyle(.glass)` | Liquid Glass | yes |
| Text Button (plain) | `Button + .buttonStyle(.plain)` | No platter |  |
| Prominent Button | `.buttonStyle(.borderedProminent) / .glassProminent` | Tinted platter / tinted glass | yes |
| Destructive Action | `Button(role: .destructive)` | Context dependent (red text or tinted) |  |
| Toggle | `Toggle` | Track is opaque; the knob becomes glass while dragged | yes |
| Switch (UISwitch) | `UISwitch` | As Toggle |  |
| Slider | `Slider` | Track opaque; thumb becomes glass while dragged | yes |
| Stepper | `Stepper` | Platter; not glass |  |
| Segmented Control | `Picker.pickerStyle(.segmented)` | Track with a moving selection; selection uses glass during drag | yes |
| UISegmentedControl | `UISegmentedControl` | As segmented | yes |
| Picker (menu) | `Picker.pickerStyle(.menu)` | Menu presented on glass |  |
| Date Picker | `DatePicker (compact / graphical)` | Popover with system material |  |
| Color Picker | `ColorPicker` | System sheet |  |
| Text Field | `TextField` | No glass (field); keyboard is system UI |  |
| Search Field | `.searchable` | Search field in toolbar/tab bar uses glass |  |
| Secure Field | `SecureField` | No glass |  |
| Menu Button | `Menu` | Menu on glass |  |
| Toolbar Buttons | `ToolbarItem / ToolbarItemGroup` | Grouped on a shared glass background |  |
| Disclosure Control | `DisclosureGroup` | No glass |  |
| Contextual Actions | `.contextMenu` | Menu on glass with lifted preview |  |
| Loading State | `ProgressView inside a glass button` | Liquid Glass |  |

## Navigation

| Entry | API | Surface / kind | Lab |
|---|---|---|---|
| Navigation Bar | `NavigationStack + .toolbar` | Bar items float on glass; scroll edge effect beneath |  |
| Large Title | `.navigationBarTitleDisplayMode(.large)` | Title over content; collapses on scroll |  |
| Inline Title | `.navigationBarTitleDisplayMode(.inline)` | Inline title |  |
| Toolbar | `.toolbar { ToolbarItem }` | Items grouped on glass |  |
| Toolbar Item Grouping | `ToolbarItemGroup + ToolbarSpacer + sharedBackgroundVisibility` | Separate glass groups |  |
| Bottom Toolbar | `ToolbarItem(placement: .bottomBar)` | Floating glass items |  |
| Tab Bar | `TabView { Tab }` | Floating glass tab bar |  |
| Floating Tab Bar | `TabView + .tabViewBottomAccessory` | Glass bar with accessory |  |
| Tab Selection | `TabView(selection:)` | Selection lens on glass |  |
| Tab Bar Minimization | `.tabBarMinimizeBehavior(.onScrollDown)` | Collapses to a compact glass control |  |
| Search within Navigation | `.searchable / Tab(role: .search)` | Search field on glass |  |
| Sidebar | `NavigationSplitView sidebar` | Floating glass sidebar on iPad |  |
| Navigation Split View | `NavigationSplitView` | Sidebar + content + detail |  |
| Collapsing Navigation | `Large title collapse on scroll` | Title transitions to inline |  |
| Scroll Edge Effects | `.scrollEdgeEffectStyle(.soft / .hard, for:)` | Soft blur/fade under bars |  |
| Navigation Transitions | `.navigationTransition(.zoom(sourceID:in:))` | Zoom from source |  |
| UINavigationBar (standalone) | `UINavigationBar` | Glass bar items | yes |
| UIToolbar (standalone) | `UIToolbar` | Glass item groups | yes |
| UITabBar (standalone) | `UITabBar` | Glass tab bar | yes |
| UINavigationController | `UINavigationController + UISearchController` | Glass bars, scroll edge effect |  |
| UITabBarController | `UITabBarController + tabBarMinimizeBehavior` | Glass tab bar |  |

## Menus & Presentation

| Entry | API | Surface / kind | Lab |
|---|---|---|---|
| Menu | `Menu` | Glass menu morphing from its button |  |
| Context Menu | `.contextMenu(menuItems:preview:)` | Glass menu + lifted preview |  |
| Selection Menu | `Picker(.menu) / Menu with selection` | Glass menu with checkmark |  |
| Picker Menu | `Picker.pickerStyle(.menu)` | Glass menu |  |
| Confirmation Dialog | `.confirmationDialog` | Action sheet / popover on glass |  |
| Alert | `.alert` | System alert material |  |
| Sheet | `.sheet` | Sheet with glass background at partial height |  |
| Half-height Sheet | `.presentationDetents([.medium])` | Inset glass sheet |  |
| Full-height Sheet | `.presentationDetents([.large])` | Opaque at full height |  |
| Popover | `.popover` | Glass popover (iPad); sheet on iPhone unless adapted |  |
| Content Preview | `.contextMenu(preview:)` | Lifted preview |  |
| SwiftUI Presentation Modifiers | `.presentationBackground / .presentationCornerRadius` | Configurable |  |
| UIKit Sheet | `UISheetPresentationController` | As SwiftUI sheet |  |
| UIKit Alert / Action Sheet | `UIAlertController` | System alert |  |
| UIKit Popover | `UIPopoverPresentationController` | Glass popover |  |
| Search Suggestions | `.searchSuggestions` | Suggestion list |  |
| Edit Menu | `UIEditMenuInteraction (text selection)` | Glass edit menu |  |

## Notifications & Overlays

| Entry | API | Surface / kind | Lab |
|---|---|---|---|
| Local Notifications | `UNUserNotificationCenter.add(_:)` | System banner (system-owned) |  |
| Notification Banners | `UNNotificationPresentationOptions.banner` | System banner |  |
| Foreground Notification Presentation | `userNotificationCenter(_:willPresent:)` | System banner while the app is active |  |
| In-app Alerts | `.alert` | System alert |  |
| Sheets | `.sheet` | Glass sheet |  |
| Popovers | `.popover` | Glass popover |  |
| Menus | `Menu` | Glass menu |  |
| Contextual Overlays | `.contextMenu` | Glass menu |  |
| Progress Overlay (custom) | `ProgressView + .glassEffect()` | Custom composite using native glass |  |
| Custom Toast (custom) | `Text + .glassEffect() + transition` | Custom composite using native glass |  |

## Unsupported native surfaces

- **Lock Screen & Notification Center**: Rendered by SpringBoard. Apps cannot present or capture them; only their own banners can be requested.
- **Control Center**: System UI outside the app's process and capture scope.
- **Home Screen dock, folders and widgets chrome**: System UI. Widgets render in the system with their own containers.
- **Dynamic Island system UI**: Owned by the system. Live Activities (ActivityKit) are presented by iOS and are not capturable by the app.
- **App Switcher**: System UI.
- **Volume / brightness HUDs**: System UI.
- **Siri**: System UI.
- **System keyboard**: Rendered by the keyboard process. It appears in system screenshots but not in view snapshots; it is not part of the lab canvas.
- **Notification banner pixels**: A banner can be triggered with permission, but its timing and composition are controlled by iOS; in-app capture APIs do not include it.
