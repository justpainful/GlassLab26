import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Accelerate

/// A single-channel float image (row-major).
struct Plane: Sendable {
    var width: Int
    var height: Int
    var data: [Float]

    init(width: Int, height: Int, fill: Float = 0) {
        self.width = width; self.height = height
        data = [Float](repeating: fill, count: width * height)
    }
    init(width: Int, height: Int, data: [Float]) {
        precondition(data.count == width * height)
        self.width = width; self.height = height; self.data = data
    }

    @inline(__always) subscript(x: Int, y: Int) -> Float {
        get { data[y * width + x] }
        set { data[y * width + x] = newValue }
    }

    /// Clamped bilinear sample.
    func sample(_ x: Double, _ y: Double) -> Float {
        let xf = min(max(x, 0), Double(width - 1)), yf = min(max(y, 0), Double(height - 1))
        let x0 = Int(xf), y0 = Int(yf)
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let fx = Float(xf - Double(x0)), fy = Float(yf - Double(y0))
        let a = self[x0, y0] * (1 - fx) + self[x1, y0] * fx
        let b = self[x0, y1] * (1 - fx) + self[x1, y1] * fx
        return a * (1 - fy) + b * fy
    }

    func cropped(_ r: PixelRegion) -> Plane {
        var out = Plane(width: r.width, height: r.height)
        for y in 0..<r.height {
            let sy = min(max(r.y + y, 0), height - 1)
            for x in 0..<r.width {
                let sx = min(max(r.x + x, 0), width - 1)
                out.data[y * r.width + x] = data[sy * width + sx]
            }
        }
        return out
    }

    /// Separable Gaussian blur with clamped edges. sigma in pixels; sigma <= 0.05 returns a copy.
    func gaussianBlurred(sigma: Double) -> Plane {
        guard sigma > 0.05 else { return self }
        let radius = max(1, Int(ceil(3 * sigma)))
        var kernel = [Float](repeating: 0, count: 2 * radius + 1)
        var sum: Float = 0
        for i in -radius...radius {
            let v = Float(exp(-Double(i * i) / (2 * sigma * sigma)))
            kernel[i + radius] = v; sum += v
        }
        for i in kernel.indices { kernel[i] /= sum }
        var tmp = [Float](repeating: 0, count: data.count)
        var out = [Float](repeating: 0, count: data.count)
        let w = width, h = height
        data.withUnsafeBufferPointer { src in
            tmp.withUnsafeMutableBufferPointer { t in
                kernel.withUnsafeBufferPointer { k in
                    for y in 0..<h {
                        let row = y * w
                        for x in 0..<w {
                            var acc: Float = 0
                            for i in -radius...radius {
                                let sx = x + i < 0 ? 0 : (x + i >= w ? w - 1 : x + i)
                                acc += src[row + sx] * k[i + radius]
                            }
                            t[row + x] = acc
                        }
                    }
                }
            }
        }
        tmp.withUnsafeBufferPointer { t in
            out.withUnsafeMutableBufferPointer { o in
                kernel.withUnsafeBufferPointer { k in
                    for y in 0..<h {
                        for x in 0..<w {
                            var acc: Float = 0
                            for i in -radius...radius {
                                let sy = y + i < 0 ? 0 : (y + i >= h ? h - 1 : y + i)
                                acc += t[sy * w + x] * k[i + radius]
                            }
                            o[y * w + x] = acc
                        }
                    }
                }
            }
        }
        return Plane(width: w, height: h, data: out)
    }

