import Foundation
import zlib

struct HDRLightLevels {
    let maxCLL: Double
    let maxFALL: Double
}

/// 为系统编码的 PQ PNG 补充标准 cLLI；保留原像素压缩数据和色彩配置。
enum HDRPNG {
    static func addingLightLevels(to data: Data, levels: HDRLightLevels) throws -> Data {
        guard data.count >= 33, data.prefix(8) == Data([137,80,78,71,13,10,26,10]),
              [levels.maxCLL, levels.maxFALL].allSatisfy({
                  $0.isFinite && $0 >= 0 && $0 * 10_000 <= Double(Int32.max)
              }) else { throw ImageFailure.invalidExport }
        var payload = Data()
        append(UInt32((levels.maxCLL * 10_000).rounded()), to: &payload)
        append(UInt32((min(levels.maxFALL, levels.maxCLL) * 10_000).rounded()), to: &payload)
        var body = Data("cLLI".utf8)
        body.append(payload)
        let checksum = body.withUnsafeBytes {
            crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt($0.count))
        }
        var chunk = Data()
        append(UInt32(payload.count), to: &chunk)
        chunk.append(body)
        append(UInt32(checksum), to: &chunk)
        var result = Data(data.prefix(8))
        var offset = 8
        var inserted = false
        while offset < data.count {
            guard offset + 12 <= data.count else { throw ImageFailure.invalidExport }
            let length = data[offset..<offset+4].reduce(0) { ($0 << 8) | Int($1) }
            guard length <= data.count - offset - 12 else { throw ImageFailure.invalidExport }
            let kind = data[offset+4..<offset+8]
            if kind != Data("cLLI".utf8) { result.append(data[offset..<offset+length+12]) }
            if kind == Data("IHDR".utf8) {
                result.append(chunk)
                inserted = true
            }
            offset += length + 12
        }
        guard inserted else { throw ImageFailure.invalidExport }
        return result
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
}
