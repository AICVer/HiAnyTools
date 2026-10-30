"""pytest 驱动实际 Swift 图像引擎；测试数据与覆盖率全部保存在 output。"""

from __future__ import annotations

import json
from pathlib import Path
import struct
import subprocess
import uuid
import zlib

import colour
import numpy as np
from PIL import Image
import pytest


PROJECT = Path(__file__).resolve().parents[1]
OUTPUT = PROJECT / "output" / "tests"


@pytest.fixture(scope="session")
def probe():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    binary = OUTPUT / "hdr-probe"
    subprocess.run([
        "xcrun", "swiftc", *[str(path) for path in sorted((PROJECT / "Sources").glob("*.swift"))
                            if path.name != "HDRImageLabApp.swift"],
        str(PROJECT / "tests/Probe.swift"), "-o", str(binary),
        "-module-cache-path", str(OUTPUT / "ModuleCache"),
        "-profile-generate", "-profile-coverage-mapping",
    ], check=True, capture_output=True, text=True)

    def runProbe(*args: object, success: bool = True):
        runDirectory = OUTPUT / "runs" / uuid.uuid4().hex
        runDirectory.mkdir(parents=True)
        process = subprocess.run([str(binary), *map(str, args)], cwd=runDirectory,
                                 capture_output=True, text=True, timeout=60)
        if success:
            assert process.returncode == 0, process.stderr
            return json.loads(process.stdout)
        assert process.returncode != 0
        return process.stderr

    return runProbe


@pytest.fixture
def imageDirectory():
    path = OUTPUT / "fixtures" / uuid.uuid4().hex
    path.mkdir(parents=True)
    return path


@pytest.fixture
def sdr(probe, imageDirectory):
    path = imageDirectory / "sdr.png"
    probe("fixture", path)
    return path


def sample(probe, peak: float, pixels: list[float]) -> np.ndarray:
    """调用生产高光处理，并返回实际 Core Image 渲染值。"""
    data = probe("sample", peak, ",".join(map(str, pixels)))
    return np.asarray(data["pixels"]).reshape(-1, 4)


def pngChunks(path: Path) -> dict[bytes, bytes]:
    """独立检查 PNG chunk 与 CRC，不通过生产代码解释元数据。"""
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    chunks = {}
    offset = 8
    while offset < len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        crc = struct.unpack_from(">I", data, offset + 8 + length)[0]
        assert zlib.crc32(kind + payload) == crc
        chunks[kind] = chunks.get(kind, b"") + payload
        offset += length + 12
    return chunks


def pngPixels(path: Path) -> np.ndarray:
    """按 PNG 标准反滤波，直接读取 16 位 PQ 码值。"""
    chunks = pngChunks(path)
    width, height, depth, colorType, _, _, interlace = struct.unpack(">IIBBBBB", chunks[b"IHDR"])
    assert depth == 16 and colorType in (2, 6) and interlace == 0
    channels = 4 if colorType == 6 else 3
    bpp = channels * 2
    rowSize = width * bpp
    raw = zlib.decompress(chunks[b"IDAT"])
    previous = bytearray(rowSize)
    rows = []
    for rowIndex in range(height):
        start = rowIndex * (rowSize + 1)
        method = raw[start]
        current = bytearray(raw[start + 1:start + 1 + rowSize])
        for i in range(rowSize):
            left = current[i - bpp] if i >= bpp else 0
            above = previous[i]
            upperLeft = previous[i - bpp] if i >= bpp else 0
            if method == 0:
                predictor = 0
            elif method == 1:
                predictor = left
            elif method == 2:
                predictor = above
            elif method == 3:
                predictor = (left + above) // 2
            else:
                assert method == 4
                p = left + above - upperLeft
                candidates = (left, above, upperLeft)
                predictor = min(candidates, key=lambda value: abs(p - value))
            current[i] = (current[i] + predictor) % 256
        rows.append(np.frombuffer(bytes(current), dtype=">u2").reshape(width, channels))
        previous = current
    return np.stack(rows).astype(float) / 65535


@pytest.mark.parametrize("peak", [203, 400, 600])
def test_gray_ramp_is_monotonic_and_bounded(probe, peak):
    values = np.linspace(0, 1, 257)
    pixels = [[v, v, v, 1] for v in values]
    output = sample(probe, peak, np.asarray(pixels).ravel().tolist())
    assert np.all(np.diff(output[:, 0]) >= -1e-6)
    np.testing.assert_allclose(output[values <= 0.5, 0], values[values <= 0.5], atol=1e-6)
    np.testing.assert_allclose(output[-1, :3], peak / 203, atol=1e-5)
    assert output[:, :3].max() <= peak / 203 + 1e-5


def test_default_is_identity_including_color_and_alpha(probe):
    pixels = [0.7, 0.2, 0.4, 1, 0.25, 0.15, 0.1, 0.5]
    np.testing.assert_allclose(sample(probe, 203, pixels).ravel(), pixels, atol=1e-6)


def test_highlight_gain_preserves_color_ratios_and_alpha(probe):
    pixels = np.array([[0.9, 0.8, 0.7, 1], [0.45, 0.4, 0.35, 0.5], [0, 0, 0, 0]])
    result = sample(probe, 600, pixels.ravel().tolist())
    gains = result[:2, :3] / pixels[:2, :3]
    assert np.all(gains > 1)
    np.testing.assert_allclose(gains, np.repeat(gains[:, :1], 3, axis=1), atol=1e-5)
    np.testing.assert_allclose(result[:, 3], pixels[:, 3], atol=1e-6)
    assert np.isfinite(result).all()


