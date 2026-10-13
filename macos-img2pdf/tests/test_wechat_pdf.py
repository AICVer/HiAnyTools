"""用独立 PDF 引擎校验小程序 JavaScript 编码器的实际输出。"""

from pathlib import Path
import subprocess

import fitz
from PIL import Image, ImageChops, ImageDraw, ImageStat
import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("width,height", [(600, 400), (400, 600), (600, 600)])
def test_javascript_pdf_roundtrip(tmp_path: Path, width: int, height: int) -> None:
    """横图、竖图、方图无裁切或倒置，且嵌入的 JPEG 数据完全一致。"""
    source = tmp_path / "input.jpg"
    target = tmp_path / "result.pdf"
    with Image.new("RGB", (width, height), "#ef6480") as image:
        draw = ImageDraw.Draw(image)
        draw.rectangle((width // 2, 0, width - 1, height // 2 - 1), fill="#f3cc51")
        draw.rectangle((0, height // 2, width // 2 - 1, height - 1), fill="#4acbbb")
        draw.rectangle((width // 2, height // 2, width - 1, height - 1), fill="#28478d")
        image.save(source, quality=95)
    script = """
const fs = require('node:fs');
const { createPdf } = require('./wechat-miniprogram/miniprogram/utils/pdf');
const bytes = createPdf(fs.readFileSync(process.argv[1]), Number(process.argv[3]), Number(process.argv[4]));
fs.writeFileSync(process.argv[2], new Uint8Array(bytes));
"""
    subprocess.run(["node", "-e", script, str(source), str(target), str(width), str(height)], cwd=PROJECT_ROOT, check=True)
    with fitz.open(target) as document:
        assert not document.is_repaired
        assert len(document) == 1
        page = document[0]
        assert page.rect.width / page.rect.height == pytest.approx(width / height)
        imageRef = page.get_images()[0][0]
        assert document.extract_image(imageRef)["image"] == source.read_bytes()
        pixmap = page.get_pixmap(matrix=fitz.Matrix(150 / 72, 150 / 72))
        assert (pixmap.width, pixmap.height) == (width, height)
        with Image.frombytes("RGB", (width, height), pixmap.samples) as rendered, Image.open(source) as original:
            difference = ImageStat.Stat(ImageChops.difference(original, rendered))
            assert max(difference.mean) < 2
        previewDir = PROJECT_ROOT / "output" / "wechat"
        previewDir.mkdir(parents=True, exist_ok=True)
        pixmap.save(str(previewDir / f"verified-{width}x{height}.png"))
        (previewDir / f"verified-{width}x{height}.pdf").write_bytes(target.read_bytes())