    /// Sobel gradient components.
    func sobel() -> (gx: Plane, gy: Plane) {
        var gx = Plane(width: width, height: height), gy = Plane(width: width, height: height)
        guard width >= 3, height >= 3 else { return (gx, gy) }
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let a = self[x - 1, y - 1], b = self[x, y - 1], c = self[x + 1, y - 1]
                let d = self[x - 1, y], f = self[x + 1, y]
                let g = self[x - 1, y + 1], h = self[x, y + 1], i = self[x + 1, y + 1]
                gx[x, y] = (c + 2 * f + i - a - 2 * d - g) / 8
                gy[x, y] = (g + 2 * h + i - a - 2 * b - c) / 8
                _ = d
            }
        }
        return (gx, gy)
    }

    func gradientMagnitude() -> Plane {
        let (gx, gy) = sobel()
        var out = Plane(width: width, height: height)
        for i in data.indices { out.data[i] = (gx.data[i] * gx.data[i] + gy.data[i] * gy.data[i]).squareRoot() }
        return out
    }

    /// Box-average downsampling by an integer factor.
    func downsampled(by f: Int) -> Plane {
        guard f > 1 else { return self }
        let w = width / f, h = height / f
        var out = Plane(width: w, height: h)
        let inv = 1 / Float(f * f)
        for y in 0..<h {
            for x in 0..<w {
                var acc: Float = 0
                for dy in 0..<f { for dx in 0..<f { acc += self[x * f + dx, y * f + dy] } }
                out[x, y] = acc * inv
            }
        }
        return out
    }

    func values(in mask: Mask) -> [Double] {
        var v: [Double] = []
        v.reserveCapacity(mask.count)
        for i in data.indices where mask.data[i] != 0 { v.append(Double(data[i])) }
        return v
    }

    func mean(in mask: Mask? = nil) -> Double {
        var s = 0.0, n = 0
        for i in data.indices where mask == nil || mask!.data[i] != 0 { s += Double(data[i]); n += 1 }
        return n > 0 ? s / Double(n) : .nan
    }

    func std(in mask: Mask? = nil) -> Double {
        let m = mean(in: mask)
        var s = 0.0, n = 0
        for i in data.indices where mask == nil || mask!.data[i] != 0 { let d = Double(data[i]) - m; s += d * d; n += 1 }
        return n > 1 ? (s / Double(n - 1)).squareRoot() : .nan
    }

    static func - (a: Plane, b: Plane) -> Plane {
        var o = a
        vDSP.subtract(a.data, b.data, result: &o.data)
        return o
    }
}

/// Binary region mask aligned with a Plane.
struct Mask: Sendable {
    var width: Int
    var height: Int
    var data: [UInt8]

    init(width: Int, height: Int, fill: Bool = false) {
        self.width = width; self.height = height
        data = [UInt8](repeating: fill ? 1 : 0, count: width * height)
    }

    var count: Int { data.reduce(0) { $0 + Int($1) } }
    var isEmpty: Bool { !data.contains(1) }

    static func & (a: Mask, b: Mask) -> Mask {
        var o = a
        for i in o.data.indices { o.data[i] = (a.data[i] != 0 && b.data[i] != 0) ? 1 : 0 }
        return o
    }

    var boundingBox: PixelRegion? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height { for x in 0..<width where data[y * width + x] != 0 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        return maxX < 0 ? nil : PixelRegion(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    func cropped(_ r: PixelRegion) -> Mask {
        var out = Mask(width: r.width, height: r.height)
        for y in 0..<r.height { for x in 0..<r.width {
            let sx = r.x + x, sy = r.y + y
            if sx >= 0, sy >= 0, sx < width, sy < height { out.data[y * r.width + x] = data[sy * width + sx] }
        } }
        return out
    }
}

/// An RGB image decoded into linear Display P3 floats. The decoding goes through Core Graphics
/// color management, so the source's embedded profile and transfer function are honoured.
struct LinearImage: Sendable {
    var r: Plane
    var g: Plane
    var b: Plane
    /// Name of the color space the source declared (or "untagged").
    var sourceColorSpace: String

    var width: Int { r.width }
    var height: Int { r.height }

    static let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
    static let workingSpaceName = "Linear Display P3 (extended, float32)"

    init(r: Plane, g: Plane, b: Plane, sourceColorSpace: String) {
        self.r = r; self.g = g; self.b = b; self.sourceColorSpace = sourceColorSpace
    }

    init(width: Int, height: Int, fill: (Float, Float, Float) = (0, 0, 0)) {
        r = Plane(width: width, height: height, fill: fill.0)
        g = Plane(width: width, height: height, fill: fill.1)
        b = Plane(width: width, height: height, fill: fill.2)
        sourceColorSpace = LinearImage.workingSpaceName
    }

    init?(cgImage: CGImage) {
        let w = cgImage.width, h = cgImage.height
        guard w > 0, h > 0 else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        var buffer = [Float](repeating: 0, count: w * h * 4)
        let ok: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 32, bytesPerRow: w * 16,
                                      space: LinearImage.workingSpace, bitmapInfo: info.rawValue) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        var rp = Plane(width: w, height: h), gp = Plane(width: w, height: h), bp = Plane(width: w, height: h)
        for i in 0..<(w * h) {
            let a = buffer[i * 4 + 3]
            let inv: Float = a > 0 ? 1 / a : 0
            rp.data[i] = buffer[i * 4] * inv
            gp.data[i] = buffer[i * 4 + 1] * inv
            bp.data[i] = buffer[i * 4 + 2] * inv
        }
        self.init(r: rp, g: gp, b: bp, sourceColorSpace: (cgImage.colorSpace?.name as String?) ?? "untagged")
    }

    static func load(url: URL) -> LinearImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return LinearImage(cgImage: img)
    }

