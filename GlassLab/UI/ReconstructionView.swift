import SwiftUI

/// Reconstruction Lab: fits an independent model to native captures. Everything rendered here is the
/// app's own approximation and is labelled as such; it never replaces the native reference.
struct ReconstructionView: View {
    @Environment(AppModel.self) private var model
    @State private var chosen: Set<UUID> = []
    @State private var running = false
    @State private var progress = 0.0
    @State private var result: ParameterEstimator.Result?
    @State private var previews: [(String, CGImage?, CGImage?, CGImage?)] = []
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    private var candidates: [(ExperimentSession, Experiment)] {
        model.store.sessions.flatMap { s in s.experiments.filter { !$0.referenceFrames.isEmpty && !$0.resultFrames.isEmpty }.map { (s, $0) } }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Reconstruction output is Glass Lab's own model, not Apple Liquid Glass.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                    Text("Model stages: background sampling → rim distortion along the outline normal → Gaussian blur → saturation → transmission and per-channel offset (tint) → Gaussian rim highlight → compositing. Parameters are fitted by Nelder–Mead on linear-light MSE.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Training data (reference + native glass pairs)") {
                    if candidates.isEmpty { Text("Acquire experiments in the Lab first.").foregroundStyle(.secondary) }
                    ForEach(candidates, id: \.1.id) { pair in
                        Button {
                            if chosen.contains(pair.1.id) { chosen.remove(pair.1.id) } else { chosen.insert(pair.1.id) }
                        } label: {
                            HStack {
                                Image(systemName: chosen.contains(pair.1.id) ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) {
                                    Text(pair.1.title).font(.subheadline).lineLimit(2)
                                    Text(pair.0.title).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section {
                    if running {
                        ProgressView(value: progress)
                        Button("Cancel", role: .cancel) { task?.cancel() }
                    } else {
                        Button("Fit model and cross-validate", systemImage: "function") { start() }
                            .disabled(chosen.isEmpty)
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.caption) }
                } footer: {
                    Text("Use several backgrounds of the same subject and variant. With 3 or more samples each one is held out in turn to test generalisation to unseen backgrounds.")
                }
                if let r = result {
                    Section("Fitted parameters") {
                        ForEach(r.report) { p in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(p.name)
                                    Spacer()
                                    Text(Format.number(p.value, digits: 3) + (p.unit.isEmpty ? "" : " " + p.unit)).monospacedDigit()
                                }
                                HStack(spacing: 8) {
                                    ProvenanceBadge(provenance: .estimated)
                                    Text("SE " + Format.number(p.standardError, digits: 2)).font(.caption2.monospacedDigit())
                                    Text("sensitivity " + Format.number(p.sensitivity * 100, digits: 2) + "%").font(.caption2.monospacedDigit())
                                    if !p.identifiable { Text("not identifiable").font(.caption2).foregroundStyle(.orange) }
                                    if p.atBound { Text("at bound").font(.caption2).foregroundStyle(.orange) }
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                        KeyValueRow(key: "Training RMSE (linear RGB)", value: Format.number(r.trainingRMSE, digits: 3), provenance: .derived)
                        KeyValueRow(key: "Iterations", value: "\(r.iterations) (\(r.converged ? "converged" : "iteration limit"))")
                        ForEach(r.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }
                    if !r.folds.isEmpty {
                        Section("Cross-validation (leave one out)") {
                            ForEach(r.folds) { f in
                                HStack { Text(f.heldOut).font(.caption).lineLimit(1); Spacer(); Text("train \(Format.number(f.trainRMSE, digits: 3)) · held-out \(Format.number(f.heldOutRMSE, digits: 3))").font(.caption.monospacedDigit()) }
                            }
                        }
                    }
                    Section("Reference vs reconstruction vs error") {
                        ForEach(previews, id: \.0) { p in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.0).font(.caption)
                                HStack(spacing: 4) {
                                    tile(p.1, "Apple (captured)")
                                    tile(p.2, "Glass Lab model")
                                    tile(p.3, "|error| x4")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reconstruction")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func tile(_ img: CGImage?, _ caption: String) -> some View {
        VStack(spacing: 2) {
            if let img { Image(decorative: img, scale: 1).interpolation(.none).resizable().scaledToFit() } else { Color.gray.opacity(0.2) }
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func start() {
        let pairs = candidates.filter { chosen.contains($0.1.id) }
        let inputs: [(String, URL, URL, GlassRegionModel, Double)] = pairs.compactMap { pair in
            let s = pair.0, e = pair.1
            guard let rf = e.referenceFrames.last, let tf = e.resultFrames.last else { return nil }
            return (e.configuration.background.summary + " · " + String(e.id.uuidString.prefix(4)), model.store.url(for: rf, in: s.id), model.store.url(for: tf, in: s.id),
                    CaptureCoordinator.regionModel(for: e, pixelsPerPoint: tf.pixelsPerPoint), tf.pixelsPerPoint)
        }
        running = true; error = nil; result = nil; previews = []; progress = 0
        task = Task {
            do {
                let out = try await Task.detached { () throws -> (ParameterEstimator.Result, [(String, CGImage?, CGImage?, CGImage?)]) in
                    var samples: [ReconstructionSample] = []
                    for i in inputs {
                        guard let r = LinearImage.load(url: i.1), let t = LinearImage.load(url: i.2),
                              let s = ReconstructionSample.make(name: i.0, reference: r, test: t, region: i.3, ppp: i.4) else { continue }
                        samples.append(s)
                    }
                    guard !samples.isEmpty else { throw GlassLabError.invalidData("no usable samples (frames missing or glass outside the frame)") }
                    let res = try ParameterEstimator.estimate(training: samples) { p in Task { @MainActor in progress = p } }
                    let views = samples.map { s -> (String, CGImage?, CGImage?, CGImage?) in
                        let rec = ReconstructionRenderer.render(res.parameters, s)
                        return (s.name, s.target.cgImage(), rec.cgImage(), Heatmap.difference(s.target, rec, gain: 4))
                    }
                    return (res, views)
                }.value
                result = out.0; previews = out.1
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            running = false
        }
    }
}
