import Foundation
import CoreImage

enum GamutVolumeSpace: String, CaseIterable, Codable {
    case cam16 = "CAM16-UCS", ictcp = "ICtCp", lab = "CIELab"
    var axes: [String] {
        switch self {
        case .cam16: return ["a′", "J′", "−b′"]
        case .ictcp: return ["Cp", "I", "Ct"]
        case .lab: return ["a*", "L*", "−b*"]
        }
    }
}

struct ColorPoint: Codable {
    let xy: [Double]?
    let uv: [Double]?
    let lab: [Double]
    let cam16: [Double]?
    let ictcp: [Double]?
    let displayRGB: [Double]

    func scene(_ space: GamutVolumeSpace) -> [Double]? {
        switch space {
        case .lab: return [lab[1], lab[0], -lab[2]]
        case .cam16: return cam16.map { [$0[1], $0[0], -$0[2]] }
        case .ictcp: return ictcp.map { [$0[2], $0[0], $0[1]] }
        }
    }
}

struct PixelDistribution: Codable {
    let originalWidth: Int
    let originalHeight: Int
    let width: Int
    let height: Int
    let transparentCount: Int
    let invalidCount: Int
    let negativeClampedCount: Int
    let points: [ColorPoint]
}

struct PixelComparison {
    let original: PixelDistribution
    let enhanced: PixelDistribution?
}

/// iOS 无 colour-science 运行时；公式以本机 colour-science 独立数值验收。
enum PixelColorMath {
    static let white = [0.9504559270516716, 1.0, 1.0890577507598784]
    static let rgbToXYZ = [[0.6369580483012914, 0.1446169035862083, 0.1688809751641721],
                           [0.2627002120112671, 0.6779980715188708, 0.0593017164698620],
                           [0.0, 0.0280726930490874, 1.060985057710791]]
    static let cat16 = [[0.401288, 0.650173, -0.051461],
                        [-0.250268, 1.204414, 0.045854], [-0.002079, 0.048952, 0.953127]]
    static func multiply(_ matrix: [[Double]], _ vector: [Double]) -> [Double] {
        matrix.map { row in zip(row, vector).reduce(0) { $0 + $1.0 * $1.1 } }
    }

    static func point(rgb: [Double], displayRGB: [Double]) -> ColorPoint {
        let xyz = multiply(rgbToXYZ, rgb)
        let sum = xyz.reduce(0, +)
        let denominator = xyz[0] + 15 * xyz[1] + 3 * xyz[2]
        let xy = sum > 1e-12 ? [xyz[0] / sum, xyz[1] / sum] : nil
        let uv = denominator > 1e-12 ? [4 * xyz[0] / denominator, 9 * xyz[1] / denominator] : nil
        let f = zip(xyz, white).map { value, reference -> Double in
            let t = value / reference
            return t > pow(6.0 / 29, 3) ? cbrt(t) : t / (3 * pow(6.0 / 29, 2)) + 4.0 / 29
        }
        let lab = [116 * f[1] - 16, 500 * (f[0] - f[1]), 200 * (f[1] - f[2])]
        let lms = multiply([[1688.0/4096, 2146.0/4096, 262.0/4096],
                            [683.0/4096, 2951.0/4096, 462.0/4096],
                            [99.0/4096, 309.0/4096, 3688.0/4096]], rgb.map { $0 * 203 })
        var ictcp: [Double]?
        // 原色矩阵浮点误差不应在10000nit白点产生外壳缺口；只容忍数值舍入量。
        if lms.allSatisfy({ $0 >= -1e-8 && $0 <= 10000 + 1e-8 }) {
            let pq = lms.map { value -> Double in
                let y = pow(min(10000, max(0, value)) / 10000, 2610.0/16384)
                return pow((3424.0/4096 + 2413.0/128*y) / (1 + 2392.0/128*y), 2523.0/32)
            }
            ictcp = multiply([[0.5,0.5,0], [6610.0/4096,-13613.0/4096,7003.0/4096],
                              [17933.0/4096,-17390.0/4096,-543.0/4096]], pq)
        }
        return ColorPoint(xy: xy, uv: uv, lab: lab, cam16: cam16(xyz), ictcp: ictcp, displayRGB: displayRGB)
    }

    /// 与 HiGamut 相同固定观察条件：D65，LA=100，Yb=20，平均环绕，完全适应。
    static func cam16(_ xyz: [Double]) -> [Double]? {
        let k = 1.0 / 501
        let fl = 0.2 * pow(k, 4) * 500 + 0.1 * pow(1-pow(k, 4), 2) * cbrt(500)
        let n = 0.2
        let nbb = 0.725 * pow(1/n, 0.2)
        let z = 1.48 + sqrt(n)
        let rgbWhite = multiply(cat16, white.map { $0 * 100 })
        func response(_ value: Double) -> Double {
            let p = pow(abs(fl * value / 100), 0.42)
            return (value < 0 ? -400 : 400) * p / (p + 27.13) + 0.1
        }
        let w = response(100)
        let aw = (3.05 * w - 0.305) * nbb
        let rgb = zip(multiply(cat16, xyz.map { $0 * 100 }), rgbWhite).map { response($0 * 100 / $1) }
        let a = rgb[0] - 12 * rgb[1] / 11 + rgb[2] / 11
        let b = (rgb[0] + rgb[1] - 2 * rgb[2]) / 9
        let h = atan2(b, a)
        let achromatic = (2*rgb[0] + rgb[1] + rgb[2]/20 - 0.305) * nbb
        guard achromatic >= -1e-10 else { return nil }
        let j = 100 * pow(max(0, achromatic) / aw, 0.69 * z)
        let t = (50000.0/13) * nbb * (cos(h+2)+3.8) / 4 * hypot(a,b)
            / (rgb[0] + rgb[1] + 1.05*rgb[2])
        let c = pow(max(0,t),0.9) * sqrt(j/100) * pow(1.64-pow(0.29,n),0.73)
        let m = log1p(0.0228 * c * pow(fl,0.25)) / 0.0228
        let result = [1.7*j/(1+0.007*j), m*cos(h), m*sin(h)]
        return result.allSatisfy(\.isFinite) ? result : nil
    }
}

