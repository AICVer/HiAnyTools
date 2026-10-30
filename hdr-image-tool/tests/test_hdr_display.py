"""R3/R4：实际 HDR 浮点预览与显式内容余量。"""

import shutil

import pytest

from test_hdr_engine import imageDirectory, probe, sdr


@pytest.mark.parametrize("peak", [203, 400, 600])
def test_sdr_enhancement_preview_is_tagged_linear_float(probe, sdr, peak):
    info = probe("preview-meta", sdr, "HDR", peak)
    assert info["bitsPerComponent"] == 16
    assert "ExtendedLinearITUR_2020" in info["colorSpace"]
    assert abs(info["contentHeadroom"] - peak / 203) < 0.005
    assert abs(info["maxRGB"] - peak / 203) < 0.005


def test_pq_preview_stays_above_reference_white(probe, imageDirectory):
    source = imageDirectory / "pq.png"
    probe("hdrfixture", source)
    hdr = probe("preview-meta", source, "HDR", 203)
    sdrInfo = probe("preview-meta", source, "SDR", 203)
    assert hdr["contentHeadroom"] > 4.9 and hdr["maxRGB"] > 4.9
    assert sdrInfo["bitsPerComponent"] == 8 and sdrInfo["contentHeadroom"] <= 1
    assert sdrInfo["maxRGB"] <= 1.01


def test_actual_format_ignores_misleading_extension(probe, imageDirectory):
    source = imageDirectory / "original.png"
    disguised = imageDirectory / "not-really-jpeg.jpg"
    probe("hdrfixture", source)
    shutil.copyfile(source, disguised)
    info = probe("preview-meta", disguised, "HDR", 203)
    assert info["formatName"] == "PNG" and info["dynamicRangeLabel"] == "PQ HDR"


def test_gainmap_preview_has_distinct_modes(probe, imageDirectory):
    source = imageDirectory / "gainmap.jpg"
    probe("gainmap", source)
    hdr = probe("preview-meta", source, "HDR", 203)
    sdrInfo = probe("preview-meta", source, "SDR", 203)
    gain = probe("preview-meta", source, "GainMap", 203)
    assert hdr["dynamicRangeLabel"] == "GainMap HDR"
    assert hdr["maxRGB"] > sdrInfo["maxRGB"]
    assert gain["bitsPerComponent"] == 8


def test_headroom_uses_actual_pixels(probe):
    info = probe("sample", 203, "5,4,3,1")
    assert abs(info["contentHeadroom"] - 5) < 0.001
