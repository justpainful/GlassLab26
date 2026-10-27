import Foundation
import os

enum Format {
    /// Formats a value to `digits` significant digits, never padding with precision the
    /// measurement does not have. nil → "N/A".
    static func number(_ v: Double?, digits: Int = 3) -> String {
        guard let v, v.isFinite else { return "N/A" }
        if v == 0 { return "0" }
        let d = max(1, digits)
        let magnitude = Int(floor(log10(abs(v))))
        let decimals = max(0, d - 1 - magnitude)
        if abs(v) >= 1e6 || abs(v) < 1e-4 {
            return String(format: "%.\(d - 1)e", v)
        }
        return String(format: "%.\(min(decimals, 8))f", v)
    }

    static func measurement(_ m: Measurement) -> String {
        guard let v = m.value else { return "N/A" }
        var s = number(v, digits: m.significantDigits)
        if !m.unit.isEmpty { s += " " + m.unit }
        return s
    }

    static func uncertainty(_ m: Measurement) -> String? {
        guard let u = m.uncertainty else { return nil }
        return "± " + number(u.halfWidth, digits: 2) + (m.unit.isEmpty ? "" : " " + m.unit) + " (" + u.kind.rawValue + ")"
    }

    static func bytes(_ b: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
    }

    static func milliseconds(_ seconds: Double?, digits: Int = 3) -> String {
        guard let s = seconds else { return "N/A" }
        return number(s * 1000, digits: digits) + " ms"
    }

    static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

enum Log {
    static let app = Logger(subsystem: "com.justpainful.glasslab", category: "app")
    static let capture = Logger(subsystem: "com.justpainful.glasslab", category: "capture")
    static let analysis = Logger(subsystem: "com.justpainful.glasslab", category: "analysis")
    static let storage = Logger(subsystem: "com.justpainful.glasslab", category: "storage")
}

enum GlassLabError: LocalizedError {
    case captureFailed(String)
    case permissionDenied(String)
    case invalidData(String)
    case storage(String)
    case cancelled
    case thermalLimit(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .captureFailed(let s): return "Capture failed: \(s)"
        case .permissionDenied(let s): return "Permission denied: \(s)"
        case .invalidData(let s): return "Invalid data: \(s)"
        case .storage(let s): return "Storage error: \(s)"
        case .cancelled: return "Cancelled"
        case .thermalLimit(let s): return "Paused for thermal pressure: \(s)"
        case .unsupported(let s): return "Unsupported: \(s)"
        }
    }
}
