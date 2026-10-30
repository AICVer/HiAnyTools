import Foundation

enum ReferenceGamut: String, CaseIterable, Codable {
    case sRGB = "sRGB", displayP3 = "Display P3", bt2020 = "BT.2020"

    /// D65 标准原色到线性 BT.2020；由 colour-science 归一原色矩阵计算。
    var toBT2020: [[Double]] {
        switch self {
        case .sRGB:
            return [[0.6274038959346991,0.3292830383778839,0.0433130656874172],
                    [0.06909728935823205,0.9195403950754585,0.01136231556630918],
                    [0.01639143887515023,0.08801330787722578,0.8955952532476243]]
        case .displayP3:
            return [[0.7538330343617218,0.19859736905261666,0.04756959658566184],
                    [0.04574384896535825,0.9417772198116936,0.01247893122294813],
                    [-0.00121034035451839,0.01760171730109,0.9836086230534284]]
        case .bt2020: return [[1,0,0],[0,1,0],[0,0,1]]
        }
    }
}

struct ReferenceGamutMesh: Codable {
    let gamut: ReferenceGamut
    let peakNits: Double
    let boundaryRGB: [[Double]]
    let vertices: [ColorPoint]
    let triangles: [[Int]]
    let edges: [[Int]]

    /// 采样RGB立方体六个面；共用边界顶点，保持闭合拓扑，不取点云凸包。
    static func make(gamut: ReferenceGamut, peakNits: Double, divisions: Int = 8) throws -> ReferenceGamutMesh {
        guard peakNits.isFinite, (1...10000).contains(peakNits), (2...16).contains(divisions)
        else { throw ImageFailure.invalidOptions }
        var lookup: [[Int]: Int] = [:]
        var boundaryRGB: [[Double]] = []
        var vertices: [ColorPoint] = []
        var triangles: [[Int]] = []
        var edges = Set<[Int]>()
        func vertex(_ indices: [Int]) -> Int {
            if let index = lookup[indices] { return index }
            let index = vertices.count
            lookup[indices] = index
            // 暗端加密，改善非线性坐标在黑点附近的曲面近似。
            let rgb = indices.map { pow(Double($0) / Double(divisions), 2) }
            let working = PixelColorMath.multiply(gamut.toBT2020, rgb).map { $0 * peakNits / 203 }
            boundaryRGB.append(rgb)
            vertices.append(PixelColorMath.point(rgb: working, displayRGB: [0,0,0]))
            return index
        }
        for axis in 0..<3 {
            for side in [0, divisions] {
                for row in 0..<divisions {
                    try Task.checkCancellation()
                    for column in 0..<divisions {
                        func at(_ u: Int, _ v: Int) -> Int {
                            var indices = [0,0,0]
                            indices[axis] = side
                            indices[(axis+1)%3] = u
                            indices[(axis+2)%3] = v
                            return vertex(indices)
                        }
                        let a = at(row,column), b = at(row+1,column)
                        let c = at(row+1,column+1), d = at(row,column+1)
                        triangles += side == 0 ? [[a,c,b],[a,d,c]] : [[a,b,c],[a,c,d]]
                        for pair in [[a,b],[b,c],[c,d],[d,a]] { edges.insert(pair.sorted()) }
                    }
                }
            }
        }
        return ReferenceGamutMesh(gamut: gamut, peakNits: peakNits, boundaryRGB: boundaryRGB,
            vertices: vertices, triangles: triangles, edges: edges.sorted { $0.lexicographicallyPrecedes($1) })
    }
}
