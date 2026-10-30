import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import OSLog

@main
struct HDRImageLabApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

private actor ImageSession {
    let engine = ImageEngine()
    var image: LoadedImage?
    private var original: LoadedImage?
    private var selectedLUT: CubeLUT?
    private var lutApplied = false
    private var latestGeneration = 0

    func load(_ url: URL, generation: Int) throws -> ImageInfo {
        guard generation >= latestGeneration else { throw CancellationError() }
        latestGeneration = generation
        selectedLUT = nil
        lutApplied = false
        image = nil
        let loaded = try engine.load(url)
        image = loaded
        original = loaded
        return ImageInfo(width: Int(loaded.size.width), height: Int(loaded.size.height),
                         isHDR: loaded.isHDR, hasGainMap: loaded.gainMap != nil,
                         typeName: loaded.formatName, dynamicRangeLabel: loaded.dynamicRangeLabel,
                         sourceHeadroom: loaded.isHDR ? try engine.contentHeadroom(of: loaded.hdr) : 1)
    }

    func compose(grayURL: URL?, maximumGain: Double?, generation: Int) throws -> ImageInfo {
        guard generation == latestGeneration else { throw CancellationError() }
        guard let original else { throw ImageFailure.invalidImage }
        let result: LoadedImage
        if let maximumGain {
            let gray = try grayURL.map { try engine.load($0) }
            result = try engine.compose(original, graySource: gray, maximumGain: maximumGain)
        } else { result = original }
        image = result
        lutApplied = false
        selectedLUT = nil
        return ImageInfo(width: Int(result.size.width), height: Int(result.size.height),
            isHDR: result.isHDR, hasGainMap: result.gainMap != nil, typeName: result.formatName,
            dynamicRangeLabel: maximumGain == nil ? result.dynamicRangeLabel : "灰度 GainMap 合成",
            sourceHeadroom: try engine.contentHeadroom(of: result.hdr), isComposed: maximumGain != nil)
    }

    func applyLUT(data: Data?, name: String?, enabled: Bool, generation: Int) throws -> ImageInfo {
        guard generation == latestGeneration else { throw CancellationError() }
        guard let original else { throw ImageFailure.invalidImage }
        var lut = selectedLUT
        if let data {
            guard data.count <= 32_000_000, let text = String(data: data, encoding: .utf8)
            else { throw LUTFailure.invalid("请选择不超过32MB的UTF-8 .cube文件。") }
            lut = try CubeLUT.parse(text, name: name ?? "3D LUT")
        }
        let result: LoadedImage
        if enabled {
            guard let lut else { throw LUTFailure.invalid("请先导入LUT。") }
            result = try engine.applying(lut, to: original)
        } else { result = original }
        selectedLUT = lut
        image = result
        lutApplied = enabled
        return ImageInfo(width: Int(result.size.width), height: Int(result.size.height),
            isHDR: result.isHDR, hasGainMap: result.gainMap != nil, typeName: result.formatName,
            dynamicRangeLabel: enabled ? "LUT增强 · 线性BT.2020" : result.dynamicRangeLabel,
            sourceHeadroom: try engine.contentHeadroom(of: result.hdr), isLUT: enabled,
            lutName: lut?.name, lutDimension: lut?.dimension)
    }

    func preview(mode: ImageMode, peak: Double, generation: Int) throws -> CGImage {
        try Task.checkCancellation()
        guard generation == latestGeneration else { throw CancellationError() }
        guard let image else { throw ImageFailure.invalidImage }
        return try engine.preview(image, mode: mode, peak: peak)
    }

    func histogram(peak: Double, generation: Int) throws -> HistogramStats {
        try Task.checkCancellation()
        guard generation == latestGeneration else { throw CancellationError() }
        guard let image else { throw ImageFailure.invalidImage }
        return try engine.histogram(image, peak: peak)
    }

    func distribution(peak: Double, generation: Int) throws -> PixelComparison {
        try Task.checkCancellation()
        guard generation == latestGeneration else { throw CancellationError() }
        guard let image else { throw ImageFailure.invalidImage }
        let current = try engine.distribution(image, peak: peak)
        if lutApplied, let original {
            return PixelComparison(original: try engine.distribution(original, peak: peak), enhanced: current)
        }
        return PixelComparison(original: current, enhanced: nil)
    }

    func export(peak: Double, format: ExportFormat, generation: Int,
                options: ExportOptions = ExportOptions()) throws -> URL {
        guard generation == latestGeneration else { throw CancellationError() }
        guard let image else { throw ImageFailure.invalidImage }
        return try engine.export(image, peak: peak, format: format,
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("HDRExports"), options: options)
    }

    func exportSDR(format: SDRFormat, generation: Int, options: ExportOptions = ExportOptions()) throws -> URL {
        guard generation == latestGeneration else { throw CancellationError() }
        guard let image else { throw ImageFailure.invalidImage }
        return try engine.exportSDR(image, format: format,
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("HDRExports"), options: options)
    }
}

