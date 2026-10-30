#if os(iOS)
import SwiftUI

struct PixelVisualizationPanel: View {
    let distribution: PixelDistribution
    let enhancedDistribution: PixelDistribution?
    let analysisID: String
    init(distribution: PixelDistribution, enhancedDistribution: PixelDistribution? = nil, analysisID: String = "") {
        self.distribution = distribution
        self.enhancedDistribution = enhancedDistribution
        self.analysisID = analysisID
    }
    @State private var showOriginalPoints = true
    @State private var showEnhancedPoints = true
    @State private var showOriginalHull = false
    @State private var showEnhancedHull = false
    @State private var originalHull: PixelHullMesh?
    @State private var enhancedHull: PixelHullMesh?
    @State private var loadedHullSpace: GamutVolumeSpace?
    @State private var loadedHullID: String?
    @State private var hullError: String?
    @State private var useUV = false
    @State private var showSRGB = true
    @State private var showP3 = true
    @State private var show2020 = true
    @State private var volumeSpace = GamutVolumeSpace.cam16
    @State private var showReferenceSRGB = true
    @State private var showReferenceP3 = true
    @State private var showReference2020 = true
    @State private var referencePeak = 10000
    @State private var referenceMeshes: [ReferenceGamutMesh] = []
    @State private var loadedReferencePeak: Int?
    @State private var referenceError: String?
    @State private var automaticRotation = false
    @State private var yaw = 0.6
    @State private var pitch = -0.25
    @State private var zoom = 1.0
    @State private var rotationStarted = Date()
    @GestureState private var drag = CGSize.zero
    @GestureState private var magnification = 1.0

    private func chromaticity(_ xy: [Double]) -> [Double] {
        guard useUV else { return xy }
        let d = -2 * xy[0] + 12 * xy[1] + 3
        return [4 * xy[0] / d, 9 * xy[1] / d]
    }
    private func color(_ point: ColorPoint) -> Color {
        Color(red: point.displayRGB[0], green: point.displayRGB[1], blue: point.displayRGB[2])
    }

    private func setRotation(_ enabled: Bool) {
        if automaticRotation && !enabled { yaw += Date().timeIntervalSince(rotationStarted) * 0.25 }
        if enabled && !automaticRotation { rotationStarted = .now }
        automaticRotation = enabled
    }

    private func referenceColor(_ gamut: ReferenceGamut) -> Color {
        switch gamut {
        case .sRGB: return .blue
        case .displayP3: return .orange
        case .bt2020: return .purple
        }
    }

    private var visibleReferenceMeshes: [ReferenceGamutMesh] {
        guard loadedReferencePeak == referencePeak else { return [] }
        return referenceMeshes.filter {
            switch $0.gamut {
            case .sRGB: return showReferenceSRGB
            case .displayP3: return showReferenceP3
            case .bt2020: return showReference2020
            }
        }
    }

