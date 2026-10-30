"""源线性RGB负值截断：真实Swift分析链、P3边界与HDR高光保护。"""
import colour
import numpy as np
import pytest
from pathlib import Path
from PIL import Image

from test_hdr_engine import probe, imageDirectory


@pytest.mark.parametrize("name,reference", [
    ("sRGB", "sRGB"), ("Display P3", "Display P3"), ("BT.2020", "ITU-R BT.2020")])
@pytest.mark.parametrize("rgb", [[.02, .01, -.004], [-.02, -.01, -.004], [3, 2, -.1]])
def test_negative_source_rgb_is_clamped_before_conversion(probe, name, reference, rgb):
    result = probe("distribution-float", name, ",".join(map(str, [*rgb, 1])))
    point = result["points"][0]
    space = colour.RGB_COLOURSPACES[reference]
    expected = np.maximum(rgb, 0)
    matrix = colour.normalised_primary_matrix(space.primaries, space.whitepoint)
    xyz = matrix @ expected
    np.testing.assert_allclose(point["lab"], colour.XYZ_to_Lab(xyz, illuminant=space.whitepoint), atol=.03)
    if np.any(expected):
        np.testing.assert_allclose(point["xy"], colour.XYZ_to_xy(xyz), atol=.0002)
    else:
        assert "xy" not in point
    assert result["negativeClampedCount"] == 1


def test_legal_p3_red_is_not_clipped_in_bt2020(probe):
    point = probe("distribution-float", "Display P3", "1,0,0,1")["points"][0]
    np.testing.assert_allclose(point["xy"], [.68, .32], atol=.0002)
    xyz = colour.Lab_to_XYZ(point["lab"], illuminant=colour.RGB_COLOURSPACES["Display P3"].whitepoint)
    rgb2020 = colour.RGB_COLOURSPACES["ITU-R BT.2020"].matrix_XYZ_to_RGB @ xyz
    assert rgb2020[2] < -.0005


def test_positive_hdr_highlight_and_gray_are_not_truncated(probe):
    result = probe("distribution-float", "BT.2020", "5,5,5,1,0.18,0.18,0.18,1")
    assert result["points"][0]["lab"][0] > 180
    np.testing.assert_allclose(result["points"][0]["ictcp"],
        colour.RGB_to_ICtCp(np.array([1015., 1015., 1015.]), method="ITU-R BT.2100-2 PQ"), atol=1e-6)
    assert result["negativeClampedCount"] == 0


def test_alpha_is_unpremultiplied_and_transparent_not_counted(probe):
    result = probe("distribution-float", "sRGB", "-0.01,0.05,0.1,0.5,-1,-1,-1,0")
    assert len(result["points"]) == 1
    assert result["transparentCount"] == 1
    assert result["negativeClampedCount"] == 1
    space = colour.RGB_COLOURSPACES["sRGB"]
    xyz = colour.normalised_primary_matrix(space.primaries, space.whitepoint) @ [0, .1, .2]
    np.testing.assert_allclose(result["points"][0]["xy"], colour.XYZ_to_xy(xyz), atol=.0002)


def test_analysis_does_not_modify_input_and_positive_overflow(probe):
    result = probe("distribution-float", "sRGB", "3,2,-0.1,1")
    np.testing.assert_array_equal(result["inputBefore"], result["inputAfter"])
    assert result["inputAfter"][2] < 0
    assert result["inputAfter"][0] > 2.9


def test_composed_p3_uses_original_primaries_when_filter_has_no_color_space(probe):
    point = probe("distribution-float-composed", "Display P3", "1,0,0,1")["points"][0]
    np.testing.assert_allclose(point["xy"], [.68, .32], atol=.0002)


def test_grayscale_input_keeps_neutral_chromaticity(probe, imageDirectory):
    source = imageDirectory / "gray.png"
    Image.new("L", (4, 4), 128).save(source)
    result = probe("distribution", source, 203)
    assert result["negativeClampedCount"] == 0
    np.testing.assert_allclose(result["points"][0]["xy"], [.3127, .329], atol=.0002)


@pytest.mark.skipif(not Path("/Users/wangshupeng/Downloads/IMG_3920.JPG").exists(),
                    reason="用户真实JPEG仅存在本机；合成浮点夹具仍必测")
def test_real_jpeg_low_quality_path_no_longer_generates_screenshot_outliers(probe):
    result = probe("distribution", "/Users/wangshupeng/Downloads/IMG_3920.JPG", 203, 64, "false")
    assert len(result["points"]) == 1792
    assert result["negativeClampedCount"] > 0
    space = colour.RGB_COLOURSPACES["sRGB"]
    xyz = colour.Lab_to_XYZ([p["lab"] for p in result["points"]], illuminant=space.whitepoint)
    sourceRGB = xyz @ np.linalg.inv(colour.normalised_primary_matrix(space.primaries, space.whitepoint)).T
    assert sourceRGB.min() > -2e-5
    assert np.all(xyz >= -1e-8)
    for point in result["points"]:
        assert "cam16" in point and "ictcp" in point
        if "xy" in point:
            assert sum(point["xy"]) <= 1 + 1e-7