private struct ImageInfo {
    let width: Int
    let height: Int
    let isHDR: Bool
    let hasGainMap: Bool
    let typeName: String
    let dynamicRangeLabel: String
    let sourceHeadroom: Float
    var isComposed = false
    var isLUT = false
    var lutName: String?
    var lutDimension: Int?
}

@MainActor
private final class ImageModel: ObservableObject {
    @Published var info: ImageInfo?
    @Published var preview: CGImage?
    @Published var previewRequestKey: String?
    @Published var histograms: HistogramStats?
    @Published var histogramRequestKey: String?
    @Published var histogramError: String?
    @Published var exportURL: URL?
    @Published var sdrExportURL: URL?
    @Published var error: String?
    @Published var busy = false
    @Published var revision = UUID()
    @Published var grayURL: URL?
    @Published var grayName: String?
    @Published var distribution: PixelDistribution?
    @Published var enhancedDistribution: PixelDistribution?
    @Published var distributionKey: String?
    @Published var distributionError: String?
    let session = ImageSession()
    private var importGeneration = 0
    private let logger = Logger(subsystem: "local.hdrimagelab", category: "image")

    private func invalidateImage() {
        importGeneration += 1
        revision = UUID()
        info = nil
        preview = nil
        previewRequestKey = nil
        histograms = nil
        histogramRequestKey = nil
        histogramError = nil
        exportURL = nil
        sdrExportURL = nil
        error = nil
        grayURL = nil
        grayName = nil
        distribution = nil
        enhancedDistribution = nil
        distributionKey = nil
        distributionError = nil
    }