    var body: some View {
        GroupBox("像素色域分布") {
            VStack(alignment: .leading, spacing: 12) {
                Text("当前 HDR 工作图 · 采样 \(distribution.width)×\(distribution.height) / 原图 \(distribution.originalWidth)×\(distribution.originalHeight) · \(distribution.points.count) 点")
                    .font(.caption).foregroundStyle(.secondary)
                Text("坐标保留 HDR 数值；点的颜色仅用 SDR 表观辅助辨识。透明排除 \(distribution.transparentCount)，无效排除 \(distribution.invalidCount)。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("源线性 RGB 负值修正：\(distribution.negativeClampedCount) 个采样；仅用于二维与三维分析。")
                    .font(.caption).foregroundStyle(.secondary)
                if let enhancedDistribution {
                    Text("LUT增强图：同位置\(enhancedDistribution.points.count)点，负值修正\(enhancedDistribution.negativeClampedCount)个；增强前后采用相同峰值与坐标条件。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Toggle(enhancedDistribution == nil ? "当前图散点" : "原图散点", isOn: $showOriginalPoints)
                    if enhancedDistribution != nil { Toggle("LUT增强散点", isOn: $showEnhancedPoints) }
                }.font(.caption).toggleStyle(.button)
                HStack {
                    Toggle(enhancedDistribution == nil ? "当前图凸包" : "原图凸包", isOn: $showOriginalHull).tint(.cyan)
                    if enhancedDistribution != nil { Toggle("LUT增强凸包", isOn: $showEnhancedHull).tint(.pink) }
                }.font(.caption).toggleStyle(.button)
                Text("散点和凸包开关同时作用于二维与三维；凸包会填平凹陷，仅描述采样范围，不是设备色域。原图凸包为青色，LUT凸包为粉色。")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("色度图", selection: $useUV) {
                    Text("CIE 1931 xy").tag(false)
                    Text("CIE 1976 u′v′").tag(true)
                }.pickerStyle(.segmented)
                HStack {
                    Toggle("sRGB", isOn: $showSRGB).tint(.blue)
                    Toggle("Display P3", isOn: $showP3).tint(.orange)
                    Toggle("BT.2020", isOn: $show2020).tint(.purple)
                }.font(.caption).toggleStyle(.button).lineLimit(1)
                chromaticityChart
                let noChromaticity = distribution.points.filter { (useUV ? $0.uv : $0.xy) == nil }.count
                Text("\(useUV ? "u′ / v′" : "x / y") · 黑色等无定义色度：\(noChromaticity)；轨迹为 CIE 1931 2°，380～780 nm。")
                    .font(.caption).foregroundStyle(.secondary)
                if let enhancedDistribution {
                    Text("LUT增强图无定义色度：\(enhancedDistribution.points.filter { (useUV ? $0.uv : $0.xy) == nil }.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("立体色域", selection: $volumeSpace) {
                    ForEach(GamutVolumeSpace.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Text("三维参考外包络").font(.subheadline.weight(.semibold))
                HStack {
                    Toggle("sRGB", isOn: $showReferenceSRGB).tint(.blue)
                        .accessibilityLabel("三维 sRGB 外包络")
                    Toggle("Display P3", isOn: $showReferenceP3).tint(.orange)
                        .accessibilityLabel("三维 Display P3 外包络")
                    Toggle("BT.2020", isOn: $showReference2020).tint(.purple)
                        .accessibilityLabel("三维 BT.2020 外包络")
                }.font(.caption).toggleStyle(.button).lineLimit(1)
                Picker("包络参考峰值", selection: $referencePeak) {
                    ForEach([203,600,1000,10000], id: \.self) { Text("\($0) nit").tag($0) }
                }.pickerStyle(.menu)
                if loadedReferencePeak != referencePeak {
                    if let referenceError { Text("参考包络暂不可用：\(referenceError)").font(.caption) }
                    else { ProgressView("正在计算参考包络…") }
                }
                volumeChart
                if (showOriginalHull || showEnhancedHull) && (loadedHullSpace != volumeSpace || loadedHullID != analysisID) {
                    if let hullError { Text("像素凸包暂不可用：\(hullError)").font(.caption) }
                    else { ProgressView("正在计算像素凸包…") }
                }
                Text("参考包络：D65，黑位0，三种原色共用峰值\(referencePeak) nit；半透明六面采样网格。超过203 nit时表示该原色的HDR参考范围，不是标准SDR显示器实测能力。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Toggle("自动旋转", isOn: Binding(get: { automaticRotation }, set: setRotation))
                    Button("重置视角") { setRotation(false); yaw = 0.6; pitch = -0.25; zoom = 1 }
                }.font(.caption)
                Text("拖动旋转，双指缩放；亮度轴朝上，三轴等比例缩放。\(volumeSpace.axes.joined(separator: " / "))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(volumeSpace == .ictcp
                     ? "ICtCp：BT.2100 PQ，1倍线性参考白=203 nit；坐标未经JND缩放，超出PQ定义域的点不绘制。"
                     : "D65，参考白203 nit；Lab保留L*>100。CAM16-UCS：LA=100 cd/m²，Yb=20，平均环绕、完全适应；超出模型有效域的点不绘制。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("三维有效点 \(distribution.points.filter { $0.scene(volumeSpace) != nil }.count) / \(distribution.points.count)；采样点云，不表示设备色域体积。")
                    .font(.caption).foregroundStyle(.secondary)
                if let enhancedDistribution {
                    Text("LUT增强三维有效点 \(enhancedDistribution.points.filter { $0.scene(volumeSpace) != nil }.count) / \(enhancedDistribution.points.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: referencePeak) {
            let requestedPeak = referencePeak
            referenceError = nil
            do {
                let meshes = try await Task.detached(priority: .userInitiated) {
                    try ReferenceGamut.allCases.map {
                        try ReferenceGamutMesh.make(gamut: $0, peakNits: Double(requestedPeak))
                    }
                }.value
                try Task.checkCancellation()
                guard requestedPeak == referencePeak else { return }
                referenceMeshes = meshes
                loadedReferencePeak = requestedPeak
            } catch is CancellationError { return }
            catch { if requestedPeak == referencePeak { referenceError = error.localizedDescription } }
        }
        .task(id: "\(analysisID)|\(volumeSpace.rawValue)") {
            let requestedSpace = volumeSpace
            loadedHullSpace = nil
            hullError = nil
            let originalPoints = distribution.points.compactMap { $0.scene(requestedSpace) }
            let enhancedPoints = enhancedDistribution?.points.compactMap { $0.scene(requestedSpace) }
            do {
                let hulls = try await Task.detached(priority: .userInitiated) {
                    (try PixelHull.mesh(originalPoints), try enhancedPoints.map { try PixelHull.mesh($0) })
                }.value
                guard !Task.isCancelled, requestedSpace == volumeSpace else { return }
                originalHull = hulls.0
                enhancedHull = hulls.1
                loadedHullSpace = requestedSpace
                loadedHullID = analysisID
            } catch is CancellationError { return }
            catch { if requestedSpace == volumeSpace { hullError = error.localizedDescription } }
        }
    }

    private var chromaticityChart: some View {
        let originalPolygon = showOriginalHull ? PixelHull.polygon(distribution.points.compactMap { useUV ? $0.uv : $0.xy }) : []
        let enhancedPolygon = showEnhancedHull ? PixelHull.polygon(enhancedDistribution?.points.compactMap { useUV ? $0.uv : $0.xy } ?? []) : []
        let points = (showOriginalPoints ? distribution.points : []) + (showEnhancedPoints ? enhancedDistribution?.points ?? [] : [])
        return Canvas { context, size in
            let maximum = useUV ? 0.65 : 0.85
            let margin = 28.0
            let side = min(size.width, size.height) - margin * 2
            func position(_ value: [Double]) -> CGPoint {
                CGPoint(x: margin + value[0] / maximum * side,
                        y: size.height - margin - value[1] / maximum * side)
            }
            for tick in 0...8 {
                let value = Double(tick) / 10
                guard value <= maximum else { continue }
                var grid = Path()
                grid.move(to: position([value,0])); grid.addLine(to: position([value,maximum]))
                grid.move(to: position([0,value])); grid.addLine(to: position([maximum,value]))
                context.stroke(grid, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)
                let text = Text(String(format: "%.1f", value)).font(.system(size: 9)).foregroundStyle(.secondary)
                context.draw(text, at: CGPoint(x: position([value,0]).x, y: size.height - 12))
                context.draw(text, at: CGPoint(x: 12, y: position([0,value]).y))
            }
            func polygon(_ vertices: [[Double]], tint: Color, width: Double) {
                var path = Path()
                for (index, value) in vertices.enumerated() {
                    if index == 0 { path.move(to: position(chromaticity(value))) }
                    else { path.addLine(to: position(chromaticity(value))) }
                }
                path.closeSubpath()
                context.stroke(path, with: .color(tint), lineWidth: width)
            }
            polygon(SpectralLocus.xy, tint: .secondary, width: 1)
            for point in points {
                guard let value = useUV ? point.uv : point.xy else { continue }
                let p = position(value)
                guard p.x >= margin && p.x <= margin+side && p.y >= margin && p.y <= size.height-margin else { continue }
                context.fill(Path(ellipseIn: CGRect(x:p.x-1.5,y:p.y-1.5,width:3,height:3)), with:.color(color(point).opacity(0.65)))
            }
            func outline(_ values: [[Double]], tint: Color) {
                guard let first = values.first else { return }
                if values.count == 1 {
                    let p = position(first)
                    context.fill(Path(ellipseIn: CGRect(x: p.x-2,y: p.y-2,width: 4,height: 4)), with: .color(tint))
                    return
                }
                var path = Path()
                path.move(to: position(first))
                for value in values.dropFirst() { path.addLine(to: position(value)) }
                path.closeSubpath()
                context.stroke(path, with: .color(tint), lineWidth: 2)
            }
            outline(originalPolygon, tint: .cyan)
            outline(enhancedPolygon, tint: .pink)
            if showSRGB { polygon([[0.64,0.33],[0.30,0.60],[0.15,0.06]], tint:.blue, width:1.5) }
            if showP3 { polygon([[0.68,0.32],[0.265,0.69],[0.15,0.06]], tint:.orange, width:1.5) }
            if show2020 { polygon([[0.708,0.292],[0.170,0.797],[0.131,0.046]], tint:.purple, width:1.5) }
            let white = position(chromaticity([0.3127,0.3290]))
            context.draw(Text("＋ D65").font(.system(size:10)), at:white, anchor:.leading)
        }
        .aspectRatio(1, contentMode:.fit)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("\(useUV ? "CIE 1976 u′v′" : "CIE 1931 xy") 像素分布，原图散点\(showOriginalPoints ? distribution.points.count : 0)，LUT散点\(showEnhancedPoints ? enhancedDistribution?.points.count ?? 0 : 0)，原图凸包\(showOriginalHull ? "显示" : "隐藏")，LUT凸包\(showEnhancedHull ? "显示" : "隐藏")")
    }

    private var volumeChart: some View {
        let points = (showOriginalPoints ? distribution.points : []) + (showEnhancedPoints ? enhancedDistribution?.points ?? [] : [])
        let entries = points.compactMap { point -> (ColorPoint, [Double])? in
            point.scene(volumeSpace).map { (point, $0) }
        }
        var shells = visibleReferenceMeshes.map {
            (triangles: $0.triangles, edges: $0.edges, positions: $0.vertices.map { $0.scene(volumeSpace) }, tint: referenceColor($0.gamut), pixel: false)
        }
        if loadedHullSpace == volumeSpace && loadedHullID == analysisID {
            for (hull, visible, tint) in [(originalHull, showOriginalHull, Color.cyan), (enhancedHull, showEnhancedHull, Color.pink)] {
                if visible, let hull {
                    shells.append((hull.triangles,hull.edges,hull.vertices.map { Optional($0) },tint,true))
                }
            }
        }
        let boundsPoints = entries.map { $0.1 } + shells.flatMap { $0.positions.compactMap { $0 } }
        let minimum = (0..<3).map { axis in min(0, boundsPoints.map { $0[axis] }.min() ?? 0) }
        let maximum = (0..<3).map { axis in max(0, boundsPoints.map { $0[axis] }.max() ?? 1) }
        let center = zip(minimum,maximum).map { ($0+$1)/2 }
        let extent = max(1e-6, zip(minimum,maximum).map { $1-$0 }.max() ?? 1)
        return TimelineView(.animation(minimumInterval:1.0/20, paused:!automaticRotation)) { timeline in
            let angle = yaw + Double(drag.width)/100 + (automaticRotation ? timeline.date.timeIntervalSince(rotationStarted)*0.25 : 0)
            let elevation = max(-1.4, min(1.4,pitch + Double(drag.height)/150))
            Canvas { context, size in
                let scale = min(size.width,size.height)*0.62/extent * zoom * magnification
                func rotated(_ p: [Double]) -> [Double] {
                    let x=p[0]-center[0], y=p[1]-center[1], z=p[2]-center[2]
                    let a=x*cos(angle)+z*sin(angle), b = -x*sin(angle)+z*cos(angle)
                    return [a, y*cos(elevation)-b*sin(elevation), y*sin(elevation)+b*cos(elevation)]
                }
                func projected(_ p: [Double]) -> CGPoint {
                    CGPoint(x:size.width/2+p[0]*scale,y:size.height/2-p[1]*scale)
                }
                let transformed = shells.map { ($0, $0.positions.map { $0.map(rotated) }) }
                // 透明外壳按深度从远到近绘制；散点保留在前景，便于透壳比较。
                var facets: [(depth: Double, points: [[Double]], tint: Color, pixel: Bool)] = []
                for (mesh, positions) in transformed {
                    for triangle in mesh.triangles {
                        let points = triangle.compactMap { positions[$0] }
                        guard points.count == 3 else { continue }
                        facets.append((points.map { $0[2] }.reduce(0,+)/3, points, mesh.tint, mesh.pixel))
                    }
                }
                for facet in facets.sorted(by: { $0.depth < $1.depth }) {
                    var path = Path()
                    path.move(to: projected(facet.points[0]))
                    path.addLine(to: projected(facet.points[1]))
                    path.addLine(to: projected(facet.points[2]))
                    path.closeSubpath()
                    context.fill(path, with: .color(facet.tint.opacity(facet.pixel ? 0.10 : 0.045)))
                }
                for (mesh, positions) in transformed {
                    var wire = Path()
                    for edge in mesh.edges {
                        guard let a = positions[edge[0]], let b = positions[edge[1]] else { continue }
                        wire.move(to: projected(a)); wire.addLine(to: projected(b))
                    }
                    context.stroke(wire, with: .color(mesh.tint.opacity(mesh.pixel ? 0.75 : 0.32)), lineWidth: mesh.pixel ? 1 : 0.5)
                    if mesh.pixel && mesh.edges.isEmpty, let p = positions.first ?? nil {
                        let p = projected(p)
                        context.fill(Path(ellipseIn: CGRect(x:p.x-2,y:p.y-2,width:4,height:4)), with: .color(mesh.tint))
                    }
                }
                for axis in 0..<3 {
                    var start=[0.0,0.0,0.0], end=start
                    start[axis]=minimum[axis]; end[axis]=maximum[axis]
                    var path=Path(); path.move(to:projected(rotated(start))); path.addLine(to:projected(rotated(end)))
                    context.stroke(path,with:.color(.secondary),lineWidth:1)
                    context.draw(Text("\(volumeSpace.axes[axis]) \(maximum[axis],specifier:"%.2f")").font(.system(size:10)),at:projected(rotated(end)),anchor:.bottomLeading)
                }
                let sorted = entries.map { ($0.0,rotated($0.1)) }.sorted { $0.1[2] < $1.1[2] }
                for (point, location) in sorted {
                    let p=projected(location)
                    context.fill(Path(ellipseIn:CGRect(x:p.x-1.8,y:p.y-1.8,width:3.6,height:3.6)),with:.color(color(point).opacity(0.8)))
                }
            }
        }
        .frame(height:300).clipped()
        .background(Color.secondary.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
        .contentShape(Rectangle())
        .gesture(DragGesture().updating($drag) { value,state,_ in state=value.translation }
            .onChanged { _ in if automaticRotation { setRotation(false) } }
            .onEnded { value in yaw += Double(value.translation.width)/100; pitch=max(-1.4,min(1.4,pitch+Double(value.translation.height)/150)) })
        .simultaneousGesture(MagnifyGesture().updating($magnification) { value,state,_ in state=value.magnification }
            .onEnded { value in zoom=max(0.3,min(5,zoom*value.magnification)) })
        .accessibilityLabel("\(volumeSpace.rawValue) 三维像素点云，\(entries.count) 点；参考外包络 \(visibleReferenceMeshes.map { $0.gamut.rawValue }.joined(separator: "、"))，\(referencePeak) nit；支持拖动旋转与双指缩放")
    }
}
#endif
