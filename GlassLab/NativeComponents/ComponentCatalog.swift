import Foundation

enum ComponentGroup: String, CaseIterable, Identifiable {
    case primitives = "Glass Primitives"
    case controls = "Buttons & Controls"
    case navigation = "Navigation"
    case presentation = "Menus & Presentation"
    case overlays = "Notifications & Overlays"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .primitives: return "circle.lefthalf.filled"
        case .controls: return "switch.2"
        case .navigation: return "sidebar.left"
        case .presentation: return "rectangle.portrait.on.rectangle.portrait"
        case .overlays: return "bell.badge"
        }
    }
}

/// Catalog entry. Names are experiment cases, not claims that Apple ships that many glass materials.
struct ComponentDescriptor: Identifiable, Hashable {
    var id: String
    var name: String
    var group: ComponentGroup
    var kind: String
    var framework: String
    var api: String
    var minOS: String = "iOS 26.0"
    /// How the system renders the main surface (glass, glass on interaction, or no glass).
    var surface: String
    var states: [String]
    var factors: [String]
    var experiments: [String]
    var settings: [String]
    var deviceNotes: String
    /// Configuration to open in the Experiment Lab, when the lab canvas can host this component.
    var labConfig: SceneConfiguration?

    static func == (a: ComponentDescriptor, b: ComponentDescriptor) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum ComponentCatalog {
    private static func cfg(_ f: (inout SceneConfiguration) -> Void) -> SceneConfiguration {
        var c = SceneConfiguration(); f(&c); return c
    }

    private static let glassFactors = ["Background luminance and texture", "Shape and size", "Tint", "Interactivity", "Appearance (light/dark)", "Reduce Transparency / Increase Contrast"]
    private static let glassExperiments = ["Translucency", "Blur", "Refraction", "Highlights", "Color", "Motion (if interactive)"]
    private static let glassSettings = ["Variant", "Shape", "Width/Height/Corner", "Tint", "Interactive", "Content", "Background"]

    private static func primitive(_ id: String, _ name: String, api: String, kind: String = "Glass effect", minOS: String = "iOS 26.0",
                                  states: [String] = ["Static"], _ setup: @escaping (inout SceneConfiguration) -> Void) -> ComponentDescriptor {
        ComponentDescriptor(id: id, name: name, group: .primitives, kind: kind, framework: "SwiftUI", api: api, minOS: minOS,
                            surface: "Liquid Glass rendered by the system", states: states, factors: glassFactors, experiments: glassExperiments,
                            settings: glassSettings, deviceNotes: "Same API on iPhone and iPad; the rendered material can differ with display and GPU.",
                            labConfig: cfg { c in c.name = name; setup(&c) })
    }

    static let primitives: [ComponentDescriptor] = [
        primitive("regular", "Regular Glass", api: ".glassEffect(.regular, in:)") { $0.variant = .regular },
        primitive("clear", "Clear Glass", api: ".glassEffect(.clear, in:)") { $0.variant = .clear },
        primitive("identity", "Identity Reference", api: ".glassEffect(.identity, in:)", kind: "Reference (no material)") { $0.variant = .identity },
        primitive("tintedRegular", "Tinted Regular Glass", api: "Glass.regular.tint(_:)") { $0.variant = .regular; $0.tint = RGBAColor(0, 0.48, 1, 0.6) },
        primitive("tintedClear", "Tinted Clear Glass", api: "Glass.clear.tint(_:)") { $0.variant = .clear; $0.tint = RGBAColor(1, 0.3, 0.4, 0.6) },
        primitive("interactiveRegular", "Interactive Regular Glass", api: "Glass.regular.interactive()", states: ["Idle", "Touch down", "Drag", "Release"]) { $0.interactive = true; $0.content = .symbol; $0.interaction = .pressAndHold },
        primitive("interactiveClear", "Interactive Clear Glass", api: "Glass.clear.interactive()", states: ["Idle", "Touch down", "Drag", "Release"]) { $0.variant = .clear; $0.interactive = true; $0.content = .symbol; $0.interaction = .pressAndHold },
        primitive("glassButton", "Glass Button", api: ".buttonStyle(.glass)", kind: "Button style", states: ["Normal", "Pressed"]) { $0.subject = .glassButton; $0.content = .text; $0.referenceMode = .subjectHidden },
        primitive("glassProminent", "Glass Prominent Button", api: ".buttonStyle(.glassProminent)", kind: "Button style", states: ["Normal", "Pressed"]) { $0.subject = .glassProminentButton; $0.content = .text; $0.referenceMode = .subjectHidden },
        primitive("glassDisabled", "Disabled Glass Button", api: ".buttonStyle(.glass).disabled(true)", kind: "Button style", states: ["Disabled"]) { $0.subject = .glassButton; $0.content = .text; $0.referenceMode = .subjectHidden },
        primitive("glassText", "Glass with Text", api: ".glassEffect() on Text") { $0.content = .text },
        primitive("glassSymbol", "Glass with SF Symbol", api: ".glassEffect() on Image(systemName:)") { $0.content = .symbol; $0.shape = .circle; $0.geometry.width = 88 },
        primitive("glassMixed", "Glass with Mixed Content", api: ".glassEffect() on Label") { $0.content = .mixed },
        primitive("capsule", "Glass on Capsule", api: ".glassEffect(in: .capsule)") { $0.shape = .capsule },
        primitive("circle", "Glass on Circle", api: ".glassEffect(in: .circle)") { $0.shape = .circle; $0.geometry.width = 120; $0.geometry.height = 120 },
        primitive("roundedRect", "Glass on Rounded Rectangle", api: ".glassEffect(in: .rect(cornerRadius:))") { $0.shape = .roundedRect; $0.geometry.height = 140 },
        primitive("customShape", "Glass on Supported Custom Shape", api: ".glassEffect(in: some Shape) with a custom Shape") { $0.shape = .customStar; $0.geometry.width = 180; $0.geometry.height = 180 },
        primitive("single", "Single Glass Surface", api: ".glassEffect()") { _ in },
        primitive("grouped", "Grouped Glass Surfaces", api: "GlassEffectContainer(spacing:)", kind: "Container") { $0.subject = .glassGroup; $0.geometry.elementCount = 3; $0.geometry.width = 72; $0.geometry.height = 72; $0.shape = .circle; $0.content = .symbol },
        primitive("merging", "Merging Glass Surfaces", api: "GlassEffectContainer + spacing", kind: "Container", states: ["Separated", "Blending", "Merged"]) { $0.subject = .glassGroup; $0.geometry.elementCount = 2; $0.geometry.width = 80; $0.geometry.height = 80; $0.shape = .circle; $0.interaction = .merge },
        primitive("splitting", "Splitting Glass Surfaces", api: "GlassEffectContainer + glassEffectID", kind: "Container", states: ["Merged", "Splitting", "Separated"]) { $0.subject = .glassGroup; $0.geometry.elementCount = 2; $0.geometry.width = 80; $0.geometry.height = 80; $0.shape = .circle; $0.interaction = .split },
        primitive("morphing", "Morphing Glass Surfaces", api: "glassEffectID(_:in:) + withAnimation", kind: "Transition", states: ["Collapsed", "Expanded"]) { $0.subject = .glassGroup; $0.geometry.elementCount = 3; $0.geometry.width = 64; $0.geometry.height = 64; $0.shape = .circle; $0.interaction = .morph },
        primitive("overlapping", "Overlapping Glass Surfaces", api: "glassEffect + negative stack spacing", kind: "Container") { $0.subject = .glassGroup; $0.geometry.elementCount = 2; $0.geometry.width = 120; $0.geometry.height = 120; $0.shape = .circle; $0.geometry.elementSpacing = -40 },
        primitive("transitions", "Animated Glass Transitions", api: "glassEffectTransition(.matchedGeometry / .materialize / .identity)", kind: "Transition", states: ["Appearing", "Disappearing"]) { $0.subject = .glassGroup; $0.geometry.elementCount = 2; $0.interaction = .appear },
    ]

    private static func control(_ id: String, _ name: String, api: String, surface: String, states: [String], lab: SubjectKind? = nil, framework: String = "SwiftUI") -> ComponentDescriptor {
        ComponentDescriptor(id: id, name: name, group: .controls, kind: "Control", framework: framework, api: api, surface: surface, states: states,
                            factors: ["Tint / accent", "Appearance", "Dynamic Type", "Increase Contrast", "Interaction"],
                            experiments: ["Color", "Motion", "Highlights (where glass appears)"], settings: ["State", "Tint", "Appearance"],
                            deviceNotes: "Metrics follow the system size class; iPad uses pointer hover effects.",
                            labConfig: lab.map { k in cfg { $0.subject = k; $0.name = name; $0.referenceMode = .subjectHidden; $0.geometry.width = 260 } })
    }

    static let controls: [ComponentDescriptor] = [
        control("button", "Button (bordered)", api: "Button + .buttonStyle(.bordered)", surface: "Filled platter; not glass", states: ["Normal", "Pressed", "Disabled"]),
        control("iconButton", "Icon-only Glass Button", api: "Button { Image } .buttonStyle(.glass)", surface: "Liquid Glass", states: ["Normal", "Pressed", "Disabled"], lab: .glassButton),
        control("textButton", "Text Button (plain)", api: "Button + .buttonStyle(.plain)", surface: "No platter", states: ["Normal", "Pressed", "Disabled"]),
        control("prominent", "Prominent Button", api: ".buttonStyle(.borderedProminent) / .glassProminent", surface: "Tinted platter / tinted glass", states: ["Normal", "Pressed", "Disabled"], lab: .glassProminentButton),
        control("destructive", "Destructive Action", api: "Button(role: .destructive)", surface: "Context dependent (red text or tinted)", states: ["Normal", "Pressed"]),
        control("toggle", "Toggle", api: "Toggle", surface: "Track is opaque; the knob becomes glass while dragged", states: ["On", "Off", "Dragging", "Disabled"], lab: .toggle),
        control("switch", "Switch (UISwitch)", api: "UISwitch", surface: "As Toggle", states: ["On", "Off", "Disabled"], framework: "UIKit"),
        control("slider", "Slider", api: "Slider", surface: "Track opaque; thumb becomes glass while dragged", states: ["Idle", "Dragging", "Disabled"], lab: .slider),
        control("stepper", "Stepper", api: "Stepper", surface: "Platter; not glass", states: ["Normal", "Pressed", "At bound"]),
        control("segmented", "Segmented Control", api: "Picker.pickerStyle(.segmented)", surface: "Track with a moving selection; selection uses glass during drag", states: ["Selected", "Dragging"], lab: .segmentedControl),
        control("uiSegmented", "UISegmentedControl", api: "UISegmentedControl", surface: "As segmented", states: ["Selected"], lab: .uikitSegmented, framework: "UIKit"),
        control("picker", "Picker (menu)", api: "Picker.pickerStyle(.menu)", surface: "Menu presented on glass", states: ["Closed", "Open"]),
        control("datePicker", "Date Picker", api: "DatePicker (compact / graphical)", surface: "Popover with system material", states: ["Compact", "Expanded"]),
        control("colorPicker", "Color Picker", api: "ColorPicker", surface: "System sheet", states: ["Closed", "Presented"]),
        control("textField", "Text Field", api: "TextField", surface: "No glass (field); keyboard is system UI", states: ["Normal", "Focused", "Disabled"]),
        control("searchField", "Search Field", api: ".searchable", surface: "Search field in toolbar/tab bar uses glass", states: ["Idle", "Focused", "Typing"]),
        control("secureField", "Secure Field", api: "SecureField", surface: "No glass", states: ["Normal", "Focused"]),
        control("menuButton", "Menu Button", api: "Menu", surface: "Menu on glass", states: ["Closed", "Open"]),
        control("toolbarButton", "Toolbar Buttons", api: "ToolbarItem / ToolbarItemGroup", surface: "Grouped on a shared glass background", states: ["Normal", "Pressed"]),
        control("disclosure", "Disclosure Control", api: "DisclosureGroup", surface: "No glass", states: ["Collapsed", "Expanded"]),
        control("contextual", "Contextual Actions", api: ".contextMenu", surface: "Menu on glass with lifted preview", states: ["Idle", "Pressed", "Presented"]),
        control("loading", "Loading State", api: "ProgressView inside a glass button", surface: "Liquid Glass", states: ["Loading"]),
    ]

    private static func nav(_ id: String, _ name: String, api: String, surface: String, notes: String, framework: String = "SwiftUI", lab: SubjectKind? = nil) -> ComponentDescriptor {
        ComponentDescriptor(id: id, name: name, group: .navigation, kind: "Navigation", framework: framework, api: api, surface: surface,
                            states: ["Rest", "Scrolled", "Transitioning"], factors: ["Scroll position", "Content under the bar", "Size class", "Appearance"],
                            experiments: ["Motion (scroll, push/pop)", "Translucency of bars", "Scroll edge effect"], settings: ["Title mode", "Items", "Scroll content"],
                            deviceNotes: notes,
                            labConfig: lab.map { k in cfg { $0.subject = k; $0.name = name; $0.referenceMode = .subjectHidden; $0.geometry.width = 390; $0.background.kind = .scrollingContent } })
    }

    static let navigation: [ComponentDescriptor] = [
        nav("navBar", "Navigation Bar", api: "NavigationStack + .toolbar", surface: "Bar items float on glass; scroll edge effect beneath", notes: "Compact height on iPhone landscape."),
        nav("largeTitle", "Large Title", api: ".navigationBarTitleDisplayMode(.large)", surface: "Title over content; collapses on scroll", notes: "iPhone and iPad."),
        nav("inlineTitle", "Inline Title", api: ".navigationBarTitleDisplayMode(.inline)", surface: "Inline title", notes: "iPhone and iPad."),
        nav("toolbar", "Toolbar", api: ".toolbar { ToolbarItem }", surface: "Items grouped on glass", notes: "Placement differs between size classes."),
        nav("toolbarGrouping", "Toolbar Item Grouping", api: "ToolbarItemGroup + ToolbarSpacer + sharedBackgroundVisibility", minOSNote: true, surface: "Separate glass groups", notes: "ToolbarSpacer is iOS 26+."),
        nav("bottomToolbar", "Bottom Toolbar", api: "ToolbarItem(placement: .bottomBar)", surface: "Floating glass items", notes: "iPhone primarily."),
        nav("tabBar", "Tab Bar", api: "TabView { Tab }", surface: "Floating glass tab bar", notes: "Becomes a sidebar on iPad with .sidebarAdaptable."),
        nav("floatingTab", "Floating Tab Bar", api: "TabView + .tabViewBottomAccessory", surface: "Glass bar with accessory", notes: "iPhone; iPad shows the tab bar at the top."),
        nav("tabSelection", "Tab Selection", api: "TabView(selection:)", surface: "Selection lens on glass", notes: "Selection animates a glass lens."),
        nav("tabMinimize", "Tab Bar Minimization", api: ".tabBarMinimizeBehavior(.onScrollDown)", surface: "Collapses to a compact glass control", notes: "iPhone only; ignored on iPad."),
        nav("searchNav", "Search within Navigation", api: ".searchable / Tab(role: .search)", surface: "Search field on glass", notes: "Search tab placement differs by device."),
        nav("sidebar", "Sidebar", api: "NavigationSplitView sidebar", surface: "Floating glass sidebar on iPad", notes: "iPad / large iPhone landscape."),
        nav("splitView", "Navigation Split View", api: "NavigationSplitView", surface: "Sidebar + content + detail", notes: "Collapses to a stack on iPhone."),
        nav("collapsing", "Collapsing Navigation", api: "Large title collapse on scroll", surface: "Title transitions to inline", notes: "Driven by scroll offset."),
        nav("scrollEdge", "Scroll Edge Effects", api: ".scrollEdgeEffectStyle(.soft / .hard, for:)", surface: "Soft blur/fade under bars", notes: "iOS 26+."),
        nav("navTransition", "Navigation Transitions", api: ".navigationTransition(.zoom(sourceID:in:))", surface: "Zoom from source", notes: "iOS 18+ API, glass bars during transition."),
        nav("uiNavBar", "UINavigationBar (standalone)", api: "UINavigationBar", surface: "Glass bar items", notes: "UIKit.", framework: "UIKit", lab: .uikitNavigationBar),
        nav("uiToolbar", "UIToolbar (standalone)", api: "UIToolbar", surface: "Glass item groups", notes: "UIKit.", framework: "UIKit", lab: .uikitToolbar),
        nav("uiTabBar", "UITabBar (standalone)", api: "UITabBar", surface: "Glass tab bar", notes: "UIKit.", framework: "UIKit", lab: .uikitTabBar),
        nav("uiNavController", "UINavigationController", api: "UINavigationController + UISearchController", surface: "Glass bars, scroll edge effect", notes: "UIKit.", framework: "UIKit"),
        nav("uiTabController", "UITabBarController", api: "UITabBarController + tabBarMinimizeBehavior", surface: "Glass tab bar", notes: "UIKit.", framework: "UIKit"),
    ]

    private static func pres(_ id: String, _ name: String, api: String, surface: String, framework: String = "SwiftUI") -> ComponentDescriptor {
        ComponentDescriptor(id: id, name: name, group: .presentation, kind: "Presentation", framework: framework, api: api, surface: surface,
                            states: ["Hidden", "Presenting", "Presented", "Dismissing"], factors: ["Content behind", "Detent / size", "Appearance", "Reduce Motion"],
                            experiments: ["Motion (open/close)", "Translucency of the container"], settings: ["Detent", "Source"],
                            deviceNotes: "Popovers and menus anchor differently on iPad; sheets are form sheets on iPad.", labConfig: nil)
    }

    static let presentation: [ComponentDescriptor] = [
        pres("menu", "Menu", api: "Menu", surface: "Glass menu morphing from its button"),
        pres("contextMenu", "Context Menu", api: ".contextMenu(menuItems:preview:)", surface: "Glass menu + lifted preview"),
        pres("selectionMenu", "Selection Menu", api: "Picker(.menu) / Menu with selection", surface: "Glass menu with checkmark"),
        pres("pickerMenu", "Picker Menu", api: "Picker.pickerStyle(.menu)", surface: "Glass menu"),
        pres("confirmation", "Confirmation Dialog", api: ".confirmationDialog", surface: "Action sheet / popover on glass"),
        pres("alert", "Alert", api: ".alert", surface: "System alert material"),
        pres("sheet", "Sheet", api: ".sheet", surface: "Sheet with glass background at partial height"),
        pres("halfSheet", "Half-height Sheet", api: ".presentationDetents([.medium])", surface: "Inset glass sheet"),
        pres("fullSheet", "Full-height Sheet", api: ".presentationDetents([.large])", surface: "Opaque at full height"),
        pres("popover", "Popover", api: ".popover", surface: "Glass popover (iPad); sheet on iPhone unless adapted"),
        pres("preview", "Content Preview", api: ".contextMenu(preview:)", surface: "Lifted preview"),
        pres("swiftUIModifiers", "SwiftUI Presentation Modifiers", api: ".presentationBackground / .presentationCornerRadius", surface: "Configurable"),
        pres("uikitSheet", "UIKit Sheet", api: "UISheetPresentationController", surface: "As SwiftUI sheet", framework: "UIKit"),
        pres("uikitAlert", "UIKit Alert / Action Sheet", api: "UIAlertController", surface: "System alert", framework: "UIKit"),
        pres("uikitPopover", "UIKit Popover", api: "UIPopoverPresentationController", surface: "Glass popover", framework: "UIKit"),
        pres("searchSuggestions", "Search Suggestions", api: ".searchSuggestions", surface: "Suggestion list"),
        pres("editMenu", "Edit Menu", api: "UIEditMenuInteraction (text selection)", surface: "Glass edit menu", framework: "UIKit"),
    ]

    private static func overlay(_ id: String, _ name: String, api: String, surface: String, custom: Bool = false) -> ComponentDescriptor {
        ComponentDescriptor(id: id, name: name, group: .overlays, kind: custom ? "Custom composite (native glass)" : "System overlay", framework: "SwiftUI / UserNotifications",
                            api: api, surface: surface, states: ["Hidden", "Shown"], factors: ["Content behind", "Focus / Do Not Disturb", "Permissions"],
                            experiments: ["Timing", "Appearance"], settings: ["Delay"], deviceNotes: "Banners are system UI; their presentation is controlled by iOS.", labConfig: nil)
    }

    static let overlays: [ComponentDescriptor] = [
        overlay("localNotification", "Local Notifications", api: "UNUserNotificationCenter.add(_:)", surface: "System banner (system-owned)"),
        overlay("banner", "Notification Banners", api: "UNNotificationPresentationOptions.banner", surface: "System banner"),
        overlay("foregroundNotification", "Foreground Notification Presentation", api: "userNotificationCenter(_:willPresent:)", surface: "System banner while the app is active"),
        overlay("inAppAlert", "In-app Alerts", api: ".alert", surface: "System alert"),
        overlay("sheetOverlay", "Sheets", api: ".sheet", surface: "Glass sheet"),
        overlay("popoverOverlay", "Popovers", api: ".popover", surface: "Glass popover"),
        overlay("menuOverlay", "Menus", api: "Menu", surface: "Glass menu"),
        overlay("contextOverlay", "Contextual Overlays", api: ".contextMenu", surface: "Glass menu"),
        overlay("progressOverlay", "Progress Overlay (custom)", api: "ProgressView + .glassEffect()", surface: "Custom composite using native glass", custom: true),
        overlay("toast", "Custom Toast (custom)", api: "Text + .glassEffect() + transition", surface: "Custom composite using native glass", custom: true),
    ]

    static let all: [ComponentDescriptor] = primitives + controls + navigation + presentation + overlays

    static func items(in g: ComponentGroup) -> [ComponentDescriptor] { all.filter { $0.group == g } }

    /// System glass surfaces that a third-party app cannot create or capture.
    static let unsupportedSurfaces: [(String, String)] = [
        ("Lock Screen & Notification Center", "Rendered by SpringBoard. Apps cannot present or capture them; only their own banners can be requested."),
        ("Control Center", "System UI outside the app's process and capture scope."),
        ("Home Screen dock, folders and widgets chrome", "System UI. Widgets render in the system with their own containers."),
        ("Dynamic Island system UI", "Owned by the system. Live Activities (ActivityKit) are presented by iOS and are not capturable by the app."),
        ("App Switcher", "System UI."),
        ("Volume / brightness HUDs", "System UI."),
        ("Siri", "System UI."),
        ("System keyboard", "Rendered by the keyboard process. It appears in system screenshots but not in view snapshots; it is not part of the lab canvas."),
        ("Notification banner pixels", "A banner can be triggered with permission, but its timing and composition are controlled by iOS; in-app capture APIs do not include it."),
    ]
}

private extension ComponentCatalog {
    static func nav(_ id: String, _ name: String, api: String, minOSNote: Bool, surface: String, notes: String) -> ComponentDescriptor {
        nav(id, name, api: api, surface: surface, notes: notes)
    }
}