    func load(_ url: URL) async {
        invalidateImage()
        let generation = importGeneration
        busy = true
        defer { if generation == importGeneration { busy = false } }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            // CIImage 可延迟读取，复制到应用缓存后再释放外部文件的访问权限。
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HDRImports")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
            try FileManager.default.copyItem(at: url, to: copy)
            let loadedInfo = try await session.load(copy, generation: generation)
            guard generation == importGeneration else { return }
            info = loadedInfo
            revision = UUID()
        } catch is CancellationError { return }
        catch { if generation == importGeneration { report(error) } }
    }

    func loadPhoto(_ item: PhotosPickerItem) async {
        invalidateImage()
        let generation = importGeneration
        busy = true
        defer { if generation == importGeneration { busy = false } }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw ImageFailure.invalidImage
            }
            guard generation == importGeneration else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try data.write(to: url, options: .atomic)
            defer { try? FileManager.default.removeItem(at: url) }
            await load(url)
        } catch { if generation == importGeneration { report(error) } }
    }

    func requestKey(mode: ImageMode, peak: Double) -> String {
        "\(revision)|\(mode.rawValue)|\(peak)"
    }

    func updatePreview(mode: ImageMode, peak: Double) async {
        guard info != nil else { return }
        let requestedRevision = revision
        let generation = importGeneration
        let key = requestKey(mode: mode, peak: peak)
        preview = nil
        previewRequestKey = nil
        histograms = nil
        histogramRequestKey = nil
        histogramError = nil
        do {
            try Task.checkCancellation()
            let rendered = try await session.preview(mode: mode, peak: peak, generation: generation)
            try Task.checkCancellation()
            guard requestedRevision == revision, info != nil else { return }
            previewRequestKey = key
            preview = rendered
        } catch is CancellationError { return }
        catch {
            guard requestedRevision == revision, !Task.isCancelled else { return }
            report(error)
            return
        }
        do {
            let statistics = try await session.histogram(peak: peak, generation: generation)
            try Task.checkCancellation()
            guard requestedRevision == revision, info != nil else { return }
            histogramRequestKey = key
            histograms = statistics
        } catch is CancellationError { return }
        catch {
            guard requestedRevision == revision, !Task.isCancelled else { return }
            histogramError = error.localizedDescription
            logger.error("直方图失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    func export(peak: Double, format: ExportFormat, options: ExportOptions = ExportOptions()) async {
        let generation = importGeneration
        busy = true
        exportURL = nil
        defer { if generation == importGeneration { busy = false } }
        do {
            let url = try await session.export(peak: peak, format: format, generation: generation, options: options)
            guard generation == importGeneration else { return }
            exportURL = url
        } catch is CancellationError { return }
        catch { if generation == importGeneration { report(error) } }
    }

    func exportSDR(format: SDRFormat, options: ExportOptions = ExportOptions()) async {
        let generation = importGeneration
        busy = true
        sdrExportURL = nil
        defer { if generation == importGeneration { busy = false } }
        do {
            let url = try await session.exportSDR(format: format, generation: generation, options: options)
            guard generation == importGeneration else { return }
            sdrExportURL = url
        } catch is CancellationError { return }
        catch { if generation == importGeneration { report(error) } }
    }

    func report(_ failure: Error) {
        error = failure.localizedDescription
        logger.error("图像处理失败：\(failure.localizedDescription, privacy: .public)")
    }

    func loadGray(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HDRImports")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
            try FileManager.default.copyItem(at: url, to: copy)
            grayURL = copy
            grayName = url.lastPathComponent
        } catch { report(error) }
    }

    func loadGrayPhoto(_ item: PhotosPickerItem) async {
        let generation = importGeneration
        busy = true
        defer { if generation == importGeneration { busy = false } }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw ImageFailure.invalidImage }
            guard generation == importGeneration else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try data.write(to: url, options: .atomic)
            grayURL = url
            grayName = "相册图像"
        } catch { if generation == importGeneration { report(error) } }
    }

    func compose(useOtherImage: Bool, maximumGain: Double?) async {
        let generation = importGeneration
        busy = true
        defer { if generation == importGeneration { busy = false } }
        do {
            if useOtherImage && maximumGain != nil && grayURL == nil { throw ImageFailure.invalidImage }
            let updated = try await session.compose(grayURL: useOtherImage ? grayURL : nil,
                maximumGain: maximumGain, generation: generation)
            guard generation == importGeneration else { return }
            info = updated
            revision = UUID()
            exportURL = nil
            sdrExportURL = nil
        } catch is CancellationError { return }
        catch { if generation == importGeneration { report(error) } }
    }

    func loadLUT(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do { await applyLUT(data: try Data(contentsOf: url), name: url.lastPathComponent, enabled: true) }
        catch { report(error) }
    }

    func applyLUT(data: Data? = nil, name: String? = nil, enabled: Bool) async {
        let generation = importGeneration
        busy = true
        defer { if generation == importGeneration { busy = false } }
        do {
            let updated = try await session.applyLUT(data: data, name: name, enabled: enabled, generation: generation)
            guard generation == importGeneration else { return }
            info = updated
            revision = UUID()
            exportURL = nil
            sdrExportURL = nil
        } catch is CancellationError { return }
        catch { if generation == importGeneration { report(error) } }
    }

    func updateDistribution(peak: Double, key: String) async {
        guard info != nil else { return }
        let generation = importGeneration
        let requestedRevision = revision
        distribution = nil
        enhancedDistribution = nil
        distributionKey = nil
        distributionError = nil
        do {
            let result = try await session.distribution(peak: peak, generation: generation)
            try Task.checkCancellation()
            guard requestedRevision == revision else { return }
            distribution = result.original
            enhancedDistribution = result.enhanced
            distributionKey = key
        } catch is CancellationError { return }
        catch {
            if requestedRevision == revision && !Task.isCancelled { distributionError = error.localizedDescription }
        }
    }
}

