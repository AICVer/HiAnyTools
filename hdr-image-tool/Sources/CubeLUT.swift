import Foundation
import CoreImage

enum LUTFailure: LocalizedError {
    case invalid(String), requiresSDR
    var errorDescription: String? {
        switch self {
        case .invalid(let reason): return "无法读取3D LUT：\(reason)"
        case .requiresSDR: return "此LUT仅接受SDR源图，请先选择SDR图像。"
        }
    }
}

/// 首版信号契约：sRGB编码码值输入，线性BT.2020输出，R最快遍历。
struct CubeLUT {
    let name: String
    let dimension: Int
    let domainMin: [Float]
    let domainMax: [Float]
    let rgba: [Float]

    static func read(_ url: URL) throws -> CubeLUT {
        try parse(String(contentsOf: url, encoding: .utf8), name: url.lastPathComponent)
    }

    static func parse(_ text: String, name: String) throws -> CubeLUT {
        var dimension: Int?
        var low: [Float] = [0,0,0], high: [Float] = [1,1,1]
        var values: [Float] = []
        for (index, raw) in text.replacingOccurrences(of: "\u{feff}", with: "").components(separatedBy: .newlines).enumerated() {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let key = fields.first else { continue }
            if key == "TITLE" { continue }
            if key == "LUT_3D_SIZE" {
                guard dimension == nil, fields.count == 2, let n = Int(fields[1]), (2...65).contains(n)
                else { throw LUTFailure.invalid("第\(index+1)行的网格阶数须为2～65。") }
                dimension = n
                continue
            }
            let tokens = key.hasPrefix("DOMAIN_") ? Array(fields.dropFirst()) : fields
            let numbers = tokens.compactMap(Float.init)
            guard numbers.count == 3, tokens.count == 3, numbers.allSatisfy(\.isFinite)
            else { throw LUTFailure.invalid("第\(index+1)行不是有效RGB数据或受支持的3D指令。") }
            if key == "DOMAIN_MIN" { low = numbers }
            else if key == "DOMAIN_MAX" { high = numbers }
            else if key.hasPrefix("DOMAIN_") { throw LUTFailure.invalid("未知DOMAIN指令。") }
            else { values += numbers + [1] }
        }
        guard let dimension, values.count == dimension*dimension*dimension*4,
              zip(low,high).allSatisfy({ $0 < $1 })
        else { throw LUTFailure.invalid("网格数据量或DOMAIN范围不正确。") }
        return CubeLUT(name: name, dimension: dimension, domainMin: low, domainMax: high, rgba: values)
    }
}

extension ImageEngine {
    /// 对原SDR图独立应用LUT；保留线性BT.2020扩展值与alpha，不累积修改输入。
    func applying(_ lut: CubeLUT, to image: LoadedImage) throws -> LoadedImage {
        guard !image.isHDR else { throw LUTFailure.requiresSDR }
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let encoded = image.sdr.matchedFromWorkingSpace(to: srgb) else { throw ImageFailure.renderFailed }
        let code = """
        kernel vec4 lutTrilinear(sampler image, sampler table, float n, vec3 lo, vec3 span) {
            vec4 p = unpremultiply(sample(image, samplerCoord(image)));
            vec3 pos = clamp((p.rgb - lo) / span, 0.0, 1.0) * (n - 1.0);
            vec3 a = floor(pos), b = min(a + 1.0, vec3(n - 1.0)), f = pos - a;
            vec3 c000 = sample(table, samplerTransform(table, vec2(a.r+n*a.g+0.5,n-a.b-0.5))).rgb;
            vec3 c100 = sample(table, samplerTransform(table, vec2(b.r+n*a.g+0.5,n-a.b-0.5))).rgb;
            vec3 c010 = sample(table, samplerTransform(table, vec2(a.r+n*b.g+0.5,n-a.b-0.5))).rgb;
            vec3 c110 = sample(table, samplerTransform(table, vec2(b.r+n*b.g+0.5,n-a.b-0.5))).rgb;
            vec3 c001 = sample(table, samplerTransform(table, vec2(a.r+n*a.g+0.5,n-b.b-0.5))).rgb;
            vec3 c101 = sample(table, samplerTransform(table, vec2(b.r+n*a.g+0.5,n-b.b-0.5))).rgb;
            vec3 c011 = sample(table, samplerTransform(table, vec2(a.r+n*b.g+0.5,n-b.b-0.5))).rgb;
            vec3 c111 = sample(table, samplerTransform(table, vec2(b.r+n*b.g+0.5,n-b.b-0.5))).rgb;
            vec3 c0 = mix(mix(c000,c100,f.r), mix(c010,c110,f.r), f.g);
            vec3 c1 = mix(mix(c001,c101,f.r), mix(c011,c111,f.r), f.g);
            return premultiply(vec4(mix(c0,c1,f.b), p.a));
        }
        """
        // LUT是数值纹理，禁用色彩解释；显式八角点采样，保留负值与大于1的线性输出。
        // 位图首行为B=0，Core Image坐标y向上，故上面的纹理采样翻转B坐标。
        let table = CIImage(bitmapData: lut.rgba.withUnsafeBytes { Data($0) },
            bytesPerRow: lut.dimension * lut.dimension * 16,
            size: CGSize(width: lut.dimension * lut.dimension, height: lut.dimension),
            format: .RGBAf, colorSpace: nil).samplingNearest()
        guard let kernel = CIKernel(source: code),
              let result = kernel.apply(extent: encoded.extent,
                roiCallback: { index, rect in index == 1 ? table.extent : rect }, arguments: [encoded, table, lut.dimension,
                CIVector(values: lut.domainMin.map(CGFloat.init), count: 3),
                CIVector(values: zip(lut.domainMax,lut.domainMin).map { CGFloat($0-$1) }, count: 3)])
        else { throw ImageFailure.renderFailed }
        return LoadedImage(hdr: result, sdr: result, gainMap: nil, isHDR: false,
            typeName: image.typeName, name: image.name, sdrColorSpace: CGColorSpace(name: CGColorSpace.itur_2020)!)
    }
}