    func luminance() -> Plane {
        var y = Plane(width: width, height: height)
        for i in y.data.indices { y.data[i] = ColorScience.luminanceP3(r.data[i], g.data[i], b.data[i]) }
        return y
    }

    func cropped(_ region: PixelRegion) -> LinearImage {
        LinearImage(r: r.cropped(region), g: g.cropped(region), b: b.cropped(region), sourceColorSpace: sourceColorSpace)
    }

    func downsampled(by f: Int) -> LinearImage {
        LinearImage(r: r.downsampled(by: f), g: g.downsampled(by: f), b: b.downsampled(by: f), sourceColorSpace: sourceColorSpace)
    }

    func blurred(sigma: Double) -> LinearImage {
        LinearImage(r: r.gaussianBlurred(sigma: sigma), g: g.gaussianBlurred(sigma: sigma), b: b.gaussianBlurred(sigma: sigma), sourceColorSpace: sourceColorSpace)
    }

    /// Integer translation (pixels), edges clamped.
    func shifted(dx: Int, dy: Int) -> LinearImage {
        func sh(_ p: Plane) -> Plane {
            var o = Plane(width: p.width, height: p.height)
            for y in 0..<p.height { for x in 0..<p.width {
                let sx = min(max(x - dx, 0), p.width - 1), sy = min(max(y - dy, 0), p.height - 1)
                o.data[y * p.width + x] = p.data[sy * p.width + sx]
            } }
            return o
        }
        return LinearImage(r: sh(r), g: sh(g), b: sh(b), sourceColorSpace: sourceColorSpace)
    }

    /// Encodes to a CGImage in the requested space (8 or 16 bits per channel, non-linear).
    func cgImage(space: CGColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!, bits16: Bool = false) -> CGImage? {
        let w = width, h = height
        var buffer = [Float](repeating: 1, count: w * h * 4)
        for i in 0..<(w * h) {
            buffer[i * 4] = r.data[i]; buffer[i * 4 + 1] = g.data[i]; buffer[i * 4 + 2] = b.data[i]; buffer[i * 4 + 3] = 1
        }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let floatImage: CGImage? = buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 32, bytesPerRow: w * 16,
                                      space: LinearImage.workingSpace, bitmapInfo: info.rawValue) else { return nil }
            return ctx.makeImage()
        }
        guard let floatImage else { return nil }
        let bpc = bits16 ? 16 : 8
        let outInfo: UInt32 = CGImageAlphaInfo.noneSkipLast.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: bpc, bytesPerRow: 0, space: space, bitmapInfo: outInfo) else { return nil }
        ctx.draw(floatImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}

enum ImageIOHelper {
    /// Writes a PNG preserving the image's color space. Returns the byte count.
    @discardableResult
    static func writePNG(_ image: CGImage, to url: URL) throws -> Int {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw GlassLabError.storage("cannot create PNG destination")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw GlassLabError.storage("PNG encoding failed") }
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    static func writeHEIC(_ image: CGImage, to url: URL, quality: Double = 1.0) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            throw GlassLabError.storage("HEIC is not supported on this device")
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw GlassLabError.storage("HEIC encoding failed") }
    }

    static func loadCGImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func loadCGImage(data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
