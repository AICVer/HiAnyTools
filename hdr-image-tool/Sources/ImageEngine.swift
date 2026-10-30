import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum ImageFailure: LocalizedError {
    case invalidImage, multipleFrames, imageTooLarge, missingGainMap, renderFailed
    case invalidPeak, invalidExport, unsupportedFormat, invalidOptions, targetSizeUnreachable
    case invalidGain, unsupportedColorSpace, noHDRHeadroom

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法读取该图像，请选择原始静态图像文件。"
        case .multipleFrames: return "首版只处理单张静态图像。"
        case .imageTooLarge: return "首版支持最多 5000 万像素的单张图像。"
        case .missingGainMap: return "此文件没有系统可读取的 GainMap。"
        case .renderFailed: return "图像渲染失败。"
        case .invalidPeak: return "输出峰值须在 203～600 nit 之间。"
        case .invalidExport: return "导出文件回读校验失败，未生成可分享结果。"
        case .unsupportedFormat: return "当前系统没有此格式的图像编码器。"
        case .invalidOptions: return "导出参数无效：质量 0～1，DPI 1～2400，宽或高择一填写正整数，目标字节数须大于零。"
        case .targetSizeUnreachable: return "在指定像素尺寸和格式下无法达到目标文件大小。请提高文件上限或手动缩小尺寸。"
        case .invalidGain: return "最大增益须为 1～16 倍。"
        case .unsupportedColorSpace: return "该格式或源图无法可靠保留所选色彩空间，请改用 PNG、JPEG 或其他色彩空间。"
        case .noHDRHeadroom: return "当前结果未超过 SDR 参考白，系统不会写出 HDR GainMap。请提高增益，或导出普通 SDR / PQ 文件。"
        }
    }
}

enum ImageMode: String, CaseIterable {
    case hdr = "HDR", sdr = "SDR", gainMap = "GainMap"
}

enum ExportFormat: String, CaseIterable {
    case png = "PNG", tiff = "TIFF", gainMapJPEG = "GainMap JPEG", gainMapHEIC = "GainMap HEIC"
    var fileExtension: String { type.preferredFilenameExtension! }
    var isGainMap: Bool { self == .gainMapJPEG || self == .gainMapHEIC }
    var type: UTType {
        switch self {
        case .png: return .png
        case .tiff: return .tiff
        case .gainMapJPEG: return .jpeg
        case .gainMapHEIC: return .heic
        }
    }
}

enum SDRFormat: String, CaseIterable {
    case jpeg = "JPEG", heic = "HEIC", png = "PNG", bmp = "BMP"

    var type: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .png: return .png
        case .bmp: return .bmp
        }
    }

    var fileExtension: String { type.preferredFilenameExtension! }
    var keepsAlpha: Bool { self == .png }

    static var supported: [SDRFormat] {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as! [String]
        return allCases.filter { identifiers.contains($0.type.identifier) }
    }
}

struct LoadedImage {
    let hdr: CIImage
    let sdr: CIImage
    let gainMap: CIImage?
    let isHDR: Bool
    let typeName: String
    let name: String
    var sdrColorSpace: CGColorSpace? = nil
    var size: CGSize { hdr.extent.size }
    var formatName: String { UTType(typeName)?.preferredFilenameExtension?.uppercased() ?? typeName }
    var dynamicRangeLabel: String {
        if gainMap != nil { return "GainMap HDR" }
        guard isHDR else { return "SDR" }
        let space = hdr.colorSpace?.name as String? ?? ""
        if space.contains("PQ") { return "PQ HDR" }
        if space.contains("HLG") { return "HLG HDR" }
        return "HDR"
    }
}

