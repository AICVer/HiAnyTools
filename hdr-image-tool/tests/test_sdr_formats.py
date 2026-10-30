"""R1 普通格式转换：通过生产 Swift 引擎验证读写、透明与方向。"""

import numpy as np
from PIL import Image
import pytest

from test_hdr_engine import imageDirectory, probe, sdr


FORMATS = ["JPEG", "HEIC", "PNG", "BMP"]


def test_system_has_requested_encoders(probe):
    assert set(probe("formats")["formats"]) == set(FORMATS)


@pytest.mark.parametrize("sourceFormat", FORMATS)
@pytest.mark.parametrize("targetFormat", FORMATS)
def test_all_four_formats_convert_between_each_other(probe, sdr, imageDirectory, sourceFormat, targetFormat):
    source = probe("sdr-export", sdr, sourceFormat, imageDirectory)["path"]
    target = probe("sdr-export", source, targetFormat, imageDirectory)["path"]
    info = probe("inspect", target)
    assert (info["width"], info["height"], info["depth"]) == (5, 1, 8)
    assert not info["isHDR"] and not info["gainMap"]
    gray = np.asarray(info["linear"]).reshape(-1, 4)[:, :3].mean(axis=1)
    assert gray[0] < 0.03 and gray[-1] > 0.96
    assert np.all(np.diff(gray) > 0)
    assert abs(gray[1] - 0.18) < 0.025


@pytest.mark.parametrize("format", FORMATS)
def test_transparency_kept_for_png_or_composited_white(probe, imageDirectory, format):
    source = imageDirectory / "alpha.png"
    image = Image.new("RGBA", (128, 64))
    image.paste((255, 0, 0, 0), (0, 0, 64, 64))
    image.paste((255, 0, 0, 255), (64, 0, 128, 64))
    image.save(source)
    target = probe("sdr-export", source, format, imageDirectory)["path"]
    pixels = np.asarray(probe("inspect", target)["linear"]).reshape(64, 128, 4)
    if format == "PNG":
        assert pixels[32, 32, 3] == 0
    else:
        np.testing.assert_allclose(pixels[32, 32], [1, 1, 1, 1], atol=0.025)
    assert pixels[32, 96, 0] > pixels[32, 96, 1] + 0.4
    assert pixels[32, 96, 3] > 0.99


@pytest.mark.parametrize("format", FORMATS)
def test_orientation_and_original_bytes_preserved(probe, imageDirectory, format):
    source = imageDirectory / "rotated.jpg"
    exif = Image.Exif()
    exif[274] = 6
    Image.new("RGB", (80, 48), "red").save(source, exif=exif)
    before = source.read_bytes()
    target = probe("sdr-export", source, format, imageDirectory)["path"]
    info = probe("inspect", target)
    assert (info["width"], info["height"]) == (48, 80)
    assert source.read_bytes() == before


@pytest.mark.parametrize("format", FORMATS)
def test_hdr_source_exports_explicit_sdr(probe, imageDirectory, format):
    source = imageDirectory / "hdr.png"
    probe("hdrfixture", source)
    target = probe("sdr-export", source, format, imageDirectory)["path"]
    info = probe("inspect", target)
    assert info["depth"] == 8 and not info["isHDR"] and not info["gainMap"]
    pixels = np.asarray(info["linear"]).reshape(-1, 4)
    assert np.isfinite(pixels).all()
    assert pixels[:, :3].max() <= 1.02


def test_destination_failure_preserves_existing_file(probe, sdr, imageDirectory):
    path = imageDirectory / "existing.txt"
    path.write_text("keep", encoding="utf-8")
    probe("sdr-export", sdr, "JPEG", path, success=False)
    assert path.read_text(encoding="utf-8") == "keep"
