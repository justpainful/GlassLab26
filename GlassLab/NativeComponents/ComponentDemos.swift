import SwiftUI
import UIKit

/// Live, native demo for a catalog entry. Navigation and presentation demos open in a full-screen
/// container so the system bars and presentations behave exactly as in a real app.
struct ComponentDemoView: View {
    var item: ComponentDescriptor
    @State private var background = BackgroundSpec.pattern(.checkerboard, scale: 14)
    @State private var fullScreen = false

    var body: some View {
        VStack(spacing: 12) {
            switch item.group {
            case .primitives:
                PrimitiveDemo(item: item, background: $background)
            case .controls:
                ControlsDemo(id: item.id, background: background)
            case .navigation, .presentation:
                Button { fullScreen = true } label: { Label("Open live demo", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("openLiveDemo")
                Text("Opens a full-screen container with its own navigation stack so system bars and presentations are real.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            case .overlays:
                OverlaysDemo(id: item.id, background: background)
            }
            if item.group != .primitives {
                Picker("Background", selection: $background.kind) {
                    ForEach([BackgroundKind.checkerboard, .solid, .linearGradient, .randomDots, .textPattern, .verticalLines], id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }
        }
        .fullScreenCover(isPresented: $fullScreen) {
            FullScreenDemo(id: item.id, background: background)
        }
    }
}

// MARK: - Primitives

struct PrimitiveDemo: View {
    var item: ComponentDescriptor
    @Binding var background: BackgroundSpec
    @State private var toggled = false
    @State private var spacing: Double = 60
    @State private var transition = 0
    @Namespace private var ns

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                BackgroundView(spec: background)
                content
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            controls
            Picker("Background", selection: $background.kind) {
                ForEach([BackgroundKind.checkerboard, .solid, .randomDots, .linearGradient, .textPattern, .highFrequencyNoise], id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
        }
    }

    private var config: SceneConfiguration { item.labConfig ?? SceneConfiguration() }

    @ViewBuilder
    private var content: some View {
        switch item.id {
        case "merging", "splitting":
            GlassEffectContainer(spacing: 40) {
                HStack(spacing: spacing) {
                    Image(systemName: "pencil").font(.title).frame(width: 80, height: 80).glassEffect(.regular.interactive(), in: .circle)
                    Image(systemName: "eraser").font(.title).frame(width: 80, height: 80).glassEffect(.regular.interactive(), in: .circle)
                }
            }
        case "morphing":
            GlassEffectContainer(spacing: 30) {
                HStack(spacing: 16) {
                    Image(systemName: "square.and.pencil").font(.title2).frame(width: 64, height: 64)
                        .glassEffect(.regular.interactive(), in: .circle).glassEffectID("a", in: ns)
                    if toggled {
                        Image(systemName: "photo").font(.title2).frame(width: 64, height: 64)
                            .glassEffect(.regular.interactive(), in: .circle).glassEffectID("b", in: ns)
                        Image(systemName: "mic").font(.title2).frame(width: 64, height: 64)
                            .glassEffect(.regular.interactive(), in: .circle).glassEffectID("c", in: ns)
                    }
                }
            }
        case "transitions":
            GlassEffectContainer(spacing: 20) {
                HStack(spacing: 20) {
                    Text("Anchor").padding().glassEffect().glassEffectID("anchor", in: ns)
                    if toggled {
                        Text("Transition").padding().glassEffect().glassEffectID("t", in: ns)
                            .glassEffectTransition(transition == 0 ? .matchedGeometry : (transition == 1 ? .materialize : .identity))
                    }
                }
            }
        case "glassDisabled":
            Button("Disabled") {}.buttonStyle(.glass).disabled(true)
        default:
            NativeSubjectView(config: config, materialOn: true)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch item.id {
        case "merging", "splitting":
            VStack(alignment: .leading) {
                Text("Stack spacing \(Int(spacing)) pt (container spacing 40 pt)").font(.caption.monospacedDigit())
                Slider(value: $spacing, in: -20...120)
                Button(item.id == "merging" ? "Animate merge" : "Animate split") {
                    withAnimation(.smooth(duration: 0.8)) { spacing = item.id == "merging" ? (spacing > 10 ? 0 : 80) : (spacing < 40 ? 100 : 0) }
                }.buttonStyle(.glass)
            }
        case "morphing":
            Button(toggled ? "Collapse" : "Expand") { withAnimation(.bouncy) { toggled.toggle() } }.buttonStyle(.glass)
        case "transitions":
            Picker("Transition", selection: $transition) {
                Text(".matchedGeometry").tag(0); Text(".materialize").tag(1); Text(".identity").tag(2)
            }.pickerStyle(.segmented)
            Button(toggled ? "Remove" : "Insert") { withAnimation(.smooth) { toggled.toggle() } }.buttonStyle(.glass)
        default:
            EmptyView()
        }
    }
}

// MARK: - Controls

struct ControlsDemo: View {
    var id: String
    var background: BackgroundSpec
    @State private var on = true
    @State private var value = 0.4
    @State private var count = 3
    @State private var seg = 0
    @State private var date = Date()
    @State private var color = Color.blue
    @State private var text = ""
    @State private var secret = ""
    @State private var expanded = false
    @State private var disabled = false
    @State private var loading = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                BackgroundView(spec: background)
                control.padding().disabled(disabled)
            }
            .frame(minHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Toggle("Disabled state", isOn: $disabled)
        }
    }

    @ViewBuilder
    private var control: some View {
        switch id {
        case "button": Button("Bordered") {}.buttonStyle(.bordered)
        case "iconButton": Button { } label: { Image(systemName: "heart.fill").font(.title2).frame(width: 44, height: 44) }.buttonStyle(.glass).buttonBorderShape(.circle)
        case "textButton": Button("Plain text button") {}.buttonStyle(.plain)
        case "prominent":
            VStack(spacing: 12) {
                Button("Bordered Prominent") {}.buttonStyle(.borderedProminent)
                Button("Glass Prominent") {}.buttonStyle(.glassProminent)
            }
        case "destructive":
            VStack(spacing: 12) {
                Button("Delete", role: .destructive) {}.buttonStyle(.glass)
                Button("Delete", role: .destructive) {}.buttonStyle(.borderedProminent)
            }
        case "toggle": Toggle("Toggle", isOn: $on).frame(maxWidth: 260)
        case "switch": UIKitSwitch(isOn: $on).fixedSize()
        case "slider": Slider(value: $value).frame(maxWidth: 280)
        case "stepper": Stepper("Count \(count)", value: $count, in: 0...10).frame(maxWidth: 260)
        case "segmented", "uiSegmented":
            Picker("Seg", selection: $seg) { Text("Day").tag(0); Text("Week").tag(1); Text("Month").tag(2) }.pickerStyle(.segmented).frame(maxWidth: 300)
        case "picker":
            Picker("Picker", selection: $seg) { Text("Day").tag(0); Text("Week").tag(1); Text("Month").tag(2) }.pickerStyle(.menu)
        case "datePicker": DatePicker("Date", selection: $date).frame(maxWidth: 320)
        case "colorPicker": ColorPicker("Color", selection: $color).frame(maxWidth: 260)
        case "textField": TextField("Text field", text: $text).textFieldStyle(.roundedBorder).focused($focused).frame(maxWidth: 300)
        case "searchField": SearchFieldDemo()
        case "secureField": SecureField("Password", text: $secret).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
        case "menuButton":
            Menu { Button("Copy", systemImage: "doc.on.doc") {}; Button("Share", systemImage: "square.and.arrow.up") {}; Button("Delete", systemImage: "trash", role: .destructive) {} } label: { Label("Menu", systemImage: "ellipsis.circle") }.buttonStyle(.glass)
        case "toolbarButton":
            HStack(spacing: 0) {
                Button { } label: { Image(systemName: "bold") }.padding(10)
                Button { } label: { Image(systemName: "italic") }.padding(10)
                Button { } label: { Image(systemName: "underline") }.padding(10)
            }
            .glassEffect()
        case "disclosure":
            DisclosureGroup("Details", isExpanded: $expanded) { Text("Disclosed content").padding(.vertical, 4) }.frame(maxWidth: 280).padding().background(.background, in: RoundedRectangle(cornerRadius: 12))
        case "contextual":
            Text("Press and hold").padding().glassEffect()
                .contextMenu { Button("Copy", systemImage: "doc.on.doc") {}; Button("Delete", systemImage: "trash", role: .destructive) {} }
        case "loading":
            Button { loading.toggle() } label: {
                HStack { if loading { ProgressView() }; Text(loading ? "Loading" : "Start") }.frame(minWidth: 120)
            }.buttonStyle(.glass)
        default: Text("No demo")
        }
    }
}

struct UIKitSwitch: UIViewRepresentable {
    @Binding var isOn: Bool
    func makeUIView(context: Context) -> UISwitch {
        let s = UISwitch()
        s.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return s
    }
    func updateUIView(_ s: UISwitch, context: Context) { s.isOn = isOn }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject {
        var parent: UIKitSwitch
        init(_ p: UIKitSwitch) { parent = p }
        @objc func changed(_ s: UISwitch) { parent.isOn = s.isOn }
    }
}

struct SearchFieldDemo: View {
    @State private var q = ""
    var body: some View {
        NavigationStack {
            List(["Regular", "Clear", "Identity"].filter { q.isEmpty || $0.localizedCaseInsensitiveContains(q) }, id: \.self) { Text($0) }
                .searchable(text: $q)
                .navigationTitle("Search")
                .navigationBarTitleDisplayMode(.inline)
        }
        .frame(height: 260)
    }
}

// MARK: - Overlays

struct OverlaysDemo: View {
    var id: String
    var background: BackgroundSpec
    @State private var alert = false
    @State private var sheet = false
    @State private var popover = false
    @State private var progress = false
    @State private var toast = false
    private var notifications = NotificationLabState.shared

    init(id: String, background: BackgroundSpec) { self.id = id; self.background = background }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                BackgroundView(spec: background)
                if progress {
                    VStack(spacing: 8) { ProgressView(); Text("Working").font(.footnote) }
                        .padding(20).glassEffect(in: .rect(cornerRadius: 20))
                }
                if toast {
                    VStack { Spacer(); Label("Saved", systemImage: "checkmark.circle.fill").padding(.horizontal, 16).padding(.vertical, 10).glassEffect().padding(.bottom, 16) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            switch id {
            case "localNotification", "banner", "foregroundNotification":
                NotificationLabPanel(state: notifications)
            case "inAppAlert": Button("Show alert") { alert = true }.buttonStyle(.glass)
            case "sheetOverlay": Button("Show sheet") { sheet = true }.buttonStyle(.glass)
            case "popoverOverlay": Button("Show popover") { popover = true }.buttonStyle(.glass).popover(isPresented: $popover) { Text("Popover").padding() }
            case "menuOverlay": Menu("Open menu") { Button("One") {}; Button("Two") {} }.buttonStyle(.glass)
            case "contextOverlay": Text("Press and hold").padding().glassEffect().contextMenu { Button("Action") {} }
            case "progressOverlay":
                Button(progress ? "Hide progress" : "Show progress") { withAnimation { progress.toggle() } }.buttonStyle(.glass)
                Text("Custom composite: a ProgressView on native glass. Not a system component.").font(.caption).foregroundStyle(.secondary)
            case "toast":
                Button("Show toast") {
                    withAnimation(.snappy) { toast = true }
                    Task { try? await Task.sleep(for: .seconds(2)); withAnimation(.snappy) { toast = false } }
                }.buttonStyle(.glass)
                Text("Custom composite: text on native glass with a transition. iOS has no system toast.").font(.caption).foregroundStyle(.secondary)
            default: EmptyView()
            }
        }
        .alert("In-app alert", isPresented: $alert) { Button("OK") {}; Button("Delete", role: .destructive) {} } message: { Text("System alert presentation.") }
        .sheet(isPresented: $sheet) { Text("Sheet").presentationDetents([.medium, .large]) }
    }
}

// MARK: - Full-screen navigation & presentation demos

struct FullScreenDemo: View {
    var id: String
    var background: BackgroundSpec
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            demo
            Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 36, height: 36) }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .padding(.trailing, 16).padding(.top, 4)
                .accessibilityIdentifier("closeDemo")
        }
    }