/// 本地共享图像引擎；iOS 界面与 macOS 数值测试调用同一实现。
final class ImageEngine {
    let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
    let pqSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)!
    let context: CIContext

    init() {
        context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!,
            .workingFormat: CIFormat.RGBAf,
            .cacheIntermediates: false
        ])
    }

    /// 从文件内容识别编码，方向在读取时应用；不经 8 位 SDR 中间图。
    func load(_ url: URL) throws -> LoadedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ImageFailure.invalidImage }
        // URL 解码缓存与读取属性都可能触发 GainMap 的内部 HEIF 表示。
        // 用独立增量源只识别文件头，避免复制整份大图或依赖扩展名。
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let header = try file.read(upToCount: 65_536) ?? Data()
        let headerSource = CGImageSourceCreateIncremental(nil)
        CGImageSourceUpdateData(headerSource, header as CFData, false)
        guard let detected = CGImageSourceGetType(headerSource) else { throw ImageFailure.invalidImage }
        let originalType = detected as String
        let primarySpace = CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCache: false] as CFDictionary)?.colorSpace
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0 else { throw ImageFailure.invalidImage }
        guard CGImageSourceGetCount(source) == 1 else { throw ImageFailure.multipleFrames }
        guard Double(width) * Double(height) <= 50_000_000 else { throw ImageFailure.imageTooLarge }
        let hasGainMap = [kCGImageAuxiliaryDataTypeISOGainMap, kCGImageAuxiliaryDataTypeHDRGainMap]
            .contains { CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, $0) != nil }
        let baseOptions: [CIImageOption: Any] = [.applyOrientationProperty: true]
        guard let hdr = CIImage(contentsOf: url, options: baseOptions.merging([
            .expandToHDR: true, .toneMapHDRtoSDR: false
        ], uniquingKeysWith: { _, new in new })),
              let systemSDR = CIImage(contentsOf: url, options: baseOptions.merging([
                .expandToHDR: false, .toneMapHDRtoSDR: true
              ], uniquingKeysWith: { _, new in new })) else { throw ImageFailure.invalidImage }
        var sdr = systemSDR
        if hasGainMap && originalType == UTType.jpeg.identifier,
           let base = CIImage(contentsOf: url, options: [
               .expandToHDR: false, .toneMapHDRtoSDR: false, .applyOrientationProperty: false
           ]), base.contentHeadroom <= 1, base.colorSpace?.isHDR() != true {
            // Native GainMap 适配会改变 SDR primary 的解读；HDR-primary 仍由系统映射。
            let primary = try JPEGPrimary.sdrData(at: url)
            guard let decoded = CIImage(data: primary, options: [
                .toneMapHDRtoSDR: false, .applyOrientationProperty: false
            ]) else { throw ImageFailure.invalidImage }
            let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
            sdr = decoded.oriented(forExifOrientation: Int32(orientation))
        }
        let gainMap = hasGainMap ? CIImage(contentsOf: url, options: [
            .auxiliaryHDRGainMap: true, .applyOrientationProperty: true
        ]) : nil
        let isHDR = hasGainMap || hdr.contentHeadroom > 1 || hdr.colorSpace?.isHDR() == true
        return LoadedImage(hdr: hdr, sdr: sdr, gainMap: gainMap, isHDR: isHDR,
                           typeName: originalType,
                           name: url.deletingPathExtension().lastPathComponent,
                           sdrColorSpace: (sdr.colorSpace ?? primarySpace).map { CGColorSpaceCreateCopyWithStandardRange($0) })
    }

    /// 在线性 BT.2020 中保持暗部、中间调，仅向高光逐渐施加等比例 RGB 增益。
    func enhance(_ image: CIImage, peak: Double) throws -> CIImage {
        guard peak.isFinite, (203...600).contains(peak) else { throw ImageFailure.invalidPeak }
        if peak == 203 { return image }
        // 同乘 RGB 增益保持线性色度；0.5 是首版亮区起点，不作物体语义识别。
        let source = """
        kernel vec4 highlights(__sample p, float peakRatio) {
            vec4 c = unpremultiply(p);
            float y = dot(c.rgb, vec3(0.2627, 0.6780, 0.0593));
            float t = smoothstep(0.5, 1.0, y);
            c.rgb *= 1.0 + (peakRatio - 1.0) * t;
            return premultiply(c);
        }
        """
        guard let kernel = CIColorKernel(source: source),
              let result = kernel.apply(extent: image.extent, arguments: [image, peak / 203])
        else { throw ImageFailure.renderFailed }
        return result
    }

    /// GPU 归约实际线性分量峰值，避免把文件默认余量误当成实际像素峰值。
    func contentHeadroom(of image: CIImage) throws -> Float {
        let values = try reducedValues(image.unpremultiplyingAlpha(), filter: "CIAreaMaximum")
        return max(1, values[0], values[1], values[2])
    }

    /// CTA 单帧光级：像素 maxRGB 的最大值与平均值，线性 1.0 对应 203 nit。
    func lightLevels(of image: CIImage, linearColorSpace: CGColorSpace? = nil) throws -> HDRLightLevels {
        let straight = image.unpremultiplyingAlpha()
        let outputContext = linearColorSpace.map { CIContext(options: [
            .workingColorSpace: $0, .workingFormat: CIFormat.RGBAf, .cacheIntermediates: false
        ]) }
        let maximum = try reducedValues(straight, filter: "CIAreaMaximum", renderingContext: outputContext, space: linearColorSpace)
        let average = try reducedValues(straight.applyingFilter("CIMaximumComponent"), filter: "CIAreaAverage",
                                        renderingContext: outputContext, space: linearColorSpace)
        return HDRLightLevels(maxCLL: Double(max(0, maximum[0], maximum[1], maximum[2])) * 203,
                              maxFALL: Double(max(0, average[0])) * 203)
    }

    private func reducedValues(_ image: CIImage, filter: String, renderingContext: CIContext? = nil,
                               space: CGColorSpace? = nil) throws -> [Float] {
        let reduced = image.applyingFilter(filter, parameters: ["inputExtent": CIVector(cgRect: image.extent)])
        var values = [Float](repeating: 0, count: 4)
        values.withUnsafeMutableBytes { buffer in
            (renderingContext ?? context).render(reduced, toBitmap: buffer.baseAddress!, rowBytes: 16,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: space ?? linearSpace)
        }
        guard values.allSatisfy({ $0.isFinite }) else { throw ImageFailure.renderFailed }
        return values
    }

    /// 获取处理后的 HDR；已有 HDR 内容保留原动态范围。
    func outputImage(_ image: LoadedImage, peak: Double) throws -> CIImage {
        guard peak.isFinite, (203...600).contains(peak) else { throw ImageFailure.invalidPeak }
        return image.isHDR ? image.hdr : try enhance(image.hdr, peak: peak)
    }

    /// 仅缩小预览，不影响输出原始像素尺寸。
    func preview(_ image: LoadedImage, mode: ImageMode, peak: Double) throws -> CGImage {
        let selected: CIImage
        switch mode {
        case .hdr: selected = try outputImage(image, peak: peak)
        case .sdr: selected = image.sdr
        case .gainMap:
            guard let gainMap = image.gainMap else { throw ImageFailure.missingGainMap }
            selected = gainMap
        }
        let scale = min(1, 2048 / max(selected.extent.width, selected.extent.height))
        let small = selected.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let space = mode == .hdr ? linearSpace : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let result = context.createCGImage(small, from: small.extent,
            format: mode == .hdr ? .RGBAh : .RGBA8, colorSpace: space)
        else { throw ImageFailure.renderFailed }
        if mode == .hdr {
            // 未标记 headroom 的浮点 CGImage 会被系统排除在色调映射之外。
            let headroom = try contentHeadroom(of: selected)
            guard let tagged = CGImageCreateCopyWithContentHeadroom(headroom, result)
            else { throw ImageFailure.renderFailed }
            return tagged
        }
        return result
    }

    /// 写出 16 位 BT.2020/PQ；回读通过后才返回目标 URL。
    func export(_ image: LoadedImage, peak: Double, format: ExportFormat, directory: URL,
                options: ExportOptions = ExportOptions()) throws -> URL {
        if format.isGainMap {
            return try exportGainMap(image, peak: peak, format: format, directory: directory, options: options)
        }
        let pqSpace = options.hdrColorSpace.pq
        let result = try resized(outputImage(image, peak: peak), options: options)
        guard let pixels = context.createCGImage(result, from: result.extent,
            format: .RGBA16, colorSpace: pqSpace) else { throw ImageFailure.renderFailed }
        // 对最终量化后的 PQ 像素求余量，元数据不因源文件默认值而低估高光。
        let levels = try lightLevels(of: CIImage(cgImage: pixels), linearColorSpace: options.hdrColorSpace.linear)
        let headroom = Float(max(1, levels.maxCLL / 203))
        guard let rendered = CGImageCreateCopyWithContentHeadroom(headroom, pixels)
        else { throw ImageFailure.renderFailed }
        var data = try encodeToBudget(rendered, type: format.type, options: options, lossy: false)
        if format == .png { data = try HDRPNG.addingLightLevels(to: data, levels: levels) }
        if let target = options.targetBytes, data.count > target { throw ImageFailure.targetSizeUnreachable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("HDR-\(UUID().uuidString).\(format.fileExtension)")
        do {
            try data.write(to: url, options: .atomic)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  decoded.width == Int(result.extent.width),
                  decoded.height == Int(result.extent.height),
                  decoded.bitsPerComponent == 16,
                  decoded.colorSpace?.name == pqSpace.name
            else { throw ImageFailure.invalidExport }
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// 将源图的 SDR 表观转换为普通格式；PNG 保留透明，其他格式铺白底。
    func exportSDR(_ image: LoadedImage, format: SDRFormat, directory: URL,
                   options: ExportOptions = ExportOptions()) throws -> URL {
        guard SDRFormat.supported.contains(format) else { throw ImageFailure.unsupportedFormat }
        guard format != .bmp || options.sdrColorSpace == .sRGB else { throw ImageFailure.unsupportedColorSpace }
        let prepared = try sdrForExport(image, options: options)
        let base = try resized(prepared, options: options)
        let source = format.keepsAlpha ? base : base.composited(over:
            CIImage(color: .white).cropped(to: base.extent))
        guard let rendered = context.createCGImage(source, from: source.extent, format: .RGBA8,
            colorSpace: options.sdrColorSpace.space) else { throw ImageFailure.renderFailed }
        let data = try encodeToBudget(rendered, type: format.type, options: options,
                                      lossy: format == .jpeg || format == .heic)
        if let target = options.targetBytes, data.count > target { throw ImageFailure.targetSizeUnreachable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("SDR-\(UUID().uuidString).\(format.fileExtension)")
        do {
            try data.write(to: url, options: .atomic)
            guard let output = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let decoded = CGImageSourceCreateImageAtIndex(output, 0, nil),
                  decoded.width == rendered.width, decoded.height == rendered.height,
                  decoded.bitsPerComponent == 8,
                  CGImageSourceGetType(output) as String? == format.type.identifier
            else { throw ImageFailure.invalidExport }
            guard matchingColorSpace(decoded.colorSpace, options.sdrColorSpace.space) else {
                throw ImageFailure.unsupportedColorSpace
            }
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func resized(_ image: CIImage, options: ExportOptions) throws -> CIImage {
        let size = try options.outputSize(for: image.extent.size)
        guard size != image.extent.size else { return image }
        let normalized = image.transformed(by: CGAffineTransform(
            translationX: -image.extent.minX, y: -image.extent.minY))
        return normalized.transformed(by: CGAffineTransform(
            scaleX: size.width / image.extent.width, y: size.height / image.extent.height))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    /// 文件体积包含元数据；只调整有损编码质量，不暗中改变像素尺寸。
    private func encodeToBudget(_ image: CGImage, type: UTType, options: ExportOptions,
                                lossy: Bool) throws -> Data {
        func encode(_ quality: Double) throws -> Data {
            let buffer = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(buffer,
                type.identifier as CFString, 1, nil) else { throw ImageFailure.unsupportedFormat }
            var properties: [CFString: Any] = [:]
            if lossy { properties[kCGImageDestinationLossyCompressionQuality] = quality }
            if let dpi = options.dpi {
                properties[kCGImagePropertyDPIWidth] = dpi
                properties[kCGImagePropertyDPIHeight] = dpi
            }
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw ImageFailure.invalidExport }
            return buffer as Data
        }
        let initial = try encode(options.quality)
        guard let target = options.targetBytes, initial.count > target else { return initial }
        guard lossy else { throw ImageFailure.targetSizeUnreachable }
        var best = try encode(0)
        guard best.count <= target else { throw ImageFailure.targetSizeUnreachable }
        var low = 0.0
        var high = options.quality
        for _ in 0..<9 {
            let quality = (low + high) / 2
            let candidate = try encode(quality)
            if candidate.count <= target {
                best = candidate
                low = quality
            } else { high = quality }
        }
        return best
    }
}
