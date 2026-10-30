import CoreGraphics

enum HDRColorSpace: String, CaseIterable, Codable {
    case bt2020 = "BT.2020", displayP3 = "Display P3"

    var pq: CGColorSpace {
        CGColorSpace(name: self == .bt2020 ? CGColorSpace.itur_2100_PQ : CGColorSpace.displayP3_PQ)!
    }
    var sdr: CGColorSpace {
        CGColorSpace(name: self == .bt2020 ? CGColorSpace.itur_2020 : CGColorSpace.displayP3)!
    }
    var linear: CGColorSpace {
        CGColorSpace(name: self == .bt2020 ? CGColorSpace.extendedLinearITUR_2020 : CGColorSpace.extendedLinearDisplayP3)!
    }
}

enum SDRColorSpace: String, CaseIterable, Codable {
    case sRGB = "sRGB", displayP3 = "Display P3", adobeRGB = "Adobe RGB", bt2020 = "BT.2020"

    var space: CGColorSpace {
        switch self {
        case .sRGB: return CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3: return CGColorSpace(name: CGColorSpace.displayP3)!
        case .adobeRGB: return CGColorSpace(name: CGColorSpace.adobeRGB1998)!
        case .bt2020: return CGColorSpace(name: CGColorSpace.itur_2020)!
        }
    }
}

enum SDRMapping: String, CaseIterable, Codable {
    case xyz = "等 XYZ", rgb = "RGB 直通"
}

/// PNG 解码后的 Adobe RGB 可成为无系统名称的等价 ICC；比较实际色度而非名称。
func matchingColorSpace(_ actual: CGColorSpace?, _ expected: CGColorSpace) -> Bool {
    guard let actual, actual.model == .rgb else { return false }
    if actual.name != nil && actual.name == expected.name { return true }
    let xyz = CGColorSpace(name: CGColorSpace.genericXYZ)!
    let samples: [[CGFloat]] = [[0,0,0,1], [1,0,0,1], [0,1,0,1], [0,0,1,1],
                                [1,1,1,1], [0.25,0.25,0.25,1], [0.5,0.5,0.5,1], [0.75,0.75,0.75,1]]
    return samples.allSatisfy { sample in
        guard let a = CGColor(colorSpace: actual, components: sample)?.converted(to: xyz, intent: .relativeColorimetric, options: nil)?.components,
              let b = CGColor(colorSpace: expected, components: sample)?.converted(to: xyz, intent: .relativeColorimetric, options: nil)?.components else { return false }
        return zip(a, b).allSatisfy { abs($0 - $1) < 0.0002 }
    }
}
