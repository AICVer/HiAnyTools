import Foundation
import CoreImage

/// 解码表观或已知合成工作域的色彩描述，不表示像素凸包或面板实测色域。
struct ImageColorInfo: Codable {
    let sdr: String
    let hdr: String
    let gainMap: String

    static let unavailable = ImageColorInfo(sdr: "未提供", hdr: "未提供", gainMap: "未提供")

    /// 保留系统原始名称；没有标准名称时不猜测原色或传递函数。
    static func spaceLabel(_ space: CGColorSpace?) -> String {
        guard let space else { return "未提供" }
        guard let name = space.name as String? else {
            return space.model == .rgb ? "自定义 RGB（未提供标准名称）" : "未提供"
        }
        if space.model == .monochrome { return "灰度 · \(name)" }
        let p3Names = [CGColorSpace.displayP3, CGColorSpace.extendedLinearDisplayP3,
                       CGColorSpace.displayP3_PQ].map { $0 as String }
        let bt2020Names = [CGColorSpace.itur_2020, CGColorSpace.extendedLinearITUR_2020,
                           CGColorSpace.itur_2100_PQ, CGColorSpace.itur_2100_HLG].map { $0 as String }
        let srgbNames = [CGColorSpace.sRGB, CGColorSpace.linearSRGB,
                         CGColorSpace.extendedSRGB, CGColorSpace.extendedLinearSRGB,
                         CGColorSpace.itur_709].map { $0 as String }
        if p3Names.contains(name) { return "Display P3 原色 · \(name)" }
        if bt2020Names.contains(name) { return "BT.2020 原色 · \(name)" }
        if srgbNames.contains(name) {
            return "sRGB / BT.709 原色 · \(name)"
        }
        return name
    }
}

extension LoadedImage {
    /// 读取当前对象声明的色彩空间；增益数组不冒充RGB色域，合成域显式标注。
    func colorInfo(generatedHDR: Bool = false) -> ImageColorInfo {
        let hdrLabel: String
        if generatedHDR {
            hdrLabel = "线性 BT.2020（合成工作域，尚未编码）"
        } else if isHDR {
            hdrLabel = ImageColorInfo.spaceLabel(hdr.colorSpace)
        } else {
            hdrLabel = "不适用（SDR 源图；增强工作域为线性 BT.2020）"
        }
        let gainLabel: String
        if generatedHDR && gainMap != nil {
            gainLabel = "不适用（合成灰度增益图）"
        } else if let gainMap {
            let kind = gainMap.colorSpace?.model == .monochrome ? "灰度增益图" : "增益数据"
            gainLabel = "不适用（\(kind)）；数据空间：\(ImageColorInfo.spaceLabel(gainMap.colorSpace))"
        } else {
            gainLabel = "未提供"
        }
        return ImageColorInfo(sdr: ImageColorInfo.spaceLabel(sdrColorSpace ?? sdr.colorSpace),
                              hdr: hdrLabel, gainMap: gainLabel)
    }
}
