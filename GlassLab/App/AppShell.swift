import SwiftUI

/// Top-level navigation: a tab bar on iPhone that adapts to a sidebar on iPad.
struct AppShell: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.section) {
            Tab(AppSection.explore.rawValue, systemImage: AppSection.explore.symbol, value: AppSection.explore) {
                ExploreView()
            }
            Tab(AppSection.lab.rawValue, systemImage: AppSection.lab.symbol, value: AppSection.lab) {
                LabView()
            }
            Tab(AppSection.optics.rawValue, systemImage: AppSection.optics.symbol, value: AppSection.optics) {
                OpticsView()
            }
            Tab(AppSection.motion.rawValue, systemImage: AppSection.motion.symbol, value: AppSection.motion) {
                MotionView()
            }
            Tab(AppSection.sessions.rawValue, systemImage: AppSection.sessions.symbol, value: AppSection.sessions) {
                SessionsView()
            }
            TabSection("Analysis") {
                Tab(AppSection.compare.rawValue, systemImage: AppSection.compare.symbol, value: AppSection.compare) {
                    CompareView()
                }
                Tab(AppSection.reconstruction.rawValue, systemImage: AppSection.reconstruction.symbol, value: AppSection.reconstruction) {
                    ReconstructionView()
                }
                Tab(AppSection.matrix.rawValue, systemImage: AppSection.matrix.symbol, value: AppSection.matrix) {
                    MatrixView()
                }
                Tab(AppSection.performance.rawValue, systemImage: AppSection.performance.symbol, value: AppSection.performance) {
                    PerformanceView()
                }
            }
            TabSection("Reference") {
                Tab(AppSection.research.rawValue, systemImage: AppSection.research.symbol, value: AppSection.research) {
                    ResearchView()
                }
                Tab(AppSection.environment.rawValue, systemImage: AppSection.environment.symbol, value: AppSection.environment) {
                    EnvironmentView()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

/// Operator instruction strip. It is laid out ABOVE the canvas (never over it) so it cannot appear inside
/// the cropped capture region.
struct InstructionStrip: View {
    var text: String?
    var status: String
    var body: some View {
        HStack(spacing: 8) {
            if let text {
                Image(systemName: "camera.viewfinder").font(.title3)
                Text(text).font(.footnote.weight(.semibold)).lineLimit(2)
            } else if !status.isEmpty {
                ProgressView().controlSize(.small)
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 36)
        .padding(.horizontal, 12)
        .accessibilityIdentifier("instructionStrip")
    }
}
