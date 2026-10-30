"""红军门禁 3：真实 GainMap/PQ 转换及 SDR 高光增强的独立数值对照。"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import uuid

import colour
import numpy as np
from PIL import Image
import pytest

from test_hdr_engine import pngChunks, pngPixels


PROJECT = Path(__file__).resolve().parents[1]
ROOT = Path("/Users/wangshupeng/workspace/项目工作/画质研发团队/📚画质技术栈📚/技术洞察 | 画质技术标准/技术标准 | Gainmap")
OUTPUT = PROJECT / "output/red-team/round3"
HDR_CASES = [
    ("pq-png", "hdr/b614d537-4817-46fc-9120-498f090161e2.png"),
    ("pq-avif", "PQ-RGBW.avif"),
    ("pq-heic", "1. ISO_22028-5_HDR_PQ_4.93/image_001_HDR_PQ_4.93.heic"),
    ("apple", "IMG_3853.HEIC"),
    ("iso-heic", "4. ISO_21496-1_Adaptive_HDR/image_025_AdaptiveHDR.heic"),
    ("dual-jpeg", "GainMap-vs-HDR/gainMap.jpg"),
    ("adobe-jpeg", "Ultra_HDR_Samples/Originals/Ultra_HDR_Samples_Originals_01.jpg"),
]


@pytest.fixture(scope="session")
def round3Probe():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    swiftSources = sorted((PROJECT / "Sources").glob("*.swift"))
    sources = [path for path in swiftSources if path.name != "HDRImageLabApp.swift"]
    sources.append(PROJECT / "tests/Probe.swift")
    snapshotFiles = [*swiftSources, PROJECT / "tests/Probe.swift"]
    before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in snapshotFiles}
    binary = OUTPUT / "hdr-probe"
    subprocess.run(["xcrun", "swiftc", *map(str, sources), "-o", str(binary),
                    "-module-cache-path", str(OUTPUT / "ModuleCache")],
                   check=True, capture_output=True, text=True)

    def invoke(*args: object, success: bool = True):
        run = OUTPUT / "runs" / uuid.uuid4().hex
        run.mkdir(parents=True)
        process = subprocess.run([str(binary), *map(str, args)], cwd=run,
                                 capture_output=True, text=True, timeout=90)
        (run / "stdout.txt").write_text(process.stdout, encoding="utf-8")
        (run / "stderr.txt").write_text(process.stderr, encoding="utf-8")
        if success:
            assert process.returncode == 0, process.stderr
            return json.loads(process.stdout)
        assert process.returncode != 0, process.stdout
        return process.stderr

    yield invoke
    after = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in snapshotFiles}
    (OUTPUT / "snapshot.json").write_text(json.dumps({"before": before, "after": after}, indent=2), encoding="utf-8")
    assert before == after, "门禁期间源码变化，结论失效"


@pytest.fixture
def round3Folder():
    folder = OUTPUT / "files" / uuid.uuid4().hex
    folder.mkdir(parents=True)
    return folder


@pytest.mark.parametrize("kind,name", HDR_CASES)
@pytest.mark.parametrize("format", ["PNG", "TIFF"])
def test_real_hdr_to_pq_preserves_light_and_source(round3Probe, round3Folder, kind, name, format):
    source = ROOT / name
    originalBytes = source.read_bytes()
    before = round3Probe("meta", source)
    # 大图仅为控制测试资源缩至512宽；小样本保持原尺寸，均验证明确输出尺寸。
    resized = before["orientedWidth"] > 1500
    options = {"width": 512} if resized else {}
    result = Path(round3Probe("hdr-options", source, format, 203,
                              json.dumps(options), round3Folder)["path"])
    after = round3Probe("meta", result)
    assert after["depth"] == 16 and after["isHDR"]
    assert after["type"] == ("public.png" if format == "PNG" else "public.tiff")
    assert not after["hasAppleGainMap"] and not after["hasISOGainMap"]
    assert after["maxRGB"] > 1
    if resized:
        assert after["orientedWidth"] == 512
        expectedHeight = before["orientedHeight"] * 512 / before["orientedWidth"]
        assert abs(after["orientedHeight"] - expectedHeight) <= 1
    else:
        assert (after["orientedWidth"], after["orientedHeight"]) == (before["orientedWidth"], before["orientedHeight"])
    # 缩小会改变局部峰值；原尺寸只允许量化/色彩转换微差。
    tolerance = 0.10 if resized else 0.005
    if not resized:
        # ffmpeg原始10位RGBW码值0/1023证明：PQ上限为10000nit，不能把native工作域溢出当作合法编码亮度。
        expectedPeak = min(max(0, before["maxRGB"]), 10000 / 203)
        assert abs(after["maxRGB"] - expectedPeak) / expectedPeak < tolerance
    assert abs(after["meanY"] - before["meanY"]) / before["meanY"] < tolerance
    if format == "PNG":
        assert pngChunks(result)[b"cICP"] == bytes([9, 16, 0, 1])
    assert hashlib.sha256(source.read_bytes()).digest() == hashlib.sha256(originalBytes).digest()
    (OUTPUT / f"{kind}-{format}-roundtrip.json").write_text(
        json.dumps({"source": before, "output": after, "resized": resized}, indent=2), encoding="utf-8")


@pytest.mark.parametrize("peak", [203, 400, 600])
def test_encoded_white_matches_independent_st2084(round3Probe, round3Folder, peak):
    source = round3Folder / "sdr.png"
    round3Probe("fixture", source)
    result = Path(round3Probe("export", source, peak, "PNG", round3Folder)["path"])
    code = pngPixels(result)[0, -1, :3]
    expected = colour.models.eotf_inverse_ST2084(peak)
    np.testing.assert_allclose(code, expected, atol=5e-5)
    np.testing.assert_allclose(colour.models.eotf_ST2084(code), peak, atol=0.4)


@pytest.mark.parametrize("peak", [203, 400, 600])
def test_ramp_monotonic_dark_identity_and_peak_bound(round3Probe, peak):
    values = np.array([0, 0.01, 0.18, 0.49, 0.5, 0.5001, 0.55, 0.75, 0.99, 1])
    encoded = np.column_stack([values, values, values, np.ones_like(values)]).ravel()
    data = round3Probe("sample", peak, ",".join(map(str, encoded)))
    output = np.asarray(data["pixels"]).reshape(-1, 4)
    assert np.isfinite(output).all()
    assert np.all(np.diff(output[:, 0]) >= 0)
    np.testing.assert_allclose(output[values <= 0.5, 0], values[values <= 0.5], atol=1e-6)
    assert output[:, :3].max() <= peak / 203 + 1e-5
    np.testing.assert_allclose(output[-1, :3], peak / 203, atol=1e-5)
    np.testing.assert_allclose(output[:, 3], 1, atol=1e-6)


def test_rgb_ratios_and_partial_alpha_are_preserved(round3Probe):
    source = np.array([[0.95, 0.8, 0.65, 1], [0.475, 0.4, 0.325, 0.5], [0, 0, 0, 0]])
    data = round3Probe("sample", 600, ",".join(map(str, source.ravel())))
    output = np.asarray(data["pixels"]).reshape(-1, 4)
    assert np.isfinite(output).all()
    gains = output[:2, :3] / source[:2, :3]
    np.testing.assert_allclose(gains[:, 0], gains[:, 1], atol=1e-5)
    np.testing.assert_allclose(gains[:, 1], gains[:, 2], atol=1e-5)
    np.testing.assert_allclose(output[:, 3], source[:, 3], atol=1e-6)
    np.testing.assert_allclose(output[2], 0, atol=1e-6)


def test_existing_hdr_not_clamped_to_sdr_slider_limit(round3Probe, round3Folder):
    source = round3Folder / "1000.png"
    round3Probe("hdrfixture", source)
    result = Path(round3Probe("export", source, 203, "TIFF", round3Folder)["path"])
    info = round3Probe("meta", result)
    assert info["maxRGB"] * 203 > 990


@pytest.mark.parametrize("peak", [202, 601, "nan", "inf"])
def test_invalid_sdr_peak_rejected(round3Probe, peak):
    assert "203" in round3Probe("sample", peak, "1,1,1,1", success=False)


@pytest.mark.parametrize("peak", [203, 400, 600])
def test_png_clli_crc_units_and_quantized_gray_frame_values(round3Probe, round3Folder, peak):
    source = round3Folder / "sdr-gray.png"
    round3Probe("fixture", source)
    result = Path(round3Probe("export", source, peak, "PNG", round3Folder)["path"])
    chunks = pngChunks(result)  # 独立验证所有chunk CRC。
    assert len(chunks[b"cLLI"]) == 8
    maximum = int.from_bytes(chunks[b"cLLI"][:4], "big") / 10000
    average = int.from_bytes(chunks[b"cLLI"][4:], "big") / 10000
    decodedNits = colour.models.eotf_ST2084(pngPixels(result)[..., :3])
    np.testing.assert_allclose(maximum, decodedNits.max(), atol=0.5)
    np.testing.assert_allclose(average, decodedNits.max(axis=-1).mean(), atol=0.5)
    assert 0 <= average <= maximum


def test_black_clli_does_not_replace_zero_peak_with_reference_white(round3Probe, round3Folder):
    source = round3Folder / "black.png"
    Image.new("RGB", (32, 16), "black").save(source)
    result = Path(round3Probe("export", source, 600, "PNG", round3Folder)["path"])
    payload = pngChunks(result)[b"cLLI"]
    maximum = int.from_bytes(payload[:4], "big") / 10000
    average = int.from_bytes(payload[4:], "big") / 10000
    assert maximum < 0.5 and average < 0.5


def test_colored_clli_uses_average_max_rgb_not_average_y(round3Probe, round3Folder):
    source = round3Folder / "red-green.png"
    image = Image.new("RGB", (64, 32), "red")
    image.paste((0, 255, 0), (32, 0, 64, 32))
    image.save(source)
    result = Path(round3Probe("export", source, 203, "PNG", round3Folder)["path"])
    payload = pngChunks(result)[b"cLLI"]
    average = int.from_bytes(payload[4:], "big") / 10000
    decodedNits = colour.models.eotf_ST2084(pngPixels(result)[..., :3])
    expected = decodedNits.max(axis=-1).mean()
    yMean = (decodedNits * [0.2627, 0.6780, 0.0593]).sum(axis=-1).mean()
    # 非灰色样本能区分mean(maxRGB)与mean(Y)，留3%给跨CMM边界差异。
    assert abs(average - expected) <= max(0.5, expected * 0.03)
    assert average > yMean * 1.4


def test_target_byte_limit_includes_complete_clli_chunk(round3Probe, round3Folder):
    source = round3Folder / "sdr-budget.png"
    round3Probe("fixture", source)
    baseline = Path(round3Probe("export", source, 600, "PNG", round3Folder)["path"])
    assert b"cLLI" in pngChunks(baseline)
    size = baseline.stat().st_size
    destination = round3Folder / "budget"
    destination.mkdir()
    exact = Path(round3Probe("hdr-options", source, "PNG", 600,
                            json.dumps({"targetBytes": size}), destination)["path"])
    assert exact.stat().st_size <= size
    before = set(destination.iterdir())
    round3Probe("hdr-options", source, "PNG", 600,
                json.dumps({"targetBytes": size - 1}), destination, success=False)
    assert set(destination.iterdir()) == before
