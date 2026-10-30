import Foundation
import simd

struct PixelHullMesh: Codable {
    let vertices: [[Double]]
    let triangles: [[Int]]
    let edges: [[Int]]
    let dimension: Int
}

/// 采样点的凸包，不等同于非凸色域边界或设备色域。
enum PixelHull {
    static func polygon(_ input: [[Double]]) -> [[Double]] {
        let points = Array(Set(input.filter { $0.count == 2 && $0.allSatisfy(\.isFinite) }))
            .sorted { $0.lexicographicallyPrecedes($1) }
        guard points.count > 2 else { return points }
        func cross(_ a: [Double], _ b: [Double], _ c: [Double]) -> Double {
            (b[0]-a[0]) * (c[1]-a[1]) - (b[1]-a[1]) * (c[0]-a[0])
        }
        func half(_ sequence: [[Double]]) -> [[Double]] {
            var result: [[Double]] = []
            for point in sequence {
                while result.count > 1 && cross(result[result.count-2], result.last!, point) <= 0 {
                    result.removeLast()
                }
                result.append(point)
            }
            return result
        }
        return Array(half(points).dropLast()) + Array(half(Array(points.reversed())).dropLast())
    }

    /// 增量三维凸包；共面/共线采样分别返回面片/边，避免捏造体积。
    static func mesh(_ input: [[Double]]) throws -> PixelHullMesh {
        let raw = Array(Set(input.filter { $0.count == 3 && $0.allSatisfy(\.isFinite) }))
            .sorted { $0.lexicographicallyPrecedes($1) }
        guard raw.count > 1 else {
            return PixelHullMesh(vertices: raw, triangles: [], edges: [], dimension: raw.isEmpty ? -1 : 0)
        }
        let vectors = raw.map { SIMD3<Double>($0[0], $0[1], $0[2]) }
        let scale = (0..<3).map { axis in raw.map { $0[axis] }.max()! - raw.map { $0[axis] }.min()! }.max()!
        let points = vectors.map { ($0-vectors[0])/scale }
        let epsilon = 1e-9
        let a = 0
        let b = points.indices.max { simd_length_squared(points[$0]) < simd_length_squared(points[$1]) }!
        let line = points[b]-points[a]
        let c = points.indices.max {
            simd_length_squared(simd_cross(line, points[$0]-points[a])) <
                simd_length_squared(simd_cross(line, points[$1]-points[a]))
        }!
        let cross = simd_cross(line, points[c]-points[a])
        if simd_length(cross) <= epsilon * simd_length(line) {
            return PixelHullMesh(vertices: [raw[a], raw[b]], triangles: [], edges: [[0,1]], dimension: 1)
        }
        let normal = simd_normalize(cross)
        let d = points.indices.max {
            abs(simd_dot(normal, points[$0]-points[a])) < abs(simd_dot(normal, points[$1]-points[a]))
        }!
        if abs(simd_dot(normal, points[d]-points[a])) <= epsilon {
            let u = simd_normalize(line), v = simd_cross(normal, u)
            let projected = points.map { [simd_dot($0, u), simd_dot($0, v)] }
            let boundary = polygon(projected)
            let indices = boundary.map { projected.firstIndex(of: $0)! }
            let triangles = (1..<indices.count-1).map { [0,$0,$0+1] }
            let edges = indices.indices.map { [$0,($0+1)%indices.count] }
            return PixelHullMesh(vertices: indices.map { raw[$0] }, triangles: triangles, edges: edges, dimension: 2)
        }
        let inside = (points[a]+points[b]+points[c]+points[d])/4
        struct Face {
            let indices: [Int]
            let normal: SIMD3<Double>
            let anchor: SIMD3<Double>
            func distance(_ point: SIMD3<Double>) -> Double { simd_dot(normal, point-anchor) }
        }
        func face(_ indices: [Int]) -> Face? {
            var indices = indices
            var n = simd_cross(points[indices[1]]-points[indices[0]], points[indices[2]]-points[indices[0]])
            guard simd_length(n) > 1e-14 else { return nil }
            if simd_dot(n, inside-points[indices[0]]) > 0 {
                indices.swapAt(1,2)
                n = -n
            }
            return Face(indices: indices, normal: simd_normalize(n), anchor: points[indices[0]])
        }
        var faces = [[a,b,c],[a,d,b],[a,c,d],[b,d,c]].compactMap(face)
        let seed: Set<Int> = [a,b,c,d]
        for index in points.indices where !seed.contains(index) {
            try Task.checkCancellation()
            let visible = faces.filter { $0.distance(points[index]) > epsilon }
            guard !visible.isEmpty else { continue }
            var counts: [[Int]: Int] = [:]
            for facet in visible {
                for k in 0..<3 {
                    let edge = [facet.indices[k], facet.indices[(k+1)%3]].sorted()
                    counts[edge, default: 0] += 1
                }
            }
            faces.removeAll { $0.distance(points[index]) > epsilon }
            for edge in counts.keys.sorted(by: { $0.lexicographicallyPrecedes($1) }) where counts[edge] == 1 {
                if let facet = face([edge[0],edge[1],index]) { faces.append(facet) }
            }
        }
        let indices = Array(Set(faces.flatMap(\.indices))).sorted()
        let remap = Dictionary(uniqueKeysWithValues: indices.enumerated().map { ($0.element,$0.offset) })
        let triangles = faces.map { $0.indices.map { remap[$0]! } }
        var edges = Set<[Int]>()
        for triangle in triangles {
            for k in 0..<3 { edges.insert([triangle[k],triangle[(k+1)%3]].sorted()) }
        }
        return PixelHullMesh(vertices: indices.map { raw[$0] }, triangles: triangles,
            edges: edges.sorted { $0.lexicographicallyPrecedes($1) }, dimension: 3)
    }
}
