"""在本机将图片逐张转换为 PDF。"""

import argparse
import io
import logging
import os
from pathlib import Path
import re
import sys
import tempfile
from dataclasses import dataclass
from typing import Callable, Iterable

import fitz
from PIL import Image, ImageOps


SUPPORTED_SUFFIXES = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".tif", ".tiff"}
logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ConversionResult:
    """记录单张图片的输出路径、状态和提示。"""

    source: Path
    target: Path
    status: str
    message: str


def collectImages(paths: Iterable[Path]) -> list[Path]:
    """收集文件或文件夹当前层的图片，去重并按文件名自然排序。"""
    imagePaths = set()
    for path in paths:
        path = Path(path).expanduser().resolve()
        candidates = path.iterdir() if path.is_dir() else [path]
        imagePaths.update(
            item.resolve() for item in candidates
            if item.is_file() and item.suffix.lower() in SUPPORTED_SUFFIXES
        )
    return sorted(imagePaths, key=lambda path: (
        [int(part) if part.isdigit() else part.casefold()
         for part in re.split(r"(\d+)", path.name)], str(path)
    ))


def convertImage(source: Path, outputDir: Path) -> Path:
    """生成同名单页 PDF，保留像素尺寸及比例，拒绝覆盖已有文件。"""
    source, outputDir = Path(source), Path(outputDir)
    if source.suffix.lower() not in SUPPORTED_SUFFIXES:
        raise ValueError("不支持该图片格式")
    target = outputDir / f"{source.stem}.pdf"
    if target.exists():
        raise FileExistsError(f"目标已存在：{target.name}")
    with Image.open(source) as original:
        if getattr(original, "n_frames", 1) != 1:
            raise ValueError("暂不支持多帧图片或多页 TIFF，请先拆分")
        if original.mode not in {"1", "L", "LA", "P", "RGB", "RGBA", "CMYK"}:
            raise ValueError("暂不支持高位深/HDR 图片，请先转换为普通 SDR 图片")
        original.load()
        orientation = original.getexif().get(274, 1)
        with ImageOps.exif_transpose(original) as oriented:
            width, height = oriented.size
            # 普通 JPEG 直接嵌入原始压缩数据，避免重复有损编码。
            if original.format == "JPEG" and orientation == 1 and original.mode in {"RGB", "L"}:
                imageBytes = source.read_bytes()
            else:
                with oriented.convert("RGBA") as rgba:
                    with Image.new("RGB", rgba.size, "white") as flattened:
                        flattened.paste(rgba, mask=rgba.getchannel("A"))
                        buffer = io.BytesIO()
                        flattened.save(buffer, format="PNG")
                        imageBytes = buffer.getvalue()
    outputDir.mkdir(parents=True, exist_ok=True)
    with fitz.open() as document:
        # 150 DPI 只定义 PDF 纸面尺寸，不缩放或裁切原图像素。
        page = document.new_page(width=width * 72 / 150, height=height * 72 / 150)
        page.insert_image(page.rect, stream=imageBytes)
        with tempfile.NamedTemporaryFile(dir=outputDir, suffix=".tmp", delete=False) as tempFile:
            tempPath = Path(tempFile.name)
        try:
            document.save(str(tempPath), deflate=True)
            # 同目录硬链接保证完整写入后才出现结果，且不会覆盖重名文件。
            os.link(tempPath, target)
        finally:
            tempPath.unlink(missing_ok=True)
    logger.info("转换完成：%s -> %s", source, target)
    return target


def convertBatch(
    paths: Iterable[Path],
    outputDir: Path,
    onResult: Callable[[ConversionResult], None] | None = None,
) -> list[ConversionResult]:
    """逐张转换图片，记录失败与跳过项，并在每项结束后通知界面。"""
    results = []
    for source in paths:
        source = Path(source)
        target = Path(outputDir) / f"{source.stem}.pdf"
        try:
            convertImage(source, outputDir)
            result = ConversionResult(source, target, "success", "转换成功")
        except FileExistsError as error:
            if target.exists():
                result = ConversionResult(source, target, "skipped", "同名 PDF 已存在，已跳过")
            else:
                logger.warning("输出目录不可用：%s：%s", outputDir, error)
                result = ConversionResult(source, target, "failed", str(error))
        except Exception as error:
            logger.warning("转换失败：%s：%s", source, error)
            result = ConversionResult(source, target, "failed", str(error))
        results.append(result)
        if onResult is not None:
            onResult(result)
    return results


def main(argv: list[str] | None = None) -> int:
    """解析图形界面启动参数并配置运行日志。"""
    parser = argparse.ArgumentParser(description="批量图像转 PDF（每张图片一个 PDF）")
    parser.add_argument("--log-level", choices=["DEBUG", "INFO", "WARNING", "ERROR"], default="INFO")
    subparsers = parser.add_subparsers(dest="command")
    subparsers.add_parser("gui", help="打开本地图形窗口（默认）")
    args = parser.parse_args(argv)
    logging.basicConfig(level=args.log_level, format="%(levelname)s %(message)s")
    from image_to_pdf_gui import launchGui
    launchGui()
    return 0


if __name__ == "__main__":
    sys.exit(main())
