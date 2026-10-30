import Foundation
import CoreImage
import ImageIO

extension ImageEngine {
    /// 在线性 BT.2020 中取 Y；方向已在 load 应用，另一张图按比例放大并居中裁切。
    func compose(_ base: LoadedImage, graySource: LoadedImage?, maximumGain: Double) throws -> LoadedImage {
        guard maximumGain.isFinite, (1...16).contains(maximumGain) else { throw ImageFailure.invalidGain }
        let source = (graySource ?? base).sdr
        let target = base.sdr.extent
        let scale = max(target.width / source.extent.width, target.height / source.extent.height)
        let aligned = source.transformed(by: CGAffineTransform(
            translationX: -source.extent.minX, y: -source.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(
                translationX: target.midX - source.extent.width * scale / 2,
                y: target.midY - source.extent.height * scale / 2)).cropped(to: target)
        let grayCode = """
        kernel vec4 grayMap(__sample p) {
            vec4 c = unpremultiply(p);
            float y = clamp(dot(c.rgb, vec3(0.2627, 0.6780, 0.0593)), 0.0, 1.0) * c.a;
            return vec4(y, y, y, 1.0);
        }
        """
        let gainCode = """
        kernel vec4 applyGrayGain(__sample base, __sample gray, float gain) {
            vec4 c = unpremultiply(base);
            c.rgb *= pow(gain, clamp(gray.r, 0.0, 1.0));
            return premultiply(c);
        }
        """
        guard let grayKernel = CIColorKernel(source: grayCode),
              let gainKernel = CIColorKernel(source: gainCode),
              let gray = grayKernel.apply(extent: target, arguments: [aligned]),
              let hdr = gainKernel.apply(extent: target, arguments: [base.sdr, gray, maximumGain])
        else { throw ImageFailure.renderFailed }
        return LoadedImage(hdr: hdr, sdr: base.sdr, gainMap: gray, isHDR: true,
                           typeName: base.typeName, name: base.name, sdrColorSpace: base.sdrColorSpace)
    }

    /// 等 XYZ 使用系统色彩转换；直通先在源 SDR 空间取码值，再赋予目标空间解释。
    func sdrForExport(_ image: LoadedImage, options: ExportOptions) throws -> CIImage {
        guard options.sdrMapping == .rgb else { return image.sdr }
        guard let space = image.sdrColorSpace ?? image.sdr.colorSpace,
              space.model == .rgb, !space.isHDR(),
              let encoded = context.createCGImage(image.sdr, from: image.sdr.extent,
                  format: .RGBA8, colorSpace: space),
              let retagged = encoded.copy(colorSpace: options.sdrColorSpace.space)
        else { throw ImageFailure.unsupportedColorSpace }
        return CIImage(cgImage: retagged)
    }

    /// 由 SDR/HDR 双表观交给系统生成 ISO GainMap，回读确认辅助图存在。
    func exportGainMap(_ image: LoadedImage, peak: Double, format: ExportFormat,
                       directory: URL, options: ExportOptions) throws -> URL {
        guard format.isGainMap else { throw ImageFailure.unsupportedFormat }
        let hdr = try resized(outputImage(image, peak: peak), options: options)
        let sdr = try resized(image.sdr, options: options)
        let white = CIImage(color: .white).cropped(to: hdr.extent)
        let opaqueHDR = hdr.composited(over: white)
        let opaqueSDR = sdr.composited(over: white)
        let headroom = max(1, try lightLevels(of: opaqueHDR,
                                             linearColorSpace: options.hdrColorSpace.linear).maxCLL / 203)
        guard headroom > 1.00001 else { throw ImageFailure.noHDRHeadroom }
        guard let pixels = context.createCGImage(opaqueHDR, from: hdr.extent, format: .RGBAh,
                                                colorSpace: options.hdrColorSpace.linear),
              let tagged = CGImageCreateCopyWithContentHeadroom(Float(headroom), pixels)
        else { throw ImageFailure.renderFailed }
        let hdrInput = CIImage(cgImage: tagged)
        var props: [String: Any] = [:]
        if let dpi = options.dpi {
            props[kCGImagePropertyDPIWidth as String] = dpi
            props[kCGImagePropertyDPIHeight as String] = dpi
        }
        let base = opaqueSDR.settingProperties(props)
        func encode(_ quality: Double) throws -> Data {
            let settings: [CIImageRepresentationOption: Any] = [
                .hdrImage: hdrInput, .hdrGainMapAsRGB: true,
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality
            ]
            let data = format == .gainMapJPEG
                ? context.jpegRepresentation(of: base, colorSpace: options.hdrColorSpace.sdr, options: settings)
                : context.heifRepresentation(of: base, format: .RGBA8,
                                             colorSpace: options.hdrColorSpace.sdr, options: settings)
            guard let data else { throw ImageFailure.unsupportedFormat }
            return data
        }
        var data = try encode(options.quality)
        if let target = options.targetBytes, data.count > target {
            data = try encode(0)
            guard data.count <= target else { throw ImageFailure.targetSizeUnreachable }
            var low = 0.0
            var high = options.quality
            for _ in 0..<9 {
                let quality = (low + high) / 2
                let candidate = try encode(quality)
                if candidate.count <= target { data = candidate; low = quality }
                else { high = quality }
            }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("HDR-\(UUID().uuidString).\(format.fileExtension)")
        do {
            try data.write(to: url, options: .atomic)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil,
                  let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  decoded.width == Int(hdr.extent.width), decoded.height == Int(hdr.extent.height),
                  decoded.colorSpace?.name == options.hdrColorSpace.sdr.name
            else { throw ImageFailure.invalidExport }
            let loaded = try load(url)
            guard loaded.gainMap != nil, loaded.size == hdr.extent.size else { throw ImageFailure.invalidExport }
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}
