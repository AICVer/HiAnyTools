"""以 colour-science 独立核对色度、CAM16-UCS、ICtCp 和 Lab。"""
import colour
import numpy as np
from PIL import Image
import pytest

from test_hdr_engine import probe, imageDirectory, sdr


@pytest.mark.parametrize("rgb", [[0,0,0], [1,1,1], [.18,.18,.18], [1,0,0], [0,1,0], [0,0,1], [.2,.7,.4], [3,2,1], [5,5,5]])
def test_coordinates_independent_reference(probe, rgb):
    data = probe("coordinates", ",".join(map(str, rgb)))
    space = colour.RGB_COLOURSPACES["ITU-R BT.2020"]
    xyz = space.matrix_RGB_to_XYZ @ rgb
    if sum(rgb):
        np.testing.assert_allclose(data["xy"], colour.XYZ_to_xy(xyz), atol=1e-7)
        uv = colour.UCS_to_uv(colour.XYZ_to_UCS(xyz)) * [1,1.5]
        np.testing.assert_allclose(data["uv"], uv, atol=1e-7)
    else:
        assert "xy" not in data and "uv" not in data
    lab = colour.XYZ_to_Lab(xyz, illuminant=space.whitepoint)
    np.testing.assert_allclose(data["lab"], lab, atol=1e-6)
    cam = colour.XYZ_to_CAM16UCS(xyz, XYZ_w=colour.xy_to_XYZ(space.whitepoint),
        L_A=100, Y_b=20, discount_illuminant=True)
    np.testing.assert_allclose(data["cam16"], cam, atol=1e-5)
    ictcp = colour.RGB_to_ICtCp(np.array(rgb) * 203, method="ITU-R BT.2100-2 PQ")
    np.testing.assert_allclose(data["ictcp"], ictcp, atol=1e-8)


def test_hdr_coordinates_not_clamped_to_sdr(probe, imageDirectory):
    source = imageDirectory / "hdr.png"
    probe("hdrfixture", source)
    stats = probe("distribution", source, 203)
    assert max(p["lab"][0] for p in stats["points"]) > 170
    assert stats["width"] == 2


def test_sampling_alpha_and_counts(probe, imageDirectory):
    source = imageDirectory / "alpha.png"
    values = np.zeros((64,64,4), dtype=np.uint8)
    values[:32,:,:] = [255,0,0,128]
    Image.fromarray(values).save(source)
    stats = probe("distribution", source, 203)
    assert len(stats["points"]) == 2048
    assert stats["transparentCount"] == 2048
    assert stats["invalidCount"] == 0
    np.testing.assert_allclose(stats["points"][0]["xy"], [.64,.33], atol=.001)


def test_distribution_aspect_ratio_and_max_samples(probe, imageDirectory):
    source = imageDirectory / "big.png"
    Image.new("RGB", (1920,1080), (128,128,128)).save(source)
    stats = probe("distribution", source, 203)
    assert (stats["width"],stats["height"]) == (64,36)
    assert len(stats["points"]) == 2304


@pytest.mark.parametrize("size", [0,129])
def test_invalid_sample_size(probe, sdr, size):
    assert probe("distribution", sdr, 203, size, success=False)


def test_undefined_ictcp_domain_not_silently_clipped(probe):
    assert "ictcp" not in probe("coordinates", "100,100,100")
    assert "ictcp" not in probe("coordinates", "-1,-1,-1")
