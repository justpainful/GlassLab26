import SwiftUI

struct ExploreView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: ComponentDescriptor?
    @State private var query = ""
    @State private var showUnsupported = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(ComponentGroup.allCases) { g in
                    let items = ComponentCatalog.items(in: g).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.api.localizedCaseInsensitiveContains(query) }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { item in
                                NavigationLink(value: item) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                        Text(item.api).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .accessibilityIdentifier("component-\(item.id)")
                            }
                        } header: {
                            Label(g.rawValue, systemImage: g.symbol)
                        }
                    }
                }
                Section {
                    Button { showUnsupported = true } label: { Label("Unsupported Native Surfaces", systemImage: "nosign") }
                }
            }
            .navigationTitle("Explore")
            .searchable(text: $query, prompt: "Components or APIs")
        } detail: {
            if let selection {
                ComponentDetailView(item: selection)
            } else {
                EmptyStateView(title: "Choose a component", symbol: "square.grid.2x2",
                               message: "\(ComponentCatalog.all.count) native components and glass cases. Each one opens a live demo built from Apple's APIs.")
            }
        }
        .sheet(isPresented: $showUnsupported) { UnsupportedSurfacesView() }
    }
}

struct ComponentDetailView: View {
    @Environment(AppModel.self) private var model
    var item: ComponentDescriptor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ComponentDemoView(item: item)
                    .id(item.id)
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        KeyValueRow(key: "Type", value: item.kind)
                        KeyValueRow(key: "Framework", value: item.framework)
                        KeyValueRow(key: "API", value: item.api)
                        KeyValueRow(key: "Requires", value: item.minOS)
                        KeyValueRow(key: "Surface", value: item.surface)
                    }
                } label: { Label("Component", systemImage: "info.circle") }
                infoList("States", item.states, "circle.grid.3x3")
                infoList("Factors that change its appearance", item.factors, "slider.horizontal.3")
                infoList("Supported experiments", item.experiments, "flask")
                infoList("Adjustable settings", item.settings, "dial.low")
                GroupBox {
                    Text(item.deviceNotes).font(.subheadline)
                } label: { Label("iPhone vs iPad", systemImage: "ipad.and.iphone") }
                if let cfg = item.labConfig {
                    Button {
                        model.load(cfg)
                    } label: {
                        Label("Open in Experiment Lab", systemImage: "flask")
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("openInLab")
                } else {
                    Text("This component is studied in its live demo and with Motion recordings; it is not hosted in the lab canvas.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoList(_ title: String, _ values: [String], _ symbol: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(values, id: \.self) { Text("• " + $0).font(.subheadline) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: { Label(title, systemImage: symbol) }
    }
}

struct UnsupportedSurfacesView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("These surfaces use Liquid Glass but are owned by the system. Glass Lab records them here instead of imitating them.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(ComponentCatalog.unsupportedSurfaces, id: \.0) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.0).font(.headline)
                        Text(s.1).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Unsupported Native Surfaces")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
