import Foundation
import CoreImage

enum HistogramChannel: String, CaseIterable, Codable {
    case red = "R", green = "G", blue = "B", luminance = "Y"
    case hue = "H", saturation = "S", value = "V"

    var usesHDR: Bool { [.red, .green, .blue, .luminance].contains(self) }
    var unit: String {
        switch self {
        case .luminance: return "nit"
        case .hue: return "°"
        case .red, .green, .blue: return "倍参考白"
        case .saturation, .value: return "归一化"
        }
    }
}

struct HistogramDistribution: Codable {
    var bins = [Int](repeating: 0, count: 256)
    let lowerBound: Double
    let upperBound: Double
    var underflowCount = 0
    var overflowCount = 0
    var undefinedCount = 0

    mutating func add(_ value: Double) {
        if value < lowerBound { underflowCount += 1 }
        else if value > upperBound { overflowCount += 1 }
        else {
            let index = min(bins.count - 1, Int((value - lowerBound) / (upperBound - lowerBound) * Double(bins.count)))
            bins[index] += 1
        }
    }
}

struct HistogramStats: Codable {
    let originalWidth: Int
    let originalHeight: Int
    let sampledWidth: Int
    let sampledHeight: Int
    let sampledPixelCount: Int
    let hdrPixelCount: Int
    let hsvPixelCount: Int
    let transparentHDRCount: Int
    let transparentSDRCount: Int
    let invalidHDRCount: Int
    let hdrDomain: String
    let hsvDomain: String
    let channels: [String: HistogramDistribution]
}

extension ImageEngine {
    /// RGB/Y 统计编码前 HDR 工作图；HSV 统计源图的 8 位 sRGB SDR 表观。
    func histogram(_ image: LoadedImage, peak: Double, maxDimension: Int = 512) throws -> HistogramStats {
        guard (1...2048).contains(maxDimension) else { throw ImageFailure.invalidOptions }
        let working = try outputImage(image, peak: peak)
        let limit = CGFloat(maxDimension)
        let needsResize = max(working.extent.width, working.extent.height) > limit
        let options = ExportOptions(
            width: needsResize && working.extent.width >= working.extent.height ? maxDimension : nil,
            height: needsResize && working.extent.height > working.extent.width ? maxDimension : nil)
        let hdr = try resized(working, options: options)
        let sdr = try resized(image.sdr, options: options)
        let width = Int(hdr.extent.width)
        let height = Int(hdr.extent.height)
        guard width == Int(sdr.extent.width), height == Int(sdr.extent.height) else { throw ImageFailure.invalidImage }
        let count = width * height
        var linear = [Float](repeating: 0, count: count * 4)
        var encoded = [UInt8](repeating: 0, count: count * 4)
        linear.withUnsafeMutableBytes {
            context.render(hdr, toBitmap: $0.baseAddress!, rowBytes: width * 16,
                           bounds: hdr.extent, format: .RGBAf, colorSpace: linearSpace)
        }
        encoded.withUnsafeMutableBytes {
            context.render(sdr, toBitmap: $0.baseAddress!, rowBytes: width * 4,
                           bounds: sdr.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }
        let ceiling = Double(try contentHeadroom(of: working))
        var red = HistogramDistribution(lowerBound: 0, upperBound: ceiling)
        var green = red
        var blue = red
        var luminance = HistogramDistribution(lowerBound: 0, upperBound: ceiling * 203)
        var hue = HistogramDistribution(lowerBound: 0, upperBound: 360)
        var saturation = HistogramDistribution(lowerBound: 0, upperBound: 1)
        var value = saturation
        var hdrCount = 0
        var hsvCount = 0
        var transparentHDR = 0
        var transparentSDR = 0
        var invalidHDR = 0
        for pixel in 0..<count {
            if (pixel & 4095) == 0 { try Task.checkCancellation() }
            let index = pixel * 4
            let alpha = Double(linear[index + 3])
            if !alpha.isFinite || alpha < 0 { invalidHDR += 1 }
            else if alpha == 0 { transparentHDR += 1 }
            else {
                // 还原直通颜色后计数，透明像素不把黑底当作原图颜色。
                let r = Double(linear[index]) / alpha
                let g = Double(linear[index + 1]) / alpha
                let b = Double(linear[index + 2]) / alpha
                if r.isFinite && g.isFinite && b.isFinite {
                    red.add(r)
                    green.add(g)
                    blue.add(b)
                    luminance.add((0.2627002120112671 * r + 0.6779980715188708 * g + 0.059301716469862 * b) * 203)
                    hdrCount += 1
                } else { invalidHDR += 1 }
            }
            let sdrAlpha = Double(encoded[index + 3])
            if sdrAlpha == 0 { transparentSDR += 1; continue }
            let r = min(1, Double(encoded[index]) / sdrAlpha)
            let g = min(1, Double(encoded[index + 1]) / sdrAlpha)
            let b = min(1, Double(encoded[index + 2]) / sdrAlpha)
            let maximum = max(r, g, b)
            let minimum = min(r, g, b)
            let delta = maximum - minimum
            value.add(maximum)
            saturation.add(maximum > 0 ? delta / maximum : 0)
            if delta == 0 { hue.undefinedCount += 1 }
            else {
                var degrees: Double
                if maximum == r { degrees = (g - b) / delta * 60 }
                else if maximum == g { degrees = ((b - r) / delta + 2) * 60 }
                else { degrees = ((r - g) / delta + 4) * 60 }
                if degrees < 0 { degrees += 360 }
                hue.add(degrees)
            }
            hsvCount += 1
        }
        return HistogramStats(originalWidth: Int(working.extent.width), originalHeight: Int(working.extent.height),
            sampledWidth: width, sampledHeight: height, sampledPixelCount: count,
            hdrPixelCount: hdrCount, hsvPixelCount: hsvCount, transparentHDRCount: transparentHDR,
            transparentSDRCount: transparentSDR, invalidHDRCount: invalidHDR,
            hdrDomain: "编码前 HDR 工作图；线性 BT.2020；RGB 1 = 203 nit，Y 使用 nit",
            hsvDomain: "源图 SDR 表观；8 位 sRGB 编码 RGB；H 使用角度，S/V 使用 0…1",
            channels: ["R": red, "G": green, "B": blue, "Y": luminance,
                       "H": hue, "S": saturation, "V": value])
    }
}
