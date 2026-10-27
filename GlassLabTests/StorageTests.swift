import XCTest
import CoreGraphics
@testable import GlassLab

final class SerializationTests: XCTestCase {
    func testConfigurationRoundTrip() throws {
        var c = SceneConfiguration()
        c.variant = .clear; c.tint = RGBAColor(0.1, 0.2, 0.3, 0.4, space: .displayP3); c.modules = [.blur, .color]
        c.background = .pattern(.fiducialChecker, scale: 7)
        let data = try DataStore.encoder.encode(c)
        let back = try DataStore.decoder.decode(SceneConfiguration.self, from: data)
        XCTAssertEqual(back, c)
        XCTAssertEqual(back.duplicated().name, c.name + " Copy")
        XCTAssertNotEqual(back.duplicated().id, c.id)
    }

    func testMeasurementWithNaNSeriesRoundTrip() throws {
        var m = Measurement(name: "x", value: 1.5, unit: "pt", provenance: .estimated, algorithm: "a", version: "1", confidence: .low("t"),
                            uncertainty: Uncertainty(halfWidth: 0.1, kind: .fitInterval), sampleCount: 3)
        m.series = [Measurement.Series(label: "s", xUnit: "x", yUnit: "y", x: [0, 1], y: [.nan, 2])]
        let back = try DataStore.decoder.decode(Measurement.self, from: DataStore.encoder.encode(m))
        XCTAssertEqual(back.value, 1.5)
        XCTAssertTrue(back.series![0].y[0].isNaN)
        XCTAssertEqual(back.uncertainty?.kind, .fitInterval)
    }
}

@MainActor
final class DataStoreTests: XCTestCase {
    var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("GlassLabTests-" + UUID().uuidString)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    func makeFrame(_ store: DataStore, _ sid: UUID, role: FrameRecord.Role) throws -> FrameRecord {
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.displayP3)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: role == .reference ? 0.2 : 0.6, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let url = store.frameURL(sid, "\(role.rawValue)-\(UUID().uuidString).png")
        return try FrameWriter.write(ctx.makeImage()!, to: url, role: role, method: .viewSnapshot, pixelsPerPoint: 2, mediaTime: 1, crop: nil, notes: ["test"])
    }

    func testSessionCreateSaveReloadDelete() throws {
        let store = DataStore(root: root)
        let s = store.createSession(title: "T", environment: EnvironmentSnapshot())
        var e = Experiment(configuration: SceneConfiguration(), environment: EnvironmentSnapshot(), canvasSizePoints: CGSizeCodable(CGSize(width: 4, height: 4)),
                           subjectFramePoints: CGRectCodable(CGRect(x: 1, y: 1, width: 2, height: 2)))
        e.referenceFrames = [try makeFrame(store, s.id, role: .reference)]
        e.resultFrames = [try makeFrame(store, s.id, role: .test)]
        store.upsert(experiment: e, in: s.id)
        let reloaded = DataStore(root: root)
        XCTAssertEqual(reloaded.sessions.count, 1)
        XCTAssertEqual(reloaded.sessions[0].experiments.first?.resultFrames.first?.sha256.count, 64)
        let url = reloaded.url(for: reloaded.sessions[0].experiments[0].resultFrames[0], in: s.id)
        XCTAssertEqual(FrameWriter.sha256(of: url), reloaded.sessions[0].experiments[0].resultFrames[0].sha256)
        reloaded.deleteExperiment(e.id, in: s.id)
        XCTAssertTrue(reloaded.session(s.id)!.experiments.isEmpty)
        reloaded.deleteSession(s.id)
        XCTAssertTrue(reloaded.sessions.isEmpty)
    }

    func testInterruptedAcquisitionIsMarkedIncomplete() throws {
        let store = DataStore(root: root)
        let s = store.createSession(title: "T", environment: EnvironmentSnapshot())
        var e = Experiment(configuration: SceneConfiguration(), environment: EnvironmentSnapshot(), canvasSizePoints: CGSizeCodable(.zero), subjectFramePoints: CGRectCodable(.zero))
        e.referenceFrames = [try makeFrame(store, s.id, role: .reference)]
        store.upsert(experiment: e, in: s.id)
        let reloaded = DataStore(root: root)
        XCTAssertEqual(reloaded.sessions[0].experiments[0].validity.status, .incomplete)
        XCTAssertTrue(reloaded.sessions[0].experiments[0].validity.reasons.first?.contains("interrupted") ?? false)
    }

    func testCSVAndBundleRoundTrip() async throws {
        let store = DataStore(root: root)
        let s = store.createSession(title: "Bundle, \"quoted\"", environment: EnvironmentSnapshot())
        var e = Experiment(configuration: SceneConfiguration(), environment: EnvironmentSnapshot(), canvasSizePoints: CGSizeCodable(.zero), subjectFramePoints: CGRectCodable(.zero))
        e.referenceFrames = [try makeFrame(store, s.id, role: .reference)]
        e.resultFrames = [try makeFrame(store, s.id, role: .test)]
        e.analyses = [AnalysisRun(startedAt: Date(), finishedAt: Date(), appVersion: "t", algorithmVersions: [:],
                                  measurements: [Measurement(name: "m, 1", value: 2, unit: "pt", provenance: .measured, algorithm: "a", version: "1", confidence: .high("x"), sampleCount: 1),
                                                 .unavailable("n", unit: "", algorithm: "a", version: "1", reason: "because")],
                                  derivedFrames: [], log: [], validity: .valid)]
        store.upsert(experiment: e, in: s.id)
        let session = store.session(s.id)!
        let csv = ExportManager.csv(session)
        XCTAssertTrue(csv.contains("\"m, 1\""))
        XCTAssertTrue(csv.contains("N/A"))
        XCTAssertEqual(csv.split(separator: "\n").count, 3)

        let bundle = try ExportManager.makeBundle(session: session, sessionDirectory: store.directory(for: s.id), includeReport: true, includeRecordings: true)
        let entries = try ZipArchive.entries(of: bundle)
        XCTAssertTrue(entries.contains { $0.path == "manifest.json" })
        XCTAssertTrue(entries.contains { $0.path == "report.pdf" })
        XCTAssertTrue(entries.contains { $0.path.hasPrefix("frames/") })

        let report = await ExportManager.importBundle(bundle, into: store)
        XCTAssertTrue(report.imported, report.problems.joined(separator: "; "))
        XCTAssertEqual(store.sessions.count, 2)   // same ID exists, so it is imported as a copy
        XCTAssertTrue(store.sessions.contains { $0.title.hasSuffix("(imported copy)") })
    }

    func testTamperedBundleIsRejected() async throws {
        let store = DataStore(root: root)
        let s = store.createSession(title: "T", environment: EnvironmentSnapshot())
        var e = Experiment(configuration: SceneConfiguration(), environment: EnvironmentSnapshot(), canvasSizePoints: CGSizeCodable(.zero), subjectFramePoints: CGRectCodable(.zero))
        e.resultFrames = [try makeFrame(store, s.id, role: .test)]
        store.upsert(experiment: e, in: s.id)
        let bundle = try ExportManager.makeBundle(session: store.session(s.id)!, sessionDirectory: store.directory(for: s.id), includeReport: false, includeRecordings: false)
        // Flip one byte inside the stored PNG data (after the local header) without touching the CRC.
        let entries = try ZipArchive.entries(of: bundle)
        let frame = entries.first { $0.path.hasPrefix("frames/") }!
        let h = try FileHandle(forUpdating: bundle)
        try h.seek(toOffset: frame.offset + 40)
        let b = h.readData(ofLength: 1)
        try h.seek(toOffset: frame.offset + 40)
        h.write(Data([b[0] ^ 0xFF]))
        try h.close()
        let report = await ExportManager.importBundle(bundle, into: store)
        XCTAssertFalse(report.imported)
        XCTAssertFalse(report.problems.isEmpty)
    }
}

