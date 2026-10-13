"""批量图像转 PDF 的本地图形窗口。"""

from pathlib import Path
from queue import Empty, Queue
from threading import Thread
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from image_to_pdf import ConversionResult, collectImages, convertBatch


class ConverterApp:
    """选择图片和输出目录，并在后台执行转换。"""

    def __init__(self, root: tk.Tk) -> None:
        """构建窗口并初始化文件列表。"""
        self.root = root
        self.paths: list[Path] = []
        self.events: Queue = Queue()
        self.busy = False
        self.resultCount = 0
        self.counts = {"success": 0, "skipped": 0, "failed": 0}
        self.outputDir = tk.StringVar(value=str(Path(__file__).parent / "output" / "pdf"))
        self.status = tk.StringVar(value="请添加图片或选择文件夹。")
        root.title("批量图像转 PDF")
        root.geometry("840x550")
        root.minsize(680, 450)
        root.protocol("WM_DELETE_WINDOW", self.closeWindow)
        panel = ttk.Frame(root, padding=20)
        panel.pack(fill="both", expand=True)
        ttk.Label(panel, text="批量图像转 PDF", font=("Arial", 22, "bold")).pack(anchor="w")
        ttk.Label(panel, text="每张图片生成一个同名 PDF · 本机处理 · 保留比例").pack(anchor="w", pady=(6, 16))
        toolbar = ttk.Frame(panel)
        toolbar.pack(fill="x")
        self.controls = []
        for label, command in [("添加图片…", self.chooseFiles), ("添加文件夹…", self.chooseFolder), ("清空列表", self.clearFiles)]:
            button = ttk.Button(toolbar, text=label, command=command)
            button.pack(side="left", padx=(0, 8))
            self.controls.append(button)
        tableFrame = ttk.Frame(panel)
        tableFrame.pack(fill="both", expand=True, pady=12)
        self.table = ttk.Treeview(tableFrame, columns=("name", "result"), show="headings", selectmode="browse")
        self.table.heading("name", text="图片名称")
        self.table.heading("result", text="转换结果")
        self.table.column("name", width=380)
        self.table.column("result", width=340)
        scrollbar = ttk.Scrollbar(tableFrame, orient="vertical", command=self.table.yview)
        self.table.configure(yscrollcommand=scrollbar.set)
        scrollbar.pack(side="right", fill="y")
        self.table.pack(fill="both", expand=True)
        outputRow = ttk.Frame(panel)
        outputRow.pack(fill="x")
        ttk.Label(outputRow, text="保存到：").pack(side="left")
        outputEntry = ttk.Entry(outputRow, textvariable=self.outputDir)
        outputEntry.pack(side="left", fill="x", expand=True, padx=8)
        browseButton = ttk.Button(outputRow, text="选择目录…", command=self.chooseOutput)
        browseButton.pack(side="right")
        self.controls.extend([outputEntry, browseButton])
        ttk.Label(panel, text="支持 JPG / PNG / BMP / WebP / 单页 TIFF；文件夹不包含子目录；重名跳过。", wraplength=760).pack(anchor="w", pady=(10, 8))
        self.progress = ttk.Progressbar(panel, mode="determinate")
        self.progress.pack(fill="x", pady=6)
        ttk.Label(panel, textvariable=self.status, wraplength=760).pack(anchor="w", pady=5)
        self.startButton = ttk.Button(panel, text="开始转换", command=self.startConversion)
        self.startButton.pack(anchor="e", pady=(6, 0))
        self.controls.append(self.startButton)

    def addPaths(self, paths: list[Path]) -> None:
        """添加图片并显示去重后的待转换列表。"""
        try:
            self.paths = collectImages([*self.paths, *paths])
        except OSError as error:
            messagebox.showerror("读取失败", str(error), parent=self.root)
            return
        self.table.delete(*self.table.get_children())
        for index, path in enumerate(self.paths):
            self.table.insert("", "end", iid=str(index), values=(path.name, "等待转换"))
        self.progress["value"] = 0
        self.status.set(f"已选择 {len(self.paths)} 张图片。")

    def chooseFiles(self) -> None:
        """通过文件选择框添加多张图片。"""
        selected = filedialog.askopenfilenames(parent=self.root, title="选择图片", filetypes=[
            ("图片", "*.jpg *.jpeg *.png *.bmp *.webp *.tif *.tiff *.JPG *.JPEG *.PNG *.BMP *.WEBP *.TIF *.TIFF"),
            ("所有文件", "*"),
        ])
        if selected:
            self.addPaths([Path(path) for path in selected])

    def chooseFolder(self) -> None:
        """选择文件夹并添加当前层级图片。"""
        selected = filedialog.askdirectory(parent=self.root, title="选择图片文件夹")
        if selected:
            self.addPaths([Path(selected)])

    def chooseOutput(self) -> None:
        """选择 PDF 保存目录。"""
        selected = filedialog.askdirectory(parent=self.root, title="选择 PDF 保存目录")
        if selected:
            self.outputDir.set(selected)

    def clearFiles(self) -> None:
        """清空待转换列表和进度。"""
        self.paths.clear()
        self.table.delete(*self.table.get_children())
        self.progress["value"] = 0
        self.status.set("请添加图片或选择文件夹。")

    def startConversion(self) -> None:
        """验证输入并启动后台转换，保持界面可响应。"""
        if self.busy:
            return
        if not self.paths:
            messagebox.showwarning("尚未选择图片", "请先添加图片或文件夹。", parent=self.root)
            return
        if not self.outputDir.get().strip():
            messagebox.showwarning("尚未选择保存目录", "请选择 PDF 保存目录。", parent=self.root)
            return
        self.busy = True
        self.resultCount = 0
        self.counts = {"success": 0, "skipped": 0, "failed": 0}
        self.progress.configure(maximum=len(self.paths), value=0)
        for index, path in enumerate(self.paths):
            self.table.item(str(index), values=(path.name, "等待转换"))
        for control in self.controls:
            control.configure(state="disabled")
        self.status.set(f"正在转换 0 / {len(self.paths)}…")
        outputDir = Path(self.outputDir.get().strip()).expanduser().resolve()
        Thread(target=self.runConversion, args=(list(self.paths), outputDir), daemon=True).start()
        self.root.after(100, self.pollResults)

    def runConversion(self, paths: list[Path], outputDir: Path) -> None:
        """在工作线程处理图片，仅通过队列通知主线程。"""
        convertBatch(paths, outputDir, self.events.put)
        self.events.put(None)

    def pollResults(self) -> None:
        """在主线程更新转换结果与进度。"""
        try:
            while True:
                result: ConversionResult | None = self.events.get_nowait()
                if result is None:
                    self.busy = False
                    for control in self.controls:
                        control.configure(state="normal")
                    self.status.set(f"处理完成：成功 {self.counts['success']}，跳过 {self.counts['skipped']}，失败 {self.counts['failed']}。")
                    return
                self.table.item(str(self.resultCount), values=(result.source.name, result.message))
                self.resultCount += 1
                self.counts[result.status] += 1
                self.progress["value"] = self.resultCount
                self.status.set(f"正在转换 {self.resultCount} / {len(self.paths)}…")
        except Empty:
            self.root.after(100, self.pollResults)

    def closeWindow(self) -> None:
        """转换期间提示等待，避免中途关闭造成未完成输出。"""
        if self.busy:
            messagebox.showinfo("正在转换", "请等待当前批次处理完成后关闭窗口。", parent=self.root)
            return
        self.root.destroy()


def launchGui() -> None:
    """启动图像转 PDF 窗口。"""
    root = tk.Tk()
    ConverterApp(root)
    root.mainloop()