private struct HDRPreview: UIViewRepresentable {
    let image: CGImage?
    let mode: ImageMode

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.backgroundColor = .black
        // 让 SwiftUI 决定布局，避免原图 intrinsicContentSize 撑开屏幕。
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.preferredImageDynamicRange = mode == .hdr ? .high : .standard
        view.layer.toneMapMode = .automatic
        if #available(iOS 26.0, *) {
            view.layer.preferredDynamicRange = mode == .hdr ? .high : .standard
        } else {
            view.layer.wantsExtendedDynamicRangeContent = mode == .hdr
        }
        view.image = image.map { UIImage(cgImage: $0) }
    }
}

private struct ContentView: View {
    @StateObject private var model = ImageModel()
    @State private var photo: PhotosPickerItem?
    @State private var showImporter = false
    @State private var mode = ImageMode.hdr
    @State private var peak = 203.0
    @State private var format = ExportFormat.png
    @State private var sdrFormat = SDRFormat.jpeg
    @State private var quality = 0.92
    @State private var dpiText = ""
    @State private var sizeAxis = "原尺寸"
    @State private var pixelsText = ""
    @State private var targetKiBText = ""
    @State private var histogramChannel = HistogramChannel.red
    @State private var logarithmicCounts = true
    @State private var showFullScreen = false
    @State private var showGrayImporter = false
    @State private var grayPhoto: PhotosPickerItem?
    @State private var useOtherGray = false
    @State private var maximumGain = 600.0 / 203
    @State private var hdrColorSpace = HDRColorSpace.bt2020
    @State private var sdrColorSpace = SDRColorSpace.sRGB
    @State private var sdrMapping = SDRMapping.xyz
    @State private var showDistribution = false
    @State private var showLUTImporter = false

    private var distributionKey: String { "\(model.revision)|\(peak)" }

    private var previewKey: String {
        model.requestKey(mode: mode, peak: peak)
    }

    private var exportSettingsKey: String {
        "\(quality)|\(dpiText)|\(sizeAxis)|\(pixelsText)|\(targetKiBText)|\(hdrColorSpace)|\(sdrColorSpace)|\(sdrMapping)"
    }

    private func exportOptions() throws -> ExportOptions {
        func integer(_ text: String) throws -> Int? {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { return nil }
            guard let result = Int(value), result > 0 else { throw ImageFailure.invalidOptions }
            return result
        }
        let pixels = sizeAxis == "原尺寸" ? nil : try integer(pixelsText)
        guard sizeAxis == "原尺寸" || pixels != nil else { throw ImageFailure.invalidOptions }
        let kib = try integer(targetKiBText)
        guard kib.map({ $0 <= Int.max / 1024 }) ?? true else { throw ImageFailure.invalidOptions }
        return ExportOptions(quality: quality, dpi: try integer(dpiText),
            width: sizeAxis == "宽度" ? pixels : nil, height: sizeAxis == "高度" ? pixels : nil,
            targetBytes: kib.map { $0 * 1024 }, hdrColorSpace: hdrColorSpace,
            sdrColorSpace: sdrColorSpace, sdrMapping: sdrMapping)
    }