@pytest.mark.parametrize("peak", [202, 601, "nan", "inf"])
def test_invalid_peak_rejected(probe, peak):
    assert "203" in probe("sample", peak, "1,1,1,1", success=False)


@pytest.mark.parametrize("format", ["PNG", "TIFF"])
@pytest.mark.parametrize("peak", [203, 400, 600])
def test_export_depth_encoding_and_roundtrip(probe, sdr, imageDirectory, format, peak):
    result = probe("export", sdr, peak, format, imageDirectory)
    path = Path(result["path"])
    info = probe("inspect", path)
    assert (info["width"], info["height"], info["depth"]) == (5, 1, 16)
    assert "2100_PQ" in info["space"]
    assert info["isHDR"] and not info["gainMap"]
    linear = np.asarray(info["linear"]).reshape(-1, 4)
    np.testing.assert_allclose(linear[1, :3], 0.18, atol=0.002)
    np.testing.assert_allclose(linear[-1, :3] * 203, peak, atol=0.4)
    if format == "PNG":
        assert pngChunks(path)[b"cICP"] == bytes([9, 16, 0, 1])
        code = pngPixels(path)[0, -1, :3]
        expected = colour.models.eotf_inverse_ST2084(peak)
        np.testing.assert_allclose(code, expected, atol=5e-5)
    else:
        with Image.open(path) as tiff:
            assert set(tiff.tag_v2[258]) == {16}
            assert tiff.info.get("icc_profile")


def test_hdr_input_not_limited_by_sdr_slider(probe, sdr, imageDirectory):
    first = probe("export", sdr, 600, "PNG", imageDirectory)["path"]
    second = probe("export", first, 203, "TIFF", imageDirectory)["path"]
    values = np.asarray(probe("inspect", second)["linear"]).reshape(-1, 4)
    np.testing.assert_allclose(values[-1, :3] * 203, 600, atol=0.5)


def test_original_hdr_above600_preserved(probe, imageDirectory):
    source = imageDirectory / "original-1000.png"
    probe("hdrfixture", source)
    path = probe("export", source, 203, "TIFF", imageDirectory)["path"]
    values = np.asarray(probe("inspect", path)["linear"]).reshape(-1, 4)
    np.testing.assert_allclose(values[-1, :3] * 203, 1000, atol=0.5)


@pytest.mark.parametrize("mode", ["HDR", "SDR"])
def test_preview_modes(probe, sdr, mode):
    assert probe("preview", sdr, mode) == {"width": 5, "height": 1}


def test_no_gainmap_cannot_fake_gainmap_view(probe, sdr):
    assert not probe("inspect", sdr)["gainMap"]
    assert "GainMap" in probe("preview", sdr, "GainMap", success=False)


def test_preview_resize_preserves_export_size(probe, imageDirectory):
    path = imageDirectory / "wide.png"
    Image.new("RGB", (4096, 16), "white").save(path)
    assert probe("preview", path, "HDR") == {"width": 2048, "height": 8}
    output = probe("export", path, 600, "PNG", imageDirectory)["path"]
    with Image.open(output) as image:
        assert image.size == (4096, 16)


def test_orientation_applied_once(probe, imageDirectory):
    path = imageDirectory / "rotated.jpg"
    exif = Image.Exif()
    exif[274] = 6
    Image.new("RGB", (3, 2), "red").save(path, exif=exif)
    info = probe("inspect", path)
    assert (info["width"], info["height"]) == (2, 3)
    output = probe("export", path, 203, "PNG", imageDirectory)["path"]
    again = probe("inspect", output)
    assert (again["width"], again["height"]) == (2, 3)


def test_animated_image_rejected(probe, imageDirectory):
    path = imageDirectory / "animated.gif"
    Image.new("RGB", (4, 4), "red").save(path, save_all=True,
        append_images=[Image.new("RGB", (4, 4), "blue")], duration=100)
    assert "静态" in probe("inspect", path, success=False)


@pytest.mark.parametrize("kind", ["missing", "corrupt"])
def test_invalid_input_rejected(probe, imageDirectory, kind):
    path = imageDirectory / kind
    if kind == "corrupt":
        path.write_bytes(b"not an image")
    assert "读取" in probe("inspect", path, success=False)


def test_large_image_rejected_from_header(probe, imageDirectory):
    path = imageDirectory / "large.png"
    Image.new("1", (10000, 6000), 0).save(path)
    assert "5000" in probe("inspect", path, success=False)


def test_unwritable_export_does_not_leave_result(probe, sdr, imageDirectory):
    file = imageDirectory / "not-a-directory"
    file.write_text("keep", encoding="utf-8")
    probe("export", sdr, 600, "PNG", file, success=False)
    assert file.read_text(encoding="utf-8") == "keep"


def test_generated_iso_gainmap_three_views_and_pq_export(probe, imageDirectory):
    path = imageDirectory / "gainmap.jpg"
    probe("gainmap", path)
    info = probe("inspect", path)
    assert info["gainMap"] and info["isHDR"]
    for mode in ("HDR", "SDR", "GainMap"):
        preview = probe("preview", path, mode)
        assert preview["width"] > 0 and preview["height"] > 0
    output = probe("export", path, 203, "PNG", imageDirectory)["path"]
    decoded = np.asarray(probe("inspect", output)["linear"]).reshape(-1, 4)
    assert decoded[:, :3].max() > 1