    @ViewBuilder
    private var demo: some View {
        switch id {
        case "tabBar", "floatingTab", "tabSelection", "tabMinimize", "searchNav": TabDemo(accessory: id == "floatingTab", searchTab: id == "searchNav")
        case "sidebar", "splitView": SplitDemo()
        case "uiNavController": UIKitNavigationDemo(largeTitles: true, showToolbar: true).ignoresSafeArea()
        case "uiTabController": UIKitTabBarDemo().ignoresSafeArea()
        case "uiNavBar", "uiToolbar", "uiTabBar":
            ZStack { BackgroundView(spec: background).ignoresSafeArea(); UIKitBarSubject(kind: id == "uiNavBar" ? .uikitNavigationBar : (id == "uiToolbar" ? .uikitToolbar : .uikitTabBar), width: 390).frame(height: 64) }
        case "uikitSheet", "uikitAlert", "uikitPopover", "editMenu": UIKitPresentationDemo(id: id)
        default:
            if ComponentCatalog.presentation.contains(where: { $0.id == id }) { PresentationDemo(id: id, background: background) }
            else { NavigationDemo(id: id, background: background) }
        }
    }
}

struct DemoScrollContent: View {
    var body: some View {
        LazyVStack(spacing: 10) {
            ForEach(0..<40, id: \.self) { i in
                RoundedRectangle(cornerRadius: 12)
                    .fill([Color.red, .orange, .yellow, .green, .teal, .blue, .indigo, .purple][i % 8].gradient)
                    .frame(height: 72)
                    .overlay(alignment: .leading) { Text("Row \(i + 1)").font(.headline).foregroundStyle(.white).padding(.leading, 16) }
            }
        }
        .padding()
    }
}

