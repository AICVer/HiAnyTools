import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

// pytest 的本地测试入口；直接调用生产 ImageEngine，不另写算法副本。
@main
struct Probe {
    static func main() {
        do {
            let args = CommandLine.arguments
            let engine = ImageEngine()
            var result: [String: Any] = [:]
            switch args[1] {
            case "color-description":
                let spaces: [String: CGColorSpace] = [
                    "srgb": SDRColorSpace.sRGB.space, "p3": SDRColorSpace.displayP3.space,
                    "pq": HDRColorSpace.bt2020.pq, "p3-pq": HDRColorSpace.displayP3.pq,
                    "hlg": CGColorSpace(name: CGColorSpace.itur_2100_HLG)!,
                    "linear": engine.linearSpace,
                    "gray": CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!,
                    "device-rgb": CGColorSpaceCreateDeviceRGB()]
                result["label"] = ImageColorInfo.spaceLabel(spaces[args[2]])
            case "color-info":
                let loaded = try engine.load(URL(fileURLWithPath: args[2]))
                result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded.colorInfo())) as! [String: Any]
                result["rawSDRSpace"] = (loaded.sdrColorSpace ?? loaded.sdr.colorSpace)?.name as String? ?? ""
                result["rawHDRSpace"] = loaded.hdr.colorSpace?.name as String? ?? ""
            case "composed-color-info":
                let loaded = try engine.load(URL(fileURLWithPath: args[2]))
                let composed = try engine.compose(loaded, graySource: nil, maximumGain: 2)
                result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(composed.colorInfo(generatedHDR: true))) as! [String: Any]
            case "pixel-hull":
                let input = try JSONDecoder().decode([[Double]].self, from: Data(args[2].utf8))
                let hull = try PixelHull.mesh(input)
                result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(hull)) as! [String: Any]
            case "pixel-polygon":
                let input = try JSONDecoder().decode([[Double]].self, from: Data(args[2].utf8))
                result["vertices"] = PixelHull.polygon(input)
            case "lut-sample":
                let lut = try CubeLUT.read(URL(fileURLWithPath: args[2]))
                let values = args[3].split(separator: ",").map { Float($0)! }
                let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
                let source = makeImage(values, width: values.count/4, space: srgb)
                let loaded = LoadedImage(hdr: source, sdr: source, gainMap: nil, isHDR: false,
                    typeName: UTType.png.identifier, name: "lut-sample", sdrColorSpace: srgb)
                let processed = try engine.applying(lut, to: loaded)
                result = ["pixels": pixels(processed.hdr, engine: engine, space: engine.linearSpace),
                    "dimension": lut.dimension, "name": lut.name]
            case "lut-distribution", "lut-export":
                let lut = try CubeLUT.read(URL(fileURLWithPath: args[2]))
                let loaded = try engine.load(URL(fileURLWithPath: args[3]))
                let processed = try engine.applying(lut, to: loaded)
                if args[1] == "lut-export" {
                    let options = try JSONDecoder().decode(ExportOptions.self, from: Data(args[4].utf8))
                    let url = try engine.exportSDR(processed, format: .png,
                        directory: URL(fileURLWithPath: args[5]), options: options)
                    result["path"] = url.path
                } else {
                    let value = try engine.distribution(processed, peak: 203)
                    result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
                }
            case "reference-mesh":
                let mesh = try ReferenceGamutMesh.make(gamut: ReferenceGamut(rawValue: args[2])!,
                    peakNits: Double(args[3])!, divisions: args.count > 4 ? Int(args[4])! : 8)
                result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(mesh)) as! [String: Any]
            case "coordinates":
                let rgb = args[2].split(separator: ",").map { Double($0)! }
                let point = PixelColorMath.point(rgb: rgb, displayRGB: [0,0,0])
                result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(point)) as! [String: Any]
            case "distribution":
                let loaded = try engine.load(URL(fileURLWithPath: args[2]))
                let value = try engine.distribution(loaded, peak: Double(args[3])!,
                    maxDimension: args.count > 4 ? Int(args[4])! : 64,
                    highQualityDownsample: args.count > 5 ? Bool(args[5]) : nil)
                result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
            case "distribution-float", "distribution-float-composed":
                let spaces: [String: CGColorSpace] = [
                    "sRGB": CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                    "Display P3": CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!,
                    "BT.2020": engine.linearSpace]
                let space = spaces[args[2]]!
                let values = args[3].split(separator: ",").map { Float($0)! }
                let source = makeImage(values, width: values.count / 4, space: space)
                let loaded = LoadedImage(hdr: source, sdr: source, gainMap: nil, isHDR: true,
                    typeName: UTType.png.identifier, name: "float-analysis", sdrColorSpace: space)
                let before = pixels(source, engine: engine, space: space)
                let target = args[1] == "distribution-float-composed"
                    ? try engine.compose(loaded, graySource: nil, maximumGain: 1) : loaded
                let value = try engine.distribution(target, peak: 203)
                result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
                result["inputBefore"] = before
                result["inputAfter"] = pixels(source, engine: engine, space: space)
            case "compose":
                let base = try engine.load(URL(fileURLWithPath: args[2]))
                let gray = args[3] == "self" ? nil : try engine.load(URL(fileURLWithPath: args[3]))
                let composed = try engine.compose(base, graySource: gray, maximumGain: Double(args[4])!)
                if args.count > 5 {
                    let options = try JSONDecoder().decode(ExportOptions.self, from: Data(args[6].utf8))
                    let url = try engine.export(composed, peak: 203, format: ExportFormat(rawValue: args[5])!,
                        directory: URL(fileURLWithPath: args[7]), options: options)
                    result["path"] = url.path
                } else {
                    result = ["hdr": pixels(composed.hdr, engine: engine, space: engine.linearSpace),
                              "sdr": pixels(composed.sdr, engine: engine, space: engine.linearSpace),
                              "gray": pixels(composed.gainMap!, engine: engine, space: engine.linearSpace),
                              "width": composed.size.width, "height": composed.size.height]
                }
            case "sample":
                let peak = Double(args[2])!
                let values = args[3].split(separator: ",").map { Float($0)! }
                let image = makeImage(values, width: values.count / 4, space: engine.linearSpace)
                let processed = try engine.enhance(image, peak: peak)
                result["pixels"] = pixels(processed, engine: engine, space: engine.linearSpace)
                result["contentHeadroom"] = try engine.contentHeadroom(of: processed)
            case "fixture":
                let url = URL(fileURLWithPath: args[2])
                let image = makeImage([0,0,0,1, 0.18,0.18,0.18,1, 0.5,0.5,0.5,1,
                                       0.75,0.75,0.75,1, 1,1,1,1], width: 5, space: engine.linearSpace)
                try engine.context.writePNGRepresentation(of: image, to: url, format: .RGBA16,
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                result["path"] = url.path
            case "gainmap":
                let url = URL(fileURLWithPath: args[2])
                let sdr = makeImage(Array(repeating: [Float(0.8),0.8,0.8,1], count: 64 * 64).flatMap { $0 },
                                    width: 64, space: engine.linearSpace)
                let hdr = try engine.enhance(sdr, peak: 600)
                try engine.context.writeJPEGRepresentation(of: sdr, to: url,
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [.hdrImage: hdr])
                result["path"] = url.path
            case "hdrfixture":
                let url = URL(fileURLWithPath: args[2])
                let image = makeImage([1,1,1,1, 1000.0/203,1000.0/203,1000.0/203,1],
                                      width: 2, space: engine.linearSpace)
                try engine.context.writePNGRepresentation(of: image, to: url, format: .RGBA16,
                    colorSpace: engine.pqSpace)
                result["path"] = url.path
            case "inspect":
                let url = URL(fileURLWithPath: args[2])
                let image = try engine.load(url)
                let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
                let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
                result = ["width": image.size.width, "height": image.size.height,
                    "isHDR": image.isHDR, "gainMap": image.gainMap != nil,
                    "depth": decoded.bitsPerComponent,
                    "space": decoded.colorSpace?.name as String? ?? "unknown",
                    "linear": pixels(image.hdr, engine: engine, space: engine.linearSpace)]
            case "meta":
                let url = URL(fileURLWithPath: args[2])
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ImageFailure.invalidImage }
                let rawType = CGImageSourceGetType(source).map { $0 as String } ?? "unknown"
                guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
                else { throw ImageFailure.invalidImage }
                let loaded = try engine.load(url)
                let light = try engine.lightLevels(of: loaded.hdr)
                let scale = min(1, 64 / max(loaded.size.width, loaded.size.height))
                let small = loaded.hdr.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    .cropped(to: CGRect(x: 0, y: 0, width: max(1, floor(loaded.size.width * scale)),
                                       height: max(1, floor(loaded.size.height * scale))))
                let sampled = pixels(small, engine: engine, space: engine.linearSpace)
                let rgb = stride(from: 0, to: sampled.count, by: 4).flatMap { Array(sampled[$0..<$0+3]) }
                let ys = stride(from: 0, to: sampled.count, by: 4).map {
                    sampled[$0] * 0.2627 + sampled[$0+1] * 0.6780 + sampled[$0+2] * 0.0593
                }
                result = ["type": loaded.typeName, "rawContainerType": rawType, "count": CGImageSourceGetCount(source),
                    "rawWidth": props[kCGImagePropertyPixelWidth as String] ?? 0,
                    "rawHeight": props[kCGImagePropertyPixelHeight as String] ?? 0,
                    "orientation": props[kCGImagePropertyOrientation as String] ?? 1,
                    "depth": props[kCGImagePropertyDepth as String] ?? 0,
                    "orientedWidth": loaded.size.width, "orientedHeight": loaded.size.height,
                    "colorSpace": loaded.hdr.colorSpace?.name as String? ?? "unknown",
                    "profileName": props[kCGImagePropertyProfileName as String] ?? "unknown",
                    "dpiWidth": props[kCGImagePropertyDPIWidth as String] ?? 0,
                    "dpiHeight": props[kCGImagePropertyDPIHeight as String] ?? 0,
                    "hasAppleGainMap": CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil,
                    "hasISOGainMap": CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil,
                    "contentHeadroom": loaded.hdr.contentHeadroom, "isHDR": loaded.isHDR,
                    "decodedMaxNits": light.maxCLL, "pqUpperLimitNits": 10000,
                    "pqUpperOverflow": light.maxCLL > 10000.1,
                    "maxRGB": rgb.max() ?? 0, "minRGB": rgb.min() ?? 0,
                    "meanY": ys.reduce(0, +) / Float(max(1, ys.count))]
            case "preview":
                let image = try engine.load(URL(fileURLWithPath: args[2]))
                let mode = ImageMode(rawValue: args[3])!
                let preview = try engine.preview(image, mode: mode, peak: 600)
                result = ["width": preview.width, "height": preview.height]
            case "preview-meta":
                let loaded = try engine.load(URL(fileURLWithPath: args[2]))
                let preview = try engine.preview(loaded, mode: ImageMode(rawValue: args[3])!, peak: Double(args[4])!)
                let image = CIImage(cgImage: preview)
                let scale = min(1, 64 / max(image.extent.width, image.extent.height))
                let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    .cropped(to: CGRect(x: 0, y: 0, width: max(1, floor(image.extent.width * scale)),
                                       height: max(1, floor(image.extent.height * scale))))
                let values = pixels(small, engine: engine, space: engine.linearSpace)
                let rgb = stride(from: 0, to: values.count, by: 4).flatMap { Array(values[$0..<$0+3]) }
                let ys = stride(from: 0, to: values.count, by: 4).map {
                    values[$0] * 0.2627 + values[$0+1] * 0.6780 + values[$0+2] * 0.0593
                }
                result = ["width": preview.width, "height": preview.height,
                    "bitsPerComponent": preview.bitsPerComponent,
                    "colorSpace": preview.colorSpace?.name as String? ?? "unknown",
                    "contentHeadroom": preview.contentHeadroom,
                    "maxRGB": rgb.max() ?? 0, "minRGB": rgb.min() ?? 0,
                    "meanY": ys.reduce(0, +) / Float(max(1, ys.count)),
                    "dynamicRangeLabel": loaded.dynamicRangeLabel, "formatName": loaded.formatName]
            case "export":
                let image = try engine.load(URL(fileURLWithPath: args[2]))
                let url = try engine.export(image, peak: Double(args[3])!,
                    format: ExportFormat(rawValue: args[4])!, directory: URL(fileURLWithPath: args[5]))
                result["path"] = url.path
            case "formats":
                result["formats"] = SDRFormat.supported.map { $0.rawValue }
            case "sdr-export":
                let image = try engine.load(URL(fileURLWithPath: args[2]))
                let url = try engine.exportSDR(image, format: SDRFormat(rawValue: args[3])!,
                    directory: URL(fileURLWithPath: args[4]))
                result["path"] = url.path
            case "sdr-options":
                let loaded = try engine.load(URL(fileURLWithPath: args[2]))
                let options = try JSONDecoder().decode(ExportOptions.self, from: Data(args[4].utf8))
                let url = try engine.exportSDR(loaded, format: SDRFormat(rawValue: args[3])!,
                    directory: URL(fileURLWithPath: args[5]), options: options)
                result["path"] = url.path
            case "hdr-options":
                let loaded = try engine.load(URL(fileURLWithPath: args[2]))
                let options = try JSONDecoder().decode(ExportOptions.self, from: Data(args[5].utf8))
                let url = try engine.export(loaded, peak: Double(args[4])!, format: ExportFormat(rawValue: args[3])!,
                    directory: URL(fileURLWithPath: args[6]), options: options)
                result["path"] = url.path
            case "histogram":
                let loaded = try engine.load(URL(fileURLWithPath: args[2]))
                let stats = try engine.histogram(loaded, peak: Double(args[3])!,
                    maxDimension: args.count > 4 ? Int(args[4])! : 512)
                let data = try JSONEncoder().encode(stats)
                result = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            case "jpeg-primary":
                let data = try JPEGPrimary.sdrData(at: URL(fileURLWithPath: args[2]))
                try data.write(to: URL(fileURLWithPath: args[3]))
                result["bytes"] = data.count
            default: fatalError("测试入口不支持此命令")
            }
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        } catch {
            FileHandle.standardError.write(Data(error.localizedDescription.utf8))
            exit(1)
        }
    }

    static func makeImage(_ values: [Float], width: Int, space: CGColorSpace) -> CIImage {
        let data = values.withUnsafeBytes { Data($0) }
        return CIImage(bitmapData: data, bytesPerRow: width * 16,
                       size: CGSize(width: width, height: values.count / 4 / width),
                       format: .RGBAf, colorSpace: space)
    }

    static func pixels(_ image: CIImage, engine: ImageEngine, space: CGColorSpace) -> [Float] {
        var values = [Float](repeating: 0, count: Int(image.extent.width * image.extent.height) * 4)
        values.withUnsafeMutableBytes { buffer in
            engine.context.render(image, toBitmap: buffer.baseAddress!, rowBytes: Int(image.extent.width) * 16,
                                  bounds: image.extent, format: .RGBAf, colorSpace: space)
        }
        return values
    }
}
