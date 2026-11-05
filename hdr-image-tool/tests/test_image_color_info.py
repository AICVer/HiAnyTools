"""色彩描述必须来自真实解码空间，缺失或增益数据不能冒充标准色域。"""

import pytest

from test_hdr_engine import imageDirectory, probe, sdr


@pytest.mark.parametrize("space, family", [
    ("srgb", "sRGB / BT.709"), ("p3", "Display P3"),
    ("pq", "BT.2020"), ("hlg", "BT.2020"),
    ("p3-pq", "Display P3"), ("linear", "BT.2020"), ("gray", "灰度"),
])
def test_named_color_spaces_preserve_actual_description(probe, space, family):
    label = probe("color-description", space)["label"]
    assert family in label
    assert "kCGColorSpace" in label


def test_missing_space_is_not_assigned_srgb(probe):
    assert probe("color-description", "missing")["label"] == "未提供"


def test_device_rgb_does_not_claim_standard_primaries(probe):
    label = probe("color-description", "device-rgb")["label"]
    assert "sRGB / BT.709 原色" not in label
    assert "Display P3 原色" not in label


def test_sdr_file_has_no_native_hdr_or_gainmap(probe, sdr):
    info = probe("color-info", sdr)
    assert info["rawSDRSpace"] in info["sdr"]
    assert "sRGB" in info["sdr"]
    assert "不适用" in info["hdr"] and "SDR 源图" in info["hdr"]
    assert info["gainMap"] == "未提供"


def test_pq_file_reports_hdr_description_and_sdr_appearance(probe, imageDirectory):
    source = imageDirectory / "pq.png"
    probe("hdrfixture", source)
    info = probe("color-info", source)
    assert "BT.2020" in info["hdr"] and "PQ" in info["hdr"]
    assert info["rawHDRSpace"] in info["hdr"]
    assert info["rawSDRSpace"] in info["sdr"]
    assert info["gainMap"] == "未提供"


def test_gainmap_is_gain_data_not_display_gamut(probe, imageDirectory):
    source = imageDirectory / "gainmap.jpg"
    probe("gainmap", source)
    info = probe("color-info", source)
    assert "不适用" in info["gainMap"]
    assert "增益" in info["gainMap"] and "数据空间" in info["gainMap"]
    assert info["hdr"] != "未提供"


def test_composed_hdr_explicitly_reports_working_domain(probe, sdr):
    info = probe("composed-color-info", sdr)
    assert "线性 BT.2020" in info["hdr"] and "合成工作域" in info["hdr"]
    assert info["gainMap"] == "不适用（合成灰度增益图）"
