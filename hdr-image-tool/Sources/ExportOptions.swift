import Foundation
import CoreGraphics

/// 导出参数：先确定像素尺寸与 DPI，再在质量上限内满足目标字节数。
struct ExportOptions: Codable {
    var quality: Double = 0.92
    var dpi: Int?
    var width: Int?
    var height: Int?
    var targetBytes: Int?
    var hdrColorSpace: HDRColorSpace = .bt2020
    var sdrColorSpace: SDRColorSpace = .sRGB
    var sdrMapping: SDRMapping = .xyz

    init(quality: Double = 0.92, dpi: Int? = nil, width: Int? = nil,
         height: Int? = nil, targetBytes: Int? = nil,
         hdrColorSpace: HDRColorSpace = .bt2020, sdrColorSpace: SDRColorSpace = .sRGB,
         sdrMapping: SDRMapping = .xyz) {
        self.quality = quality
        self.dpi = dpi
        self.width = width
        self.height = height
        self.targetBytes = targetBytes
        self.hdrColorSpace = hdrColorSpace
        self.sdrColorSpace = sdrColorSpace
        self.sdrMapping = sdrMapping
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        quality = try values.decodeIfPresent(Double.self, forKey: .quality) ?? 0.92
        dpi = try values.decodeIfPresent(Int.self, forKey: .dpi)
        width = try values.decodeIfPresent(Int.self, forKey: .width)
        height = try values.decodeIfPresent(Int.self, forKey: .height)
        targetBytes = try values.decodeIfPresent(Int.self, forKey: .targetBytes)
        hdrColorSpace = try values.decodeIfPresent(HDRColorSpace.self, forKey: .hdrColorSpace) ?? .bt2020
        sdrColorSpace = try values.decodeIfPresent(SDRColorSpace.self, forKey: .sdrColorSpace) ?? .sRGB
        sdrMapping = try values.decodeIfPresent(SDRMapping.self, forKey: .sdrMapping) ?? .xyz
    }

    func outputSize(for original: CGSize) throws -> CGSize {
        guard quality.isFinite, (0...1).contains(quality),
              dpi.map({ (1...2400).contains($0) }) ?? true,
              targetBytes.map({ $0 > 0 }) ?? true,
              width == nil || height == nil,
              width.map({ $0 > 0 }) ?? true, height.map({ $0 > 0 }) ?? true,
              original.width > 0, original.height > 0 else { throw ImageFailure.invalidOptions }
        let scale = width.map { Double($0) / original.width }
            ?? height.map { Double($0) / original.height } ?? 1
        let size = CGSize(width: max(1, (original.width * scale).rounded()),
                          height: max(1, (original.height * scale).rounded()))
        guard size.width.isFinite, size.height.isFinite,
              size.width * size.height <= 50_000_000 else { throw ImageFailure.imageTooLarge }
        return size
    }
}
