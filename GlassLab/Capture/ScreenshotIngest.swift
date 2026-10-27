import Foundation
import Photos
import UIKit
import ImageIO

/// Reads the system screenshot the operator just took (side + volume buttons). System screenshots are
/// lossless PNGs of the composited display with an embedded color profile, which makes them the
/// highest-fidelity still capture available to a third-party app.
enum ScreenshotIngest {
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Waits for the next `userDidTakeScreenshotNotification`, then fetches the newest screenshot asset.
    @MainActor
    static func nextScreenshot(timeout: Double = 120) async throws -> (CGImage, Data, Date) {
        guard await requestAccess() else { throw GlassLabError.permissionDenied("Photos access is needed to read the screenshot you take.") }
        let taken = try await waitForScreenshotNotification(timeout: timeout)
        // The asset appears in the library shortly after the notification.
        for _ in 0..<40 {
            if let r = try? await latestScreenshot(after: taken.addingTimeInterval(-2)) { return (r.0, r.1, taken) }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw GlassLabError.captureFailed("The screenshot did not appear in Photos within 10 s. With limited Photos access, add the screenshot to the allowed items.")
    }

    @MainActor
    static func waitForScreenshotNotification(timeout: Double) async throws -> Date {
        try await withThrowingTaskGroup(of: Date.self) { group in
            group.addTask { @MainActor in
                for await _ in NotificationCenter.default.notifications(named: UIApplication.userDidTakeScreenshotNotification) {
                    return Date()
                }
                throw GlassLabError.cancelled
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw GlassLabError.captureFailed("No screenshot was taken within \(Int(timeout)) s.")
            }
            let d = try await group.next()!
            group.cancelAll()
            return d
        }
    }

    static func latestScreenshot(after: Date) async throws -> (CGImage, Data)? {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0 AND creationDate >= %@", PHAssetMediaSubtype.photoScreenshot.rawValue, after as NSDate)
        opts.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(with: .image, options: opts).firstObject else { return nil }
        let reqOpts = PHImageRequestOptions()
        reqOpts.version = .original
        reqOpts.isNetworkAccessAllowed = false
        reqOpts.deliveryMode = .highQualityFormat
        let data: Data? = await withCheckedContinuation { cont in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: reqOpts) { data, _, _, _ in cont.resume(returning: data) }
        }
        guard let data, let img = ImageIOHelper.loadCGImage(data: data) else { return nil }
        return (img, data)
    }
}
