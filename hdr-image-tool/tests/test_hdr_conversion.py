"""R5/R6：导出光级元数据与 Alpha/非法参数回归。"""

import json
from pathlib import Path
import struct

import numpy as np
from PIL import Image
import pytest

from test_hdr_engine import imageDirectory, pngChunks, probe, sdr


@pytest.mark.parametrize("peak", [203, 400, 600])
def test_png_clli_matches_final_quantized_pixels(probe, sdr, imageDirectory, peak):
    path = Path(probe("export", sdr, peak, "PNG", imageDirectory)["path"])
    chunks = pngChunks(path)
    maxCLL, maxFALL = np.asarray(struct.unpack(">II", chunks[b"cLLI"])) / 10000
    rgba = np.asarray(probe("inspect", path)["linear"]).reshape(-1, 4)
    maxRGB = rgba[:, :3].max(axis=1) * 203
    assert abs(maxCLL - maxRGB.max()) < 0.05
    assert abs(maxFALL - maxRGB.mean()) < 0.05
    assert chunks[b"cICP"] == bytes([9,16,0,1])


@pytest.mark.parametrize("format", ["PNG", "TIFF"])
def test_hdr_export_alpha_and_straight_highlight(probe, imageDirectory, format):
    source = imageDirectory / "alpha-white.png"
    Image.new("RGBA", (4, 4), (255,255,255,128)).save(source)
    path = probe("export", source, 600, format, imageDirectory)["path"]
    rgba = np.asarray(probe("inspect", path)["linear"]).reshape(-1, 4)
    np.testing.assert_allclose(rgba[:, 3], 128/255, atol=2e-4)
    np.testing.assert_allclose(rgba[:, :3] / rgba[:, 3,None] * 203, 600, atol=0.6)


@pytest.mark.parametrize("peak", [202, 601, "nan", "inf"])
def test_invalid_peak_also_rejected_for_original_hdr(probe, imageDirectory, peak):
    source = imageDirectory / "hdr.png"
    probe("hdrfixture", source)
    assert "203" in probe("export", source, peak, "PNG", imageDirectory, success=False)


def test_clli_bytes_are_included_in_target_budget(probe, sdr, imageDirectory):
    first = Path(probe("export", sdr, 600, "PNG", imageDirectory)["path"])
    before = set(imageDirectory.iterdir())
    probe("hdr-options", sdr, "PNG", 600,
        json.dumps({"targetBytes": first.stat().st_size - 1}), imageDirectory, success=False)
    assert set(imageDirectory.iterdir()) == before
