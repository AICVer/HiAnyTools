"""R7/R8 蓝军：统计守恒、统计域和独立 colour-science 数值参考。"""

import colour
import numpy as np
from PIL import Image, ImageCms
import pytest

from test_hdr_engine import imageDirectory, probe


def makeColor(imageDirectory, color):
    """生成嵌入 sRGB 配置的恒定颜色样本。"""
    path = imageDirectory / "color.png"
    profile = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    Image.new("RGBA", (8, 8), color).save(path, icc_profile=profile)
    return path


def checkConservation(stats):
    """分箱、越界和无定义计数应等于各自统计域的有效样本数。"""
    assert stats["hdrPixelCount"] + stats["transparentHDRCount"] + stats["invalidHDRCount"] == stats["sampledPixelCount"]
    assert stats["hsvPixelCount"] + stats["transparentSDRCount"] == stats["sampledPixelCount"]
    for channel, distribution in stats["channels"].items():
        total = sum(distribution["bins"]) + sum(distribution[key] for key in
            ["underflowCount", "overflowCount", "undefinedCount"])
        assert total == stats["hdrPixelCount" if channel in "RGBY" else "hsvPixelCount"]


def checkBin(distribution, expected, tolerance=1):
    """独立参考值应落在同一或相邻分箱，容忍8位色彩转换量化。"""
    expectedBin = min(255, int((expected-distribution["lowerBound"]) /
        (distribution["upperBound"]-distribution["lowerBound"]) * 256))
    occupied = np.flatnonzero(distribution["bins"])
    assert occupied.size > 0
    assert np.max(abs(occupied-expectedBin)) <= tolerance


@pytest.mark.parametrize("rgb", [(255,0,0), (0,255,0), (0,0,255), (255,255,0),
                                      (0,255,255), (255,0,255), (50,100,150)])
def test_hsv_and_linear_rgb_against_colour(probe, imageDirectory, rgb):
    source = makeColor(imageDirectory, (*rgb, 255))
    stats = probe("histogram", source, 203)
    checkConservation(stats)
    encoded = np.asarray(rgb)/255
    expected = colour.RGB_to_RGB(encoded, "sRGB", "ITU-R BT.2020",
        apply_cctf_decoding=True, apply_cctf_encoding=False)
    for channel, value in zip("RGB", expected):
        checkBin(stats["channels"][channel], value)
    expectedY = expected @ colour.RGB_COLOURSPACES["ITU-R BT.2020"].matrix_RGB_to_XYZ[1] * 203
    checkBin(stats["channels"]["Y"], expectedY)
    hsv = colour.RGB_to_HSV(encoded)
    for channel, value in zip("HSV", hsv * [360,1,1]):
        checkBin(stats["channels"][channel], value)


@pytest.mark.parametrize("gray", [0, 128, 255])
def test_gray_hue_is_undefined(probe, imageDirectory, gray):
    stats = probe("histogram", makeColor(imageDirectory, (gray,gray,gray,255)), 203)
    checkConservation(stats)
    assert stats["channels"]["H"]["undefinedCount"] == 64
    assert sum(stats["channels"]["H"]["bins"]) == 0
    assert stats["channels"]["S"]["bins"][0] == 64


def test_transparent_pixels_excluded(probe, imageDirectory):
    stats = probe("histogram", makeColor(imageDirectory, (255,0,0,0)), 600)
    checkConservation(stats)
    assert stats["transparentHDRCount"] == stats["transparentSDRCount"] == 64
    assert stats["hdrPixelCount"] == stats["hsvPixelCount"] == 0


def test_partial_alpha_restores_straight_color(probe, imageDirectory):
    stats = probe("histogram", makeColor(imageDirectory, (128,64,32,128)), 203)
    checkConservation(stats)
    hsv = colour.RGB_to_HSV(np.asarray([128,64,32])/255)
    for channel, value in zip("HSV", hsv * [360,1,1]):
        checkBin(stats["channels"][channel], value)


def test_hdr_superwhite_preserved_in_axes(probe, imageDirectory):
    source = imageDirectory / "hdr.png"
    probe("hdrfixture", source)
    stats = probe("histogram", source, 203)
    checkConservation(stats)
    assert stats["channels"]["R"]["upperBound"] > 4.9
    assert stats["channels"]["Y"]["upperBound"] > 999
    assert stats["channels"]["R"]["bins"][-1] > 0


def test_sampling_is_reported_and_source_not_changed(probe, imageDirectory):
    source = imageDirectory / "large.png"
    Image.new("RGB", (1200,800), "white").save(source)
    before = source.read_bytes()
    stats = probe("histogram", source, 400, 128)
    checkConservation(stats)
    assert (stats["originalWidth"],stats["originalHeight"]) == (1200,800)
    assert max(stats["sampledWidth"],stats["sampledHeight"]) == 128
    assert stats["sampledPixelCount"] < 1200*800
    assert "203" in stats["hdrDomain"] and "sRGB" in stats["hsvDomain"]
    assert source.read_bytes() == before


@pytest.mark.parametrize("dimension", [0, -1, 2049])
def test_invalid_sampling_dimension_rejected(probe, imageDirectory, dimension):
    source = makeColor(imageDirectory, (255,0,0,255))
    probe("histogram", source, 203, dimension, success=False)
