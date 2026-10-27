import UIKit

/// PDF research report. It reports what was measured and how; conclusions are limited to factual
/// summaries of validity plus the operator's own session notes.
enum ReportGenerator {
    static let page = CGRect(x: 0, y: 0, width: 595, height: 842)  // A4 in points
    static let margin: CGFloat = 40

    final class Cursor {
        let ctx: UIGraphicsPDFRendererContext
        var y: CGFloat = margin
        var pageNumber = 0
        init(_ ctx: UIGraphicsPDFRendererContext) { self.ctx = ctx; newPage() }

        func newPage() {
            ctx.beginPage()
            pageNumber += 1
            y = margin
            let footer = NSAttributedString(string: "Glass Lab research report · page \(pageNumber)",
                                            attributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.gray])
            footer.draw(at: CGPoint(x: margin, y: page.height - 24))
        }

        func ensure(_ h: CGFloat) { if y + h > page.height - 40 { newPage() } }

        func text(_ s: String, size: CGFloat = 10, weight: UIFont.Weight = .regular, color: UIColor = .black, mono: Bool = false, spacing: CGFloat = 4) {
            let font = mono ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : UIFont.systemFont(ofSize: size, weight: weight)
            let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
            let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
            let width = page.width - 2 * margin
            let h = ceil(a.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil).height)
            if h > page.height - 2 * margin {
                // Very long blocks: split by lines.
                for line in s.components(separatedBy: "\n") { text(line, size: size, weight: weight, color: color, mono: mono, spacing: 0) }
                y += spacing
                return
            }
            ensure(h)
            a.draw(with: CGRect(x: margin, y: y, width: width, height: h), options: [.usesLineFragmentOrigin], context: nil)
            y += h + spacing
        }

        func heading(_ s: String) { y += 6; text(s, size: 14, weight: .semibold, spacing: 6) }

        func image(_ img: UIImage, maxHeight: CGFloat = 220, caption: String? = nil) {
            let width = page.width - 2 * margin
            let scale = min(width / img.size.width, maxHeight / img.size.height, 1)
            let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
            ensure(size.height + 18)
            img.draw(in: CGRect(x: margin, y: y, width: size.width, height: size.height))
            y += size.height + 2
            if let caption { text(caption, size: 8, color: .darkGray) }
            y += 4
        }

        func images(_ list: [(UIImage, String)], maxHeight: CGFloat = 200) {
            let width = (page.width - 2 * margin - 10) / 2
            var i = 0
            while i < list.count {
                let pair = Array(list[i..<min(i + 2, list.count)])
                let heights = pair.map { min(maxHeight, $0.0.size.height * width / max(1, $0.0.size.width)) }
                let h = heights.max() ?? 0
                ensure(h + 20)
                for (k, item) in pair.enumerated() {
                    let s = min(width / item.0.size.width, maxHeight / item.0.size.height)
                    item.0.draw(in: CGRect(x: margin + CGFloat(k) * (width + 10), y: y, width: item.0.size.width * s, height: item.0.size.height * s))
                    NSAttributedString(string: item.1, attributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.darkGray])
                        .draw(in: CGRect(x: margin + CGFloat(k) * (width + 10), y: y + h + 2, width: width, height: 12))
                }
                y += h + 18
                i += 2
            }
        }
    }

    static func render(session: ExperimentSession, sessionDirectory: URL, to url: URL) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: {
            let f = UIGraphicsPDFRendererFormat()
            f.documentInfo = [kCGPDFContextTitle as String: session.title, kCGPDFContextCreator as String: "Glass Lab"]
            return f
        }())
        try renderer.writePDF(to: url) { ctx in
            let c = Cursor(ctx)
            c.text(session.title, size: 22, weight: .bold, spacing: 2)
            c.text("Glass Lab research report · generated \(Format.timestamp.string(from: Date()))", size: 9, color: .darkGray, spacing: 12)

            c.heading("Environment")
            let env = session.environment
            c.text("""
            Device \(env.machineIdentifier) (\(env.idiom)) · \(env.systemName) \(env.systemVersion)\(env.isSimulator ? " · SIMULATOR (not a reference for visual fidelity)" : "")
            App \(env.appVersion) (\(env.appBuild)) · SDK \(env.sdkName) \(env.sdkBuild) · Xcode \(env.xcodeVersion)
            Screen \(Int(env.screenBoundsPoints.width))x\(Int(env.screenBoundsPoints.height)) pt, scale \(env.scale), native scale \(env.nativeScale), gamut \(env.displayGamut), max \(env.maximumFramesPerSecond) fps
            Interface \(env.interfaceStyle) · Reduce Transparency \(env.reduceTransparency) · Increase Contrast \(env.increaseContrast) · Reduce Motion \(env.reduceMotion) · Bold Text \(env.boldText)
            Thermal \(env.thermalState) · Low Power \(env.lowPowerMode) · Content size \(env.contentSizeCategory)
            """ + (env.userEntered.isEmpty ? "" : "\nOperator-entered: " + env.userEntered.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")),
                   size: 9, mono: true)

            for (idx, e) in session.experiments.enumerated() {
                c.newPage()
                c.heading("Experiment \(idx + 1): \(e.title)")
                c.text("ID \(e.id.uuidString) · \(Format.timestamp.string(from: e.createdAt)) · validity \(e.validity.status.rawValue)" +
                       (e.validity.reasons.isEmpty ? "" : " (\(e.validity.reasons.joined(separator: "; ")))"), size: 9, color: .darkGray)
                let cfg = e.configuration
                c.text("""
                API: \(NativeGlass.apiDescription(cfg))
                Geometry: \(Format.number(cfg.geometry.width, digits: 4))x\(Format.number(cfg.geometry.height, digits: 4)) pt, corner \(Format.number(cfg.geometry.cornerRadius, digits: 3)) pt, rotation \(Format.number(cfg.geometry.rotation, digits: 3)) deg, scale \(cfg.geometry.scale), elements \(cfg.geometry.elementCount)
                Background: \(cfg.background.summary); base \(cfg.background.base.hex); contrast \(cfg.background.contrast); saturation \(cfg.background.saturation)
                Appearance \(cfg.appearance.rawValue) · capture \(cfg.captureMethod.rawValue) · reference mode \(cfg.referenceMode.rawValue)
                """, size: 9, mono: true)
                var imgs: [(UIImage, String)] = []
                for f in e.referenceFrames.suffix(1) + e.resultFrames.suffix(1) {
                    if let i = UIImage(contentsOfFile: sessionDirectory.appendingPathComponent("frames").appendingPathComponent(f.fileName).path) {
                        imgs.append((i, "\(f.role.rawValue) · \(f.pixelWidth)x\(f.pixelHeight) px · \(f.captureMethod.rawValue) · sha256 \(f.sha256.prefix(12))"))
                    }
                }
                if !imgs.isEmpty { c.images(imgs) }
                for f in (e.referenceFrames.suffix(1) + e.resultFrames.suffix(1)) where !f.pipelineNotes.isEmpty {
                    c.text("Pipeline (\(f.role.rawValue)): " + f.pipelineNotes.joined(separator: " "), size: 8, color: .darkGray)
                }
                guard let run = e.latestAnalysis else { c.text("Not analysed.", size: 10, color: .darkGray); continue }
                c.heading("Measurements")
                c.text("Analysis \(Format.timestamp.string(from: run.startedAt)) · app \(run.appVersion) · validity \(run.validity.status.rawValue)", size: 8, color: .darkGray)
                for m in run.measurements {
                    var line = "\(m.name): \(Format.measurement(m))"
                    if let u = Format.uncertainty(m) { line += " " + u }
                    line += "  [\(m.provenance.rawValue) · \(m.confidence.level.rawValue) · \(m.validity.status.rawValue)]"
                    c.text(line, size: 8.5, weight: .medium, mono: true, spacing: 0)
                    var detail = "  \(m.algorithm) (\(m.algorithmVersion)); n=\(m.sampleCount); \(m.confidence.justification)"
                    if !m.validity.reasons.isEmpty { detail += "; " + m.validity.reasons.joined(separator: "; ") }
                    if let n = m.notes { detail += "; " + n }
                    c.text(detail, size: 7.5, color: .darkGray, spacing: 3)
                }
                var derived: [(UIImage, String)] = []
                for f in run.derivedFrames {
                    if let i = UIImage(contentsOfFile: sessionDirectory.appendingPathComponent("derived").appendingPathComponent(f.fileName).path) {
                        derived.append((i, f.pipelineNotes.joined(separator: " · ")))
                    }
                }
                if !derived.isEmpty { c.heading("Graphs & heatmaps"); c.images(derived, maxHeight: 180) }
                if !run.log.isEmpty { c.text("Log: " + run.log.joined(separator: " "), size: 8, color: .darkGray) }
            }

            c.newPage()
            c.heading("Mathematical methodology")
            for model in ResearchCatalog.models {
                c.text(model.title, size: 10, weight: .semibold, spacing: 1)
                c.text(model.equation, size: 9, mono: true, spacing: 1)
                c.text(model.usage + " Limits: " + model.limits, size: 8.5, color: .darkGray, spacing: 6)
            }
            c.heading("Measurement limitations")
            for l in ResearchCatalog.limitations { c.text("• " + l, size: 8.5, spacing: 2) }
            c.heading("Conclusions")
            let all = session.experiments.compactMap(\.latestAnalysis).flatMap(\.measurements)
            let valid = all.filter { $0.validity.isUsable && $0.value != nil }.count
            c.text("\(session.experiments.count) experiment(s); \(all.count) measurement(s), of which \(valid) produced a usable value and \(all.count - valid) are N/A or invalid with stated reasons. No value in this report is a published Apple parameter.", size: 9)
            if !session.notes.isEmpty { c.text("Operator notes: " + session.notes, size: 9) }
        }
    }
}