    private var exportControls: some View {
        GroupBox("导出参数") {
            VStack(alignment: .leading, spacing: 12) {
                Text("JPEG / HEIC 质量上限：\(Int(quality * 100))%")
                Slider(value: $quality, in: 0...1, step: 0.01)
                    .accessibilityLabel("压缩质量上限")
                TextField("DPI（可选，1～2400）", text: $dpiText).keyboardType(.numberPad)
                    .accessibilityLabel("导出 DPI")
                Picker("像素尺寸", selection: $sizeAxis) {
                    ForEach(["原尺寸", "宽度", "高度"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented)
                if sizeAxis != "原尺寸" {
                    TextField("目标\(sizeAxis)（像素）", text: $pixelsText).keyboardType(.numberPad)
                }
                TextField("文件上限 KiB（可选）", text: $targetKiBText).keyboardType(.numberPad)
                    .accessibilityLabel("目标文件大小 KiB")
                Text("尺寸保持比例；DPI 只修改密度。目标体积仅搜索质量，不自动缩小像素；无损格式只校验体积上限。")
                    .font(.caption).foregroundStyle(.secondary)
            }.textFieldStyle(.roundedBorder)
        }.disabled(model.busy)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("看见高光里的层次")
                        .font(.title2.weight(.semibold))
                    Text("本地图像 · HDR / SDR · PQ 导出")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        PhotosPicker(selection: $photo, matching: .images,
                                     preferredItemEncoding: .current) {
                            Label("从相册选择", systemImage: "photo")
                        }
                        Button { showImporter = true } label: {
                            Label("导入文件", systemImage: "folder")
                        }
                    }
                    .buttonStyle(.bordered).disabled(model.busy)

                    if let info = model.info {
                        Picker("查看", selection: $mode) {
                            ForEach(ImageMode.allCases.filter { $0 != .gainMap || info.hasGainMap }, id: \.self) { item in
                                Text(item.rawValue).tag(item)
                                    .disabled(item == .gainMap && !info.hasGainMap)
                            }
                        }.pickerStyle(.segmented).disabled(model.busy)
                        HDRPreview(image: model.previewRequestKey == previewKey ? model.preview : nil, mode: mode)
                            .frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 16))
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                if model.previewRequestKey == previewKey && model.preview != nil { showFullScreen = true }
                            }
                            .accessibilityLabel("\(mode.rawValue) 图像预览")
                            .accessibilityAction(named: "全屏显示") { showFullScreen = true }
                        Text("双击图像全屏查看").font(.caption).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(info.width) × \(info.height) · \(info.isLUT ? "LUT 增强结果" : (info.isComposed ? "HDR 合成结果" : (info.isHDR ? "HDR 源图" : "SDR 源图")))")
                            Text("\(info.isComposed || info.isLUT ? "源文件格式" : "实际文件格式")：\(info.typeName) · \(info.dynamicRangeLabel)")
                            Text(info.isComposed ? "当前为合成灰度增益图，尚未写入文件。" :
                                 (info.hasGainMap ? "含系统可读取的 GainMap" : "未读取到 GainMap"))
                            if mode == .sdr {
                                Text(info.isLUT ? "LUT 增强后的 SDR 表观" : (info.isComposed ? "原图 SDR 基础表观（未应用合成增益）" :
                                     (info.hasGainMap ? "SDR 基础表观（HDR 基图时由系统映射）" : "SDR 表观（HDR 源图经系统色调映射）"))
                                )
                            }
                            TimelineView(.periodic(from: .now, by: 2)) { _ in
                                Text("当前显示余量 \(UIScreen.main.currentEDRHeadroom, specifier: "%.2f")×")
                                if UIScreen.main.currentEDRHeadroom <= 1.01 {
                                    Text("当前显示余量为 SDR，系统将映射高光；导出保留 HDR 数据。")
                                }
                            }
                            if mode == .hdr, model.previewRequestKey == previewKey, let preview = model.preview {
                                Text("预览内容余量 \(Double(preview.contentHeadroom), specifier: "%.2f")×")
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                        GroupBox("SDR · 3D LUT 增强") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("输入sRGB码值 → 线性BT.2020输出；其他编码的LUT不适用。")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(info.lutName.map { "\($0) · \(info.lutDimension ?? 0)³ · \(info.isLUT ? "已应用" : "未应用")" } ?? "尚未加载LUT")
                                    .font(.caption)
                                HStack {
                                    Button("导入并应用 .cube") { showLUTImporter = true }
                                    Button("使用提供的LUT") {
                                        guard let url = Bundle.main.url(forResource: "bt709_to_bt2020_catd65_linear", withExtension: "cube")
                                        else { model.report(LUTFailure.invalid("内置示例资源缺失。")); return }
                                        Task { mode = .sdr; await model.loadLUT(url); if model.info?.isLUT == true { sdrColorSpace = .bt2020 } }
                                    }
                                }.buttonStyle(.bordered)
                                HStack {
                                    Button("重新应用LUT") { Task { mode = .sdr; await model.applyLUT(enabled: true) } }
                                        .disabled(info.lutName == nil)
                                    Button("恢复原图") { Task { mode = .sdr; await model.applyLUT(enabled: false) } }
                                        .disabled(!info.isLUT)
                                }.buttonStyle(.bordered)
                                Text("每次从原图应用，不累积；预览、分析及SDR导出使用增强结果。原图与增强图按相同像素网格、当前峰值比较；灰度GainMap合成单独应用。")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("分布取编码前增强结果；SDR预览及导出受目标色域和亮度范围限制。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(model.busy || info.isHDR)
                        GroupBox("SDR + 灰度 GainMap 合成") {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("灰度来源", selection: $useOtherGray) {
                                    Text("当前源图").tag(false)
                                    Text("另一张图").tag(true)
                                }.pickerStyle(.segmented)
                                if useOtherGray {
                                    HStack {
                                        PhotosPicker("选择灰度来源照片", selection: $grayPhoto,
                                            matching: .images, preferredItemEncoding: .current)
                                        Button("选择灰度来源文件") { showGrayImporter = true }
                                    }.buttonStyle(.bordered)
                                    Text(model.grayName ?? "尚未选择来源图").font(.caption)
                                }
                                Text("最大增益 \(maximumGain, specifier: "%.2f")×")
                                Slider(value: $maximumGain, in: 1...16).accessibilityLabel("灰度最大增益")
                                Text("取源图 SDR 表观的线性亮度；黑色不增强，白色为最大增益。另一张图等比居中裁切；合成使用原始 SDR 基图，不叠加上次合成。")
                                    .font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("应用合成") {
                                        Task { mode = .hdr; await model.compose(useOtherImage: useOtherGray, maximumGain: maximumGain) }
                                    }.disabled(useOtherGray && model.grayURL == nil)
                                    Button("恢复源图") {
                                        Task { mode = .hdr; await model.compose(useOtherImage: false, maximumGain: nil) }
                                    }
                                }.buttonStyle(.bordered)
                            }
                        }.disabled(model.busy)
                        GroupBox("SDR → HDR 高光增强") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("输出峰值")
                                    Spacer()
                                    Text("\(Int(peak)) nit").monospacedDigit()
                                }
                                Slider(value: $peak, in: 203...600, step: 1)
                                    .accessibilityLabel("HDR 输出峰值")
                                Text(info.isComposed ? "当前为合成 HDR；请在上方调整合成增益，或恢复源图。" :
                                     (info.isHDR ? "源图已有 HDR，保留其原动态范围。" :
                                      "203 nit 保持原映射；提高峰值逐渐增强亮区。"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(info.isHDR || model.busy)
                        if model.histogramRequestKey == previewKey, let stats = model.histograms {
                            HistogramPanel(stats: stats, channel: $histogramChannel, logarithmic: $logarithmicCounts)
                        } else if let error = model.histogramError {
                            Text("直方图暂不可用：\(error)").font(.caption).foregroundStyle(.secondary)
                        } else {
                            ProgressView("正在更新采样统计…")
                        }
                        Toggle("显示像素色域分布", isOn: $showDistribution)
                        if showDistribution {
                            Group {
                                if model.distributionKey == distributionKey, let data = model.distribution {
                                    PixelVisualizationPanel(distribution: data, enhancedDistribution: model.enhancedDistribution,
                                        analysisID: distributionKey)
                                } else if let error = model.distributionError {
                                    Text("像素分布暂不可用：\(error)").font(.caption)
                                } else { ProgressView("正在计算像素色域分布…") }
                            }.task(id: distributionKey) {
                                await model.updateDistribution(peak: peak, key: distributionKey)
                            }
                        }
                        exportControls
                        GroupBox("导出 HDR 结果") {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("文件格式", selection: $format) {
                                    ForEach(ExportFormat.allCases, id: \.self) { item in
                                        Text(item.rawValue).tag(item)
                                    }
                                }.pickerStyle(.menu)
                                Picker("HDR 色域", selection: $hdrColorSpace) {
                                    ForEach(HDRColorSpace.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }.pickerStyle(.segmented)
                                Text(format.isGainMap ? "SDR 基图 + ISO GainMap · 透明铺白底" : "16 位 · \(hdrColorSpace.rawValue) 原色 · PQ")
                                    .font(.caption).foregroundStyle(.secondary)
                                if format.isGainMap {
                                    Text("结果需超过 SDR 参考白，系统才会写出 GainMap；无增益时可导出普通 SDR 或 PQ。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if Double(info.sourceHeadroom) * 203 > 10000.1 {
                                    Text("系统解码的 RGB 分量超出 PQ 范围，导出将按 0～10000 nit 的编码边界裁切。")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                                Button("生成 \(format.isGainMap ? "" : "PQ ")\(format.rawValue)") {
                                    Task {
                                        do { await model.export(peak: peak, format: format, options: try exportOptions()) }
                                        catch { model.report(error) }
                                    }
                                }.buttonStyle(.borderedProminent).disabled(model.busy)
                                if let url = model.exportURL {
                                    ShareLink(item: url) {
                                        Label("保存或分享已生成文件", systemImage: "square.and.arrow.up")
                                    }
                                }
                            }.disabled(model.busy)
                        }
                        Text("上方导出使用当前 HDR 结果。实际屏幕亮度由系统管理。")
                            .font(.footnote).foregroundStyle(.secondary)
                        GroupBox("普通格式转换（SDR）") {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("输出格式", selection: $sdrFormat) {
                                    ForEach(SDRFormat.supported, id: \.self) { item in
                                        Text(item.rawValue).tag(item)
                                    }
                                }.pickerStyle(.segmented).disabled(model.busy)
                                Picker("SDR 色域", selection: $sdrColorSpace) {
                                    ForEach(SDRColorSpace.allCases.filter { sdrFormat != .bmp || $0 == .sRGB }, id: \.self) { Text($0.rawValue).tag($0) }
                                }.pickerStyle(.segmented)
                                if sdrFormat == .bmp {
                                    Text("系统 BMP 编解码器不保留宽色域 ICC；BMP 仅提供 sRGB，P3/Adobe RGB 请选 PNG、JPEG 或 HEIC。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Picker("色域映射", selection: $sdrMapping) {
                                    ForEach(SDRMapping.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }.pickerStyle(.segmented)
                                Text(sdrMapping == .xyz ? "等 XYZ：保持色度转换，目标范围外裁切。" : "RGB 直通：保留源 SDR 编码值，更换色彩空间解释，颜色外观会改变。")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("8 位 \(sdrColorSpace.rawValue) · \(info.isLUT ? "LUT增强SDR表观" : "源图SDR表观") · 使用上方导出参数")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(sdrFormat.keepsAlpha ? "PNG 保留透明区域。" : "透明区域铺白底。")
                                    .font(.caption).foregroundStyle(.secondary)
                                if info.isHDR {
                                    Text("转换为 SDR；保留 HDR 请使用上方 HDR 导出。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Button("生成 SDR \(sdrFormat.rawValue)") {
                                    Task {
                                        do { await model.exportSDR(format: sdrFormat, options: try exportOptions()) }
                                        catch { model.report(error) }
                                    }
                                }.buttonStyle(.borderedProminent).disabled(model.busy)
                                if let url = model.sdrExportURL {
                                    ShareLink(item: url) {
                                        Label("保存或分享 SDR 文件", systemImage: "square.and.arrow.up")
                                    }
                                }
                            }.disabled(model.busy)
                        }
                    } else {
                        ContentUnavailableView("导入一张原始图片", systemImage: "photo.badge.plus",
                            description: Text("选择 HEIC、JPEG、PNG、BMP 或 TIFF，查看与转换图像。"))
                    }
                    if model.busy { ProgressView("正在处理…") }
                }.padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("HDR Image Lab")
            .fullScreenCover(isPresented: $showFullScreen) {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    HDRPreview(image: model.previewRequestKey == previewKey ? model.preview : nil, mode: mode)
                        .ignoresSafeArea().contentShape(Rectangle())
                        .onTapGesture(count: 2) { showFullScreen = false }
                        .accessibilityLabel("全屏 \(mode.rawValue) 图像")
                    Button { showFullScreen = false } label: {
                        Image(systemName: "xmark.circle.fill").font(.largeTitle)
                            .foregroundStyle(.white).padding()
                    }.accessibilityLabel("退出全屏")
                }.statusBarHidden()
            }
            .fileImporter(isPresented: $showGrayImporter, allowedContentTypes: [.image]) { result in
                switch result {
                case .success(let url): model.loadGray(url)
                case .failure(let error): model.report(error)
                }
            }
            .fileImporter(isPresented: $showLUTImporter, allowedContentTypes: [.data]) { result in
                switch result {
                case .success(let url):
                    Task { mode = .sdr; await model.loadLUT(url); if model.info?.isLUT == true { sdrColorSpace = .bt2020 } }
                case .failure(let error): model.report(error)
                }
            }
            .onChange(of: grayPhoto) { _, item in
                guard let item else { return }
                Task { await model.loadGrayPhoto(item); if grayPhoto == item { grayPhoto = nil } }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image]) { result in
                switch result {
                case .success(let url): Task { mode = .hdr; await model.load(url) }
                case .failure(let error): model.report(error)
                }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    mode = .hdr
                    await model.loadPhoto(item)
                    if photo == item { photo = nil }
                }
            }
            .onChange(of: format) { _, _ in model.exportURL = nil }
            .onChange(of: peak) { _, _ in model.exportURL = nil }
            .onChange(of: sdrFormat) { _, value in
                model.sdrExportURL = nil
                if value == .bmp { sdrColorSpace = .sRGB }
            }
            .onChange(of: exportSettingsKey) { _, _ in
                model.exportURL = nil
                model.sdrExportURL = nil
            }
            .task(id: previewKey) {
                await model.updatePreview(mode: mode, peak: peak)
            }
            .alert("处理提示", isPresented: Binding(get: { model.error != nil },
                set: { if !$0 { model.error = nil } })) {
                Button("好", role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
        }
    }
}