struct NavigationDemo: View {
    var id: String
    var background: BackgroundSpec
    @State private var hard = false
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            ScrollView { DemoScrollContent() }
                .navigationTitle("Navigation")
                .navigationBarTitleDisplayMode(id == "inlineTitle" ? .inline : .large)
                .scrollEdgeEffectStyle(hard ? .hard : .soft, for: .top)
                .toolbar {
                    if id == "toolbarGrouping" {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button("Bold", systemImage: "bold") {}
                            Button("Italic", systemImage: "italic") {}
                        }
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                        ToolbarItem(placement: .topBarTrailing) { Button("Share", systemImage: "square.and.arrow.up") {} }
                        ToolbarItem(placement: .topBarTrailing) { Button("Info", systemImage: "info") {} }.sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .topBarLeading) { Button("Edge", systemImage: hard ? "square" : "square.dashed") { hard.toggle() } }
                        ToolbarItem(placement: .topBarTrailing) { Button("Add", systemImage: "plus") {} }
                    }
                    if id == "bottomToolbar" || id == "toolbar" {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Button("Back", systemImage: "chevron.left") {}
                            Spacer()
                            Button("Compose", systemImage: "square.and.pencil") {}
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if id == "navTransition" {
                        NavigationLink(value: 1) { Label("Zoom transition", systemImage: "rectangle.expand.vertical").padding().glassEffect() }
                            .matchedTransitionSource(id: 1, in: zoom)
                            .padding()
                    }
                }
                .navigationDestination(for: Int.self) { _ in
                    BackgroundView(spec: background).ignoresSafeArea().navigationTitle("Detail").navigationTransition(.zoom(sourceID: 1, in: zoom))
                }
        }
    }
}

