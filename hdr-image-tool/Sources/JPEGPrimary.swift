import Foundation

/// 隔离 JPEG 的原始主图扫描，保留 ICC/EXIF，避免 HDR 辅助标记影响 SDR 基图解读。
enum JPEGPrimary {
    static func sdrData(at url: URL) throws -> Data {
        let original = try Data(contentsOf: url, options: .mappedIfSafe)
        return try original.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard bytes.count >= 4, bytes[0] == 0xff, bytes[1] == 0xd8 else { throw ImageFailure.invalidImage }
            var result = Data([0xff, 0xd8])
            var offset = 2
            var scanStart: Int?
            while offset < bytes.count {
                if let start = scanStart {
                    if bytes[offset] != 0xff { offset += 1; continue }
                    var marker = offset + 1
                    while marker < bytes.count && bytes[marker] == 0xff { marker += 1 }
                    guard marker < bytes.count else { throw ImageFailure.invalidImage }
                    if bytes[marker] == 0 || (0xd0...0xd7).contains(bytes[marker]) {
                        offset = marker + 1
                        continue
                    }
                    // 只在真实扫描的标记处结束，不能误读 EXIF 缩略图中的 EOI。
                    result.append(original[start..<offset])
                    scanStart = nil
                }
                guard bytes[offset] == 0xff else { throw ImageFailure.invalidImage }
                var marker = offset + 1
                while marker < bytes.count && bytes[marker] == 0xff { marker += 1 }
                guard marker < bytes.count else { throw ImageFailure.invalidImage }
                let code = bytes[marker]
                if code == 0xd9 {
                    result.append(original[offset...marker])
                    return result
                }
                if code == 0x01 || (0xd0...0xd7).contains(code) {
                    result.append(original[offset...marker])
                    offset = marker + 1
                    continue
                }
                guard marker + 2 < bytes.count else { throw ImageFailure.invalidImage }
                let length = Int(bytes[marker + 1]) * 256 + Int(bytes[marker + 2])
                let end = marker + 1 + length
                guard length >= 2, end <= bytes.count else { throw ImageFailure.invalidImage }
                let payload = bytes[(marker + 3)..<end]
                let xmp = code == 0xe1 && (
                    payload.starts(with: Array("http://ns.adobe.com/xap/1.0/\0".utf8)) ||
                    payload.starts(with: Array("http://ns.adobe.com/xmp/extension/\0".utf8)))
                let auxiliary = code == 0xe2 && (
                    payload.starts(with: Array("MPF\0".utf8)) ||
                    payload.starts(with: Array("urn:iso:std:iso:ts:21496:-1".utf8)) ||
                    payload.starts(with: Array("urn:iso:std:iso:21496:-1".utf8)))
                if !xmp && !auxiliary { result.append(original[offset..<end]) }
                offset = end
                if code == 0xda { scanStart = end }
            }
            throw ImageFailure.invalidImage
        }
    }
}
