"""R2 蓝军功能测试：密度、尺寸、质量与字节上限。"""

import json
from pathlib import Path

import numpy as np
from PIL import Image
import pytest

from test_hdr_engine import imageDirectory, probe, sdr


@pytest.mark.parametrize("format", ["JPEG", "HEIC", "PNG", "BMP"])
def test_sdr_resize_and_dpi(probe, sdr, imageDirectory, format):
    path = probe("sdr-options", sdr, format, json.dumps({"width": 40, "dpi": 300}), imageDirectory)["path"]
    info = probe("meta", path)
    assert (info["orientedWidth"], info["orientedHeight"]) == (40, 8)
    assert abs(info["dpiWidth"] - 300) < 1
    assert abs(info["dpiHeight"] - 300) < 1


@pytest.mark.parametrize("format", ["PNG", "TIFF"])
def test_hdr_resize_dpi_and_encoding(probe, sdr, imageDirectory, format):
    path = probe("hdr-options", sdr, format, 600,
                 json.dumps({"height": 6, "dpi": 144}), imageDirectory)["path"]
    info = probe("meta", path)
    assert (info["orientedWidth"], info["orientedHeight"], info["depth"]) == (30, 6, 16)
    assert abs(info["dpiWidth"] - 144) < 1
    assert "2100_PQ" in info["colorSpace"]


@pytest.mark.parametrize("format", ["JPEG", "HEIC", "PNG", "BMP"])
def test_dpi_alone_keeps_pixel_size(probe, sdr, imageDirectory, format):
    path = probe("sdr-options", sdr, format, '{"dpi":240}', imageDirectory)["path"]
    info = probe("meta", path)
    assert (info["orientedWidth"], info["orientedHeight"]) == (5, 1)


@pytest.mark.parametrize("options", [
    {"quality": -0.1}, {"quality": 1.1}, {"dpi": 0}, {"dpi": 2401},
    {"width": 0}, {"height": -1}, {"width": 10, "height": 20},
    {"targetBytes": 0}, {"targetBytes": -1}, {"width": 9223372036854775807},
])
def test_invalid_options_rejected_without_result(probe, sdr, imageDirectory, options):
    before = set(imageDirectory.iterdir())
    probe("sdr-options", sdr, "PNG", json.dumps(options), imageDirectory, success=False)
    assert set(imageDirectory.iterdir()) == before


@pytest.mark.parametrize("format", ["JPEG", "HEIC"])
def test_quality_search_hits_budget_without_resizing(probe, imageDirectory, format):
    source = imageDirectory / "noise.png"
    pixels = np.random.default_rng(42).integers(0, 256, (256, 256, 3), dtype=np.uint8)
    Image.fromarray(pixels).save(source)
    low = Path(probe("sdr-options", source, format, '{"quality":0}', imageDirectory)["path"])
    high = Path(probe("sdr-options", source, format, '{"quality":1}', imageDirectory)["path"])
    assert low.stat().st_size < high.stat().st_size
    budget = (low.stat().st_size + high.stat().st_size) // 2
    result = Path(probe("sdr-options", source, format,
        json.dumps({"quality": 1, "targetBytes": budget, "dpi": 300}), imageDirectory)["path"])
    assert result.stat().st_size <= budget
    info = probe("meta", result)
    assert (info["orientedWidth"], info["orientedHeight"]) == (256, 256)


@pytest.mark.parametrize("format", ["JPEG", "HEIC", "PNG", "BMP"])
def test_impossible_budget_is_explicit_and_no_file(probe, sdr, imageDirectory, format):
    before = set(imageDirectory.iterdir())
    message = probe("sdr-options", sdr, format, '{"targetBytes":1}', imageDirectory, success=False)
    assert "无法达到" in message
    assert set(imageDirectory.iterdir()) == before


@pytest.mark.parametrize("format", ["PNG", "TIFF"])
def test_hdr_budget_is_checked(probe, sdr, imageDirectory, format):
    probe("hdr-options", sdr, format, 600, '{"targetBytes":1}', imageDirectory, success=False)


def test_aspect_ratio_rounded_to_pixel(probe, imageDirectory):
    source = imageDirectory / "rectangle.png"
    Image.new("RGB", (70, 40), "blue").save(source)
    path = probe("sdr-options", source, "PNG", '{"width":37}', imageDirectory)["path"]
    info = probe("meta", path)
    assert (info["orientedWidth"], info["orientedHeight"]) == (37, 21)