final class ZipTests: XCTestCase {
    func testCRC32KnownValue() {
        XCTAssertEqual(ZipArchive.crc32(Data("123456789".utf8)), 0xCBF43926)
        let split = ZipArchive.crc32(Data("6789".utf8), seed: ZipArchive.crc32(Data("12345".utf8)))
        XCTAssertEqual(split, 0xCBF43926)
    }

    func testWriteListExtract() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zip-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.txt"), b = dir.appendingPathComponent("b.bin")
        try Data("hello".utf8).write(to: a)
        try Data((0..<3000).map { UInt8($0 % 251) }).write(to: b)
        let zip = dir.appendingPathComponent("t.zip")
        try ZipArchive.write(entries: [.init(path: "a.txt", source: a), .init(path: "sub/b.bin", source: b)], to: zip)
        let list = try ZipArchive.entries(of: zip)
        XCTAssertEqual(list.map(\.path), ["a.txt", "sub/b.bin"])
        let out = dir.appendingPathComponent("out")
        let names = try ZipArchive.extract(zip, to: out)
        XCTAssertEqual(names.count, 2)
        XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("sub/b.bin")), try Data(contentsOf: b))
    }
}

final class MatrixTests: XCTestCase {
    func testCartesianAndPairwise() {
        var plan = TestMatrixPlan()
        plan.axes = [.variant: ["Regular", "Clear"], .background: ["Black", "White", "Checkerboard"], .appearance: ["Light", "Dark"], .shape: ["Capsule", "Circle", "Rectangle"]]
        XCTAssertEqual(plan.fullCount, 36)
        plan.mode = .full; plan.generate()
        XCTAssertEqual(plan.cases.count, 36)
        plan.mode = .pairwise; plan.generate()
        XCTAssertLessThan(plan.cases.count, 36)
        // Every pair of levels is covered.
        let ax = plan.activeAxes
        for i in 0..<ax.count { for j in (i + 1)..<ax.count { for a in ax[i].1 { for b in ax[j].1 {
            XCTAssertTrue(plan.cases.contains { $0.levels[ax[i].0.rawValue] == a && $0.levels[ax[j].0.rawValue] == b }, "\(a)/\(b) not covered")
        } } } }
        plan.mode = .sampled; plan.sampleCount = 5; plan.generate()
        XCTAssertEqual(plan.cases.count, 5)
    }