struct TabDemo: View {
    var accessory: Bool
    var searchTab: Bool
    @State private var selection = 0
    @State private var q = ""

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: 0) { NavigationStack { ScrollView { DemoScrollContent() }.navigationTitle("Home") } }
            Tab("Library", systemImage: "books.vertical", value: 1) { NavigationStack { ScrollView { DemoScrollContent() }.navigationTitle("Library") } }
            Tab("Settings", systemImage: "gearshape", value: 2) { NavigationStack { Form { Text("Settings") }.navigationTitle("Settings") } }
            if searchTab {
                Tab(value: 3, role: .search) { NavigationStack { List(1..<30, id: \.self) { Text("Result \($0)") }.navigationTitle("Search").searchable(text: $q) } }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: accessory) {
            HStack { Image(systemName: "music.note"); Text("Now Playing"); Spacer(); Image(systemName: "play.fill") }.padding(.horizontal)
        }
    }
}

struct SplitDemo: View {
    @State private var selection: Int? = 1
    var body: some View {
        NavigationSplitView {
            List(1..<20, id: \.self, selection: $selection) { Label("Item \($0)", systemImage: "folder") }.navigationTitle("Sidebar")
        } detail: {
            ScrollView { DemoScrollContent() }.navigationTitle("Item \(selection ?? 0)")
        }
    }
}

