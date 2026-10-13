"""转换模块的输出、错误隔离与图像语义测试。"""

from pathlib import Path
from unittest.mock import Mock

import fitz
from PIL import Image
import pytest

from image_to_pdf import collectImages, convertBatch, convertImage, main


def makeImage(path: Path, mode: str = "RGB", color: object = "red") -> Path:
    """创建小型测试图片。"""
    with Image.new(mode, (60, 40), color) as image:
        image.save(path)
    return path


def test_collect_natural_order_dedup_nonrecursive(tmp_path: Path) -> None:
    """文件夹只取当前层，忽略 PDF 并按数字顺序去重。"""
    paths = [makeImage(tmp_path / name) for name in ["10.JPG", "2.png", "1.bmp"]]
    (tmp_path / "old.pdf").write_bytes(b"pdf")
    nested = tmp_path / "nested"
    nested.mkdir()
    makeImage(nested / "hidden.jpg")
    assert [path.name for path in collectImages([tmp_path, paths[0]])] == ["1.bmp", "2.png", "10.JPG"]
    assert collectImages([tmp_path / "absent.jpg"]) == []


@pytest.mark.parametrize("suffix,mode,color", [
    ("jpg", "RGB", "red"), ("jpeg", "L", 80), ("png", "RGBA", (0, 0, 0, 0)),
    ("bmp", "RGB", "red"), ("webp", "RGB", "red"), ("tif", "L", 80),
    ("tiff", "CMYK", (0, 255, 255, 0)), ("png", "P", 0), ("png", "LA", (0, 0)),
])
def test_supported_formats(tmp_path: Path, suffix: str, mode: str, color: object) -> None:
    """支持格式生成一页 PDF，尺寸与原图比例一致。"""
    source = makeImage(tmp_path / f"中文图片.{suffix}", mode, color)
    target = convertImage(source, tmp_path / "output")
    with fitz.open(target) as document:
        assert len(document) == 1
        assert document[0].rect.width == pytest.approx(28.8)
        assert document[0].rect.height == pytest.approx(19.2)
        pixmap = document[0].get_pixmap()
        if mode in {"RGBA", "LA"}:
            assert pixmap.pixel(5, 5) == (255, 255, 255)
        if suffix == "jpg":
            imageRef = document[0].get_images()[0][0]
            assert document.extract_image(imageRef)["image"] == source.read_bytes()


def test_exif_orientation(tmp_path: Path) -> None:
    """横向像素带旋转 EXIF 时，输出纸面和像素正确旋转。"""
    source = tmp_path / "rotated.jpg"
    with Image.new("RGB", (60, 40), "red") as image:
        image.paste("blue", (30, 0, 60, 40))
        exif = Image.Exif()
        exif[274] = 6
        image.save(source, exif=exif)
    target = convertImage(source, tmp_path / "output")
    with fitz.open(target) as document:
        assert document[0].rect.height / document[0].rect.width == pytest.approx(1.5)
        pixmap = document[0].get_pixmap()
        assert pixmap.pixel(5, 5)[0] > 200
        assert pixmap.pixel(5, pixmap.height - 5)[2] > 200


def test_existing_output_untouched(tmp_path: Path) -> None:
    """遇到已有目标，不覆盖它的内容。"""
    source = makeImage(tmp_path / "existing.jpg")
    target = tmp_path / "existing.pdf"
    target.write_bytes(b"keep me")
    with pytest.raises(FileExistsError):
        convertImage(source, tmp_path)
    assert target.read_bytes() == b"keep me"


@pytest.mark.parametrize("kind", ["broken", "unsupported", "multipage", "highdepth"])
def test_invalid_images_no_output(tmp_path: Path, kind: str) -> None:
    """不支持或损坏的图片不能留下伪成功结果。"""
    source = tmp_path / "image.png"
    if kind == "broken":
        source.write_bytes(b"not an image")
    elif kind == "unsupported":
        source = tmp_path / "image.txt"
        source.write_text("not supported")
    elif kind == "multipage":
        source = tmp_path / "image.tiff"
        with Image.new("RGB", (20, 20)) as image:
            image.save(source, save_all=True, append_images=[image.copy()])
    else:
        with Image.new("I;16", (20, 20)) as image:
            image.save(source)
    with pytest.raises((OSError, ValueError)):
        convertImage(source, tmp_path / "output")
    assert not (tmp_path / "output" / "image.pdf").exists()


def test_batch_continues_and_reports_collision(tmp_path: Path) -> None:
    """失败不影响后续；同名不同后缀的第二张图片跳过。"""
    broken = tmp_path / "bad.png"
    broken.write_bytes(b"broken")
    paths = [broken, makeImage(tmp_path / "same.jpg"), makeImage(tmp_path / "same.png")]
    callback = Mock()
    results = convertBatch(paths, tmp_path / "out", callback)
    assert [result.status for result in results] == ["failed", "success", "skipped"]
    assert callback.call_count == 3
    assert convertBatch([], tmp_path / "empty") == []


def test_write_failure_cleans_temp(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """写出失败后清理临时文件，不残留目标 PDF。"""
    source = makeImage(tmp_path / "source.png")
    monkeypatch.setattr(fitz.Document, "save", Mock(side_effect=OSError("disk full")))
    results = convertBatch([source], tmp_path / "out")
    assert results[0].status == "failed"
    assert list((tmp_path / "out").iterdir()) == []


def test_output_path_is_file(tmp_path: Path) -> None:
    """输出目录误选为文件时返回失败原因。"""
    source = makeImage(tmp_path / "source.png")
    output = tmp_path / "output"
    output.write_text("occupied")
    assert convertBatch([source], output)[0].status == "failed"


@pytest.mark.parametrize("arguments", [[], ["gui"], ["--log-level", "DEBUG", "gui"]])
def test_main_launches_gui(arguments: list[str], monkeypatch: pytest.MonkeyPatch) -> None:
    """默认入口与 gui 子命令均启动窗口。"""
    launch = Mock()
    monkeypatch.setattr("image_to_pdf_gui.launchGui", launch)
    assert main(arguments) == 0
    launch.assert_called_once_with()