    func testCaseConfiguration() {
        var plan = TestMatrixPlan()
        let c = MatrixCase(levels: [MatrixAxis.variant.rawValue: "Clear", MatrixAxis.background.rawValue: "White", MatrixAxis.appearance.rawValue: "Dark"])
        let cfg = plan.configuration(for: c)
        XCTAssertEqual(cfg.variant, .clear)
        XCTAssertEqual(cfg.background.kind, .solid)
        XCTAssertEqual(cfg.appearance, .dark)
        plan.cases = [c]
        XCTAssertGreaterThan(plan.estimatedBytes(canvasPixels: 1000), 0)
    }
}

final class ReconstructionTests: XCTestCase {
    func testFitRecoversModelGeneratedData() throws {
        let w = 64, h = 48
        let bg = Synthetic.image(Synthetic.noise(w, h, seed: 3, cell: 2))
        let region = GlassRegionModel(shape: .roundedRect, elements: [CGRectCodable(CGRect(x: 12, y: 10, width: 40, height: 28))], cornerRadiusPx: 6, rotationDegrees: 0)
        // Build a sample whose target is produced by the model itself with known parameters.
        var truth = ReconstructionParameters()
        truth.values = [1.5, 0.6, 0.12, 0.10, 0.14, 1.0, 0.0, 2, 0, 12]
        var sample = try XCTUnwrap(ReconstructionSample.make(name: "s", reference: bg, test: bg, region: region, ppp: 1, maxSide: 200))
        sample.target = ReconstructionRenderer.render(truth, sample)
        let start = ReconstructionParameters.initial
        let before = ParameterEstimator.totalLoss(start, [sample]).mse
        let fit = ParameterEstimator.fit([sample], start: start, maxIterations: 300)
        XCTAssertLessThan(fit.value, before * 0.2)
        XCTAssertEqual(fit.x[1], 0.6, accuracy: 0.15)
    }

    func testRendererPassesBackgroundOutsideGlass() throws {
        let bg = Synthetic.image(Synthetic.noise(40, 40))
        let region = GlassRegionModel(shape: .circle, elements: [CGRectCodable(CGRect(x: 10, y: 10, width: 20, height: 20))], cornerRadiusPx: 0, rotationDegrees: 0)
        let s = try XCTUnwrap(ReconstructionSample.make(name: "s", reference: bg, test: bg, region: region, ppp: 1, maxSide: 200))
        let out = ReconstructionRenderer.render(ReconstructionParameters(), s)
        XCTAssertEqual(out.r[0, 0], s.background.r[0, 0])
    }
}

final class CaptureHelperTests: XCTestCase {
    func testMeanAbsDifference() {
        let ctx = CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        let a = ctx.makeImage()!
        XCTAssertEqual(CaptureCoordinator.meanAbsDifference(a, a)!, 0, accuracy: 1e-12)
        ctx.setFillColor(CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        XCTAssertGreaterThan(CaptureCoordinator.meanAbsDifference(a, ctx.makeImage()!)!, 0.3)
    }

    func testRegionModelFromExperiment() {
        var c = SceneConfiguration(); c.shape = .roundedRect; c.geometry.cornerRadius = 10
        var e = Experiment(configuration: c, environment: EnvironmentSnapshot(), canvasSizePoints: CGSizeCodable(CGSize(width: 300, height: 300)),
                           subjectFramePoints: CGRectCodable(CGRect(x: 40, y: 50, width: 100, height: 60)))
        e.elementFramesPoints = [e.subjectFramePoints]
        let m = MainActor.assumeIsolated { CaptureCoordinator.regionModel(for: e, pixelsPerPoint: 3) }
        XCTAssertEqual(m.elements[0].x, 120); XCTAssertEqual(m.elements[0].width, 300)
        XCTAssertEqual(m.cornerRadiusPx, 30)
        XCTAssertEqual(m.shape, .roundedRect)
    }

    func testDisplayLinkStats() {
        var ts: [Double] = []
        var t = 0.0
        for i in 0..<120 { t += (i == 60 ? 0.05 : 1.0 / 60); ts.append(t) }
        let s = DisplayLinkLogger.stats(ts, nominalFPS: 60)!
        XCTAssertEqual(s.hitchCount, 1)
        XCTAssertEqual(s.medianInterval, 1.0 / 60, accuracy: 1e-9)
    }
}
