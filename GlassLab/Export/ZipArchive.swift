import Foundation

/// Minimal ZIP writer/reader using the STORED method (no compression). PNG, HEVC and MOV data is
/// already compressed, and stored entries keep the archive simple to verify byte for byte.
/// Files are streamed from disk in 1 MB chunks. ZIP64 is not supported (each file and the archive must be < 4 GB).
enum ZipArchive {
    struct Entry { var path: String; var source: URL }

    static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data, seed: UInt32 = 0) -> UInt32 {
        var c = ~seed
        data.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
            for byte in b { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        }
        return ~c
    }

    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    static func write(entries: [Entry], to url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let out = FileHandle(forWritingAtPath: url.path) else { throw GlassLabError.storage("cannot create \(url.lastPathComponent)") }
        defer { try? out.close() }
        var central = Data()
        var offset: UInt32 = 0
        for e in entries {
            if Task.isCancelled { throw GlassLabError.cancelled }
            let attrs = try FileManager.default.attributesOfItem(atPath: e.source.path)
            let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            guard size < UInt64(UInt32.max) else { throw GlassLabError.storage("\(e.path) is larger than 4 GB") }
            // CRC pass
            guard let inH = FileHandle(forReadingAtPath: e.source.path) else { throw GlassLabError.storage("cannot read \(e.path)") }
            var crc: UInt32 = 0
            while true { let chunk = inH.readData(ofLength: 1 << 20); if chunk.isEmpty { break }; crc = crc32(chunk, seed: crc) }
            try inH.seek(toOffset: 0)
            let name = Data(e.path.utf8)
            var local = Data()
            local += le32(0x04034b50); local += le16(20); local += le16(0x0800) // UTF-8 names
            local += le16(0); local += le16(0); local += le16(0x21)              // stored, time, date (1980-01-01)
            local += le32(crc); local += le32(UInt32(size)); local += le32(UInt32(size))
            local += le16(UInt16(name.count)); local += le16(0); local += name
            out.write(local)
            while true { let chunk = inH.readData(ofLength: 1 << 20); if chunk.isEmpty { break }; out.write(chunk) }
            try inH.close()
            var cd = Data()
            cd += le32(0x02014b50); cd += le16(20); cd += le16(20); cd += le16(0x0800)
            cd += le16(0); cd += le16(0); cd += le16(0x21)
            cd += le32(crc); cd += le32(UInt32(size)); cd += le32(UInt32(size))
            cd += le16(UInt16(name.count)); cd += le16(0); cd += le16(0); cd += le16(0); cd += le16(0)
            cd += le32(0); cd += le32(offset); cd += name
            central += cd
            let next = UInt64(offset) + UInt64(local.count) + size
            guard next < UInt64(UInt32.max) else { throw GlassLabError.storage("archive exceeds 4 GB") }
            offset = UInt32(next)
        }
        out.write(central)
        var end = Data()
        end += le32(0x06054b50); end += le16(0); end += le16(0)
        end += le16(UInt16(entries.count)); end += le16(UInt16(entries.count))
        end += le32(UInt32(central.count)); end += le32(offset); end += le16(0)
        out.write(end)
    }

    struct ReadEntry { var path: String; var offset: UInt64; var size: UInt32; var crc: UInt32; var method: UInt16 }

    /// Lists entries from the central directory.
    static func entries(of url: URL) throws -> [ReadEntry] {
        guard let h = FileHandle(forReadingAtPath: url.path) else { throw GlassLabError.storage("cannot open archive") }
        defer { try? h.close() }
        let fileSize = try h.seekToEnd()
        let tail = min(fileSize, 65_557)
        try h.seek(toOffset: fileSize - tail)
        let buf = h.readData(ofLength: Int(tail))
        func u16(_ d: Data, _ o: Int) -> UInt16 { UInt16(d[d.startIndex + o]) | UInt16(d[d.startIndex + o + 1]) << 8 }
        func u32(_ d: Data, _ o: Int) -> UInt32 { UInt32(u16(d, o)) | UInt32(u16(d, o + 2)) << 16 }
        var eocd = -1
        var i = buf.count - 22
        while i >= 0 { if u32(buf, i) == 0x06054b50 { eocd = i; break }; i -= 1 }
        guard eocd >= 0 else { throw GlassLabError.invalidData("not a ZIP archive") }
        let count = Int(u16(buf, eocd + 10))
        let cdSize = Int(u32(buf, eocd + 12)), cdOffset = UInt64(u32(buf, eocd + 16))
        try h.seek(toOffset: cdOffset)
        let cd = h.readData(ofLength: cdSize)
        var out: [ReadEntry] = []
        var p = 0
        for _ in 0..<count {
            guard p + 46 <= cd.count, u32(cd, p) == 0x02014b50 else { throw GlassLabError.invalidData("corrupt central directory") }
            let method = u16(cd, p + 10), crc = u32(cd, p + 16), size = u32(cd, p + 24)
            let nlen = Int(u16(cd, p + 28)), elen = Int(u16(cd, p + 30)), clen = Int(u16(cd, p + 32))
            let localOffset = UInt64(u32(cd, p + 42))
            let name = String(decoding: cd[(cd.startIndex + p + 46)..<(cd.startIndex + p + 46 + nlen)], as: UTF8.self)
            // Data starts after the local header, whose extra field may differ from the central one.
            try h.seek(toOffset: localOffset)
            let lh = h.readData(ofLength: 30)
            let dataStart = localOffset + 30 + UInt64(u16(lh, 26)) + UInt64(u16(lh, 28))
            out.append(ReadEntry(path: name, offset: dataStart, size: size, crc: crc, method: method))
            p += 46 + nlen + elen + clen
        }
        return out
    }

    /// Extracts STORED entries into `directory`, verifying each CRC-32. Rejects path traversal.
    static func extract(_ url: URL, to directory: URL) throws -> [String] {
        let list = try entries(of: url)
        guard let h = FileHandle(forReadingAtPath: url.path) else { throw GlassLabError.storage("cannot open archive") }
        defer { try? h.close() }
        var names: [String] = []
        for e in list {
            guard e.method == 0 else { throw GlassLabError.unsupported("\(e.path) is compressed; only Glass Lab bundles (stored entries) can be imported") }
            guard !e.path.contains(".."), !e.path.hasPrefix("/") else { throw GlassLabError.invalidData("unsafe path \(e.path)") }
            let dest = directory.appendingPathComponent(e.path)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if e.path.hasSuffix("/") { continue }
            try h.seek(toOffset: e.offset)
            FileManager.default.createFile(atPath: dest.path, contents: nil)
            guard let o = FileHandle(forWritingAtPath: dest.path) else { throw GlassLabError.storage("cannot write \(e.path)") }
            var remaining = Int(e.size), crc: UInt32 = 0
            while remaining > 0 {
                let chunk = h.readData(ofLength: min(remaining, 1 << 20))
                if chunk.isEmpty { break }
                crc = crc32(chunk, seed: crc); o.write(chunk); remaining -= chunk.count
            }
            try o.close()
            guard remaining == 0, crc == e.crc else { throw GlassLabError.invalidData("CRC mismatch in \(e.path)") }
            names.append(e.path)
        }
        return names
    }
}