extension ImageEngine {
    /// 64长边采样当前HDR工作图，位置不经SDR裁切；点颜色仅用SDR表观辅助辨识。
    func distribution(_ image: LoadedImage, peak: Double, maxDimension: Int = 64,
                      highQualityDownsample: Bool? = nil) throws -> PixelDistribution {
        guard (1...128).contains(maxDimension) else { throw ImageFailure.invalidOptions }
        let hdr = try outputImage(image, peak: peak)
        let scale = min(1, Double(maxDimension) / max(hdr.extent.width, hdr.extent.height))
        let width = max(1, Int(floor(hdr.extent.width * scale)))
        let height = max(1, Int(floor(hdr.extent.height * scale)))
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        func samples(_ source: CIImage, space: CGColorSpace) -> [Float] {
            let normalized = source.transformed(by: CGAffineTransform(
                translationX: -source.extent.minX, y: -source.extent.minY))
            let transform = CGAffineTransform(
                scaleX: Double(width) / source.extent.width, y: Double(height) / source.extent.height)
            let small = highQualityDownsample.map {
                normalized.transformed(by: transform, highQualityDownsample: $0)
            } ?? normalized.transformed(by: transform)
            var values = [Float](repeating: 0, count: width * height * 4)
            values.withUnsafeMutableBytes {
                context.render(small, toBitmap: $0.baseAddress!, rowBytes: width * 16,
                               bounds: bounds, format: .RGBAf, colorSpace: space)
            }
            return values
        }
        var values = samples(hdr, space: linearSpace)
        let originalSpace = image.hdr.colorSpace ?? image.sdrColorSpace ?? linearSpace
        let sourceLinearSpace: CGColorSpace
        if originalSpace.model == .rgb {
            guard let linearized = CGColorSpaceCreateExtendedLinearized(originalSpace)
            else { throw ImageFailure.unsupportedColorSpace }
            sourceLinearSpace = linearized
        } else {
            // 灰度与未标记的计算结果沿用引擎的线性工作域。
            sourceLinearSpace = linearSpace
        }
        var sourceValues = samples(hdr, space: sourceLinearSpace)
        var correctedOffsets: [Int] = []
        for offset in stride(from: 0, to: sourceValues.count, by: 4) {
            try Task.checkCancellation()
            guard sourceValues[offset+3] > 0,
                  sourceValues[offset..<offset+4].allSatisfy(\.isFinite),
                  sourceValues[offset..<offset+3].contains(where: { $0 < 0 }) else { continue }
            correctedOffsets.append(offset)
            for channel in 0..<3 { sourceValues[offset+channel] = max(0, sourceValues[offset+channel]) }
        }
        if !correctedOffsets.isEmpty {
            // 只修正分析副本：源线性RGB截断后再做色彩转换；P3的合法负BT.2020分量不能裁零。
            let data = sourceValues.withUnsafeBufferPointer { Data(buffer: $0) }
            let corrected = CIImage(bitmapData: data, bytesPerRow: width * 16,
                size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: sourceLinearSpace)
            var converted = [Float](repeating: 0, count: values.count)
            converted.withUnsafeMutableBytes {
                context.render(corrected, toBitmap: $0.baseAddress!, rowBytes: width * 16,
                    bounds: bounds, format: .RGBAf, colorSpace: linearSpace)
            }
            // 未修正的点保留原渲染值，避免额外往返转换改变其数值。
            for offset in correctedOffsets {
                values.replaceSubrange(offset..<offset+3, with: converted[offset..<offset+3])
            }
        }
        let colors = samples(image.sdr, space: CGColorSpace(name: CGColorSpace.sRGB)!)
        var points: [ColorPoint] = []
        var transparent = 0
        var invalid = 0
        for offset in stride(from: 0, to: values.count, by: 4) {
            try Task.checkCancellation()
            let alpha = Double(values[offset+3])
            guard alpha.isFinite, values[offset..<offset+3].allSatisfy(\.isFinite) else { invalid += 1; continue }
            guard alpha > 0 else { transparent += 1; continue }
            let rgb = (0..<3).map { Double(values[offset+$0]) / alpha }
            let displayAlpha = max(1e-6, Double(colors[offset+3]))
            let display = (0..<3).map { min(1, max(0, Double(colors[offset+$0]) / displayAlpha)) }
            points.append(PixelColorMath.point(rgb: rgb, displayRGB: display))
        }
        return PixelDistribution(originalWidth: Int(image.size.width), originalHeight: Int(image.size.height),
            width: width, height: height, transparentCount: transparent, invalidCount: invalid,
            negativeClampedCount: correctedOffsets.count, points: points)
    }
}