struct PresentationDemo: View {
    var id: String
    var background: BackgroundSpec
    @State private var sheet = false
    @State private var dialog = false
    @State private var alert = false
    @State private var popover = false
    @State private var choice = 0
    @State private var q = ""

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundView(spec: background).ignoresSafeArea()
                VStack(spacing: 16) {
                    switch id {
                    case "menu":
                        Menu { Button("Copy", systemImage: "doc.on.doc") {}; Button("Paste", systemImage: "doc.on.clipboard") {}; Divider(); Button("Delete", systemImage: "trash", role: .destructive) {} } label: { Label("Menu", systemImage: "ellipsis") }.buttonStyle(.glass)
                    case "contextMenu", "preview":
                        Text("Press and hold").font(.title3).padding(24).glassEffect(in: .rect(cornerRadius: 20))
                            .contextMenu { Button("Copy", systemImage: "doc.on.doc") {} } preview: { BackgroundView(spec: .pattern(.randomDots)).frame(width: 260, height: 180) }
                    case "selectionMenu", "pickerMenu":
                        Picker("Option", selection: $choice) { Text("Regular").tag(0); Text("Clear").tag(1); Text("Identity").tag(2) }.pickerStyle(.menu).buttonStyle(.glass)
                    case "confirmation":
                        Button("Confirmation dialog") { dialog = true }.buttonStyle(.glass)
                    case "alert":
                        Button("Alert") { alert = true }.buttonStyle(.glass)
                    case "popover":
                        Button("Popover") { popover = true }.buttonStyle(.glass).popover(isPresented: $popover) { Text("Popover content").padding().presentationCompactAdaptation(.popover) }
                    case "searchSuggestions":
                        Text("Use the search field").foregroundStyle(.secondary)
                    default:
                        Button("Sheet") { sheet = true }.buttonStyle(.glass)
                    }
                }
            }
            .navigationTitle("Presentation")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $q)
            .searchSuggestions { if id == "searchSuggestions" { ForEach(["Regular glass", "Clear glass", "Container"], id: \.self) { Text($0).searchCompletion($0) } } }
            .sheet(isPresented: $sheet) {
                VStack { Text("Sheet").font(.title2); Text(detentLabel).foregroundStyle(.secondary) }
                    .presentationDetents(id == "halfSheet" ? [.medium] : (id == "fullSheet" ? [.large] : [.medium, .large]))
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
            .confirmationDialog("Confirm", isPresented: $dialog) { Button("Delete", role: .destructive) {}; Button("Archive") {} }
            .alert("Alert", isPresented: $alert) { Button("OK") {} }
        }
    }

    private var detentLabel: String { id == "halfSheet" ? ".medium" : (id == "fullSheet" ? ".large" : ".medium / .large") }
}

struct UIKitPresentationDemo: View {
    var id: String
    @State private var request: UIKitPresenter.Request = .none
    var body: some View {
        ZStack {
            BackgroundView(spec: .pattern(.checkerboard)).ignoresSafeArea()
            UIKitPresenter(request: $request).frame(width: 1, height: 1)
            VStack(spacing: 14) {
                if id == "editMenu" {
                    UIKitEditMenuDemo().frame(height: 160).padding().glassEffect(in: .rect(cornerRadius: 20)).padding()
                } else {
                    Button("Medium sheet") { request = .sheetMedium }.buttonStyle(.glass)
                    Button("Large sheet") { request = .sheetLarge }.buttonStyle(.glass)
                    Button("Alert") { request = .alert }.buttonStyle(.glass)
                    Button("Action sheet") { request = .actionSheet }.buttonStyle(.glass)
                    Button("Popover") { request = .popover }.buttonStyle(.glass)
                }
            }
        }
    }
}