private struct HistogramPanel: View {
    let stats: HistogramStats
    @Binding var channel: HistogramChannel
    @Binding var logarithmic: Bool

    private var color: Color {
        switch channel {
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        case .luminance: return .primary
        case .hue: return .purple
        case .saturation: return .orange
        case .value: return .gray
        }
    }

    var body: some View {
        let distribution = stats.channels[channel.rawValue]!
        let maximum = max(1, distribution.bins.max() ?? 0)
        GroupBox("直方图") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("通道", selection: $channel) {
                    ForEach(HistogramChannel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Text(channel.usesHDR ? stats.hdrDomain : stats.hsvDomain)
                    .font(.caption).foregroundStyle(.secondary)
                Canvas { context, size in
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height))
                    for (index, count) in distribution.bins.enumerated() {
                        let fraction = logarithmic ? log1p(Double(count)) / log1p(Double(maximum))
                            : Double(count) / Double(maximum)
                        let x = Double(index) / Double(distribution.bins.count - 1) * size.width
                        path.addLine(to: CGPoint(x: x, y: (1 - fraction) * size.height))
                    }
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.closeSubpath()
                    context.fill(path, with: .color(color.opacity(0.45)))
                    context.stroke(path, with: .color(color), lineWidth: 1)
                }
                .frame(height: 150)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("\(channel.rawValue) 直方图，\(distribution.bins.reduce(0, +)) 个已分箱样本")
                HStack {
                    Text("\(distribution.lowerBound, specifier: "%.1f")")
                    Spacer()
                    Text("\(distribution.upperBound, specifier: "%.1f") \(channel.unit)")
                }.font(.caption).monospacedDigit()
                Toggle("计数使用对数纵轴", isOn: $logarithmic).font(.caption)
                let sampled = stats.originalWidth != stats.sampledWidth || stats.originalHeight != stats.sampledHeight
                Text("\(sampled ? "采样估计" : "全像素统计")：\(stats.sampledWidth) × \(stats.sampledHeight)，原图 \(stats.originalWidth) × \(stats.originalHeight)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("有效样本：HDR \(stats.hdrPixelCount)，HSV \(stats.hsvPixelCount)；透明排除 \(channel.usesHDR ? stats.transparentHDRCount : stats.transparentSDRCount)")
                    .font(.caption).foregroundStyle(.secondary)
                if distribution.undefinedCount > 0 {
                    Text("无定义色相：\(distribution.undefinedCount)（无彩色，包括黑白灰，不记入 H 分箱）")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if distribution.underflowCount + distribution.overflowCount > 0 {
                    Text("范围外样本：下界 \(distribution.underflowCount)，上界 \(distribution.overflowCount)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if stats.invalidHDRCount > 0 {
                    Text("无效 HDR 样本排除：\(stats.invalidHDRCount)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
