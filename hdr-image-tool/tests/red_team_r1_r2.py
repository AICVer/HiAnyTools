"""红军独立门禁 1：R1/R2，对固定源码快照和只读真实样图执行。"""

from __future__ import annotations

import hashlib
import io
import json
from pathlib import Path
import subprocess
import uuid

import numpy as np
from PIL import Image, ImageCms
import colour
import pytest


PROJECT = Path(__file__).resolve().parents[1]
ROOT = Path("/Users/wangshupeng/workspace/项目工作/画质研发团队/📚画质技术栈📚/技术洞察 | 画质技术标准/技术标准 | Gainmap")
OUTPUT = PROJECT / "output/red-team/round1"
FORMATS = ["JPEG", "HEIC", "PNG", "BMP"]


def digest(path: Path) -> str:
    """取得文件快照摘要，核查原始测试数据与源码未被悄然改变。"""
    return hashlib.sha256(path.read_bytes()).hexdigest()


@pytest.fixture(scope="session")
def redProbe():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    binary = OUTPUT / "hdr-probe"
    swiftSources = sorted((PROJECT / "Sources").glob("*.swift"))
    sources = [path for path in swiftSources if path.name != "HDRImageLabApp.swift"]
    sources.append(PROJECT / "tests/Probe.swift")
    snapshotFiles = [*swiftSources, PROJECT / "tests/Probe.swift"]
    before = {str(path): digest(path) for path in snapshotFiles}
    subprocess.run(["xcrun", "swiftc", *map(str, sources), "-o", str(binary),
                    "-module-cache-path", str(OUTPUT / "ModuleCache")],
                   check=True, capture_output=True, text=True)

    def invoke(*args: object, success: bool = True):
        run = OUTPUT / "runs" / uuid.uuid4().hex
        run.mkdir(parents=True)
        result = subprocess.run([str(binary), *map(str, args)], cwd=run,
                                capture_output=True, text=True, timeout=90)
        (run / "stdout.txt").write_text(result.stdout, encoding="utf-8")
        (run / "stderr.txt").write_text(result.stderr, encoding="utf-8")
        if success:
            assert result.returncode == 0, result.stderr
            return json.loads(result.stdout)
        assert result.returncode != 0, result.stdout
        return result.stderr

    yield invoke
    after = {str(path): digest(path) for path in snapshotFiles}
    (OUTPUT / "snapshot.json").write_text(json.dumps({"before": before, "after": after}, indent=2), encoding="utf-8")
    assert before == after, "门禁执行中源码发生变化，本轮结论已过期"


@pytest.fixture
def outFolder():
    folder = OUTPUT / "files" / uuid.uuid4().hex
    folder.mkdir(parents=True)
    return folder


@pytest.fixture
def noiseSource(outFolder):
    path = outFolder / "noise.png"
    noise = np.random.default_rng(925).integers(0, 256, (240, 320, 3), dtype=np.uint8)
    Image.fromarray(noise).save(path)
    return path


def exportOptions(redProbe, source: Path, format: str, options: dict, folder: Path) -> Path:
    """通过生产 Swift CLI 导出，不在 Python 复制缩放或编码算法。"""
    return Path(redProbe("sdr-options", source, format, json.dumps(options), folder)["path"])


@pytest.mark.parametrize("format", FORMATS)
def test_real_p3_sdr_decode_convert_and_keep_source(redProbe, outFolder, format):
    source = ROOT / "GainMap-vs-HDR/sdrOriginal.jpg"
    before = digest(source)
    result = exportOptions(redProbe, source, format, {"width": 130}, outFolder)
    meta = redProbe("meta", result)
    assert (meta["orientedWidth"], meta["orientedHeight"], meta["depth"]) == (130, 195, 8)
    assert not meta["isHDR"]
    assert digest(source) == before


@pytest.mark.parametrize("format", ["PNG", "JPEG", "HEIC"])
def test_dpi_change_preserves_raster_and_reports_density(redProbe, noiseSource, outFolder, format):
    result = exportOptions(redProbe, noiseSource, format, {"dpi": 301}, outFolder)
    meta = redProbe("meta", result)
    assert (meta["orientedWidth"], meta["orientedHeight"]) == (320, 240)
    assert abs(meta["dpiWidth"] - 301) < 0.03
    assert abs(meta["dpiHeight"] - 301) < 0.03
    if format == "PNG":
        baseline = exportOptions(redProbe, noiseSource, format, {}, outFolder)
        with Image.open(baseline) as first, Image.open(result) as second:
            assert np.array_equal(np.asarray(first), np.asarray(second))


def test_bmp_dpi_density_is_not_silently_dropped(redProbe, noiseSource, outFolder):
    result = exportOptions(redProbe, noiseSource, "BMP", {"dpi": 301}, outFolder)
    with Image.open(result) as image:
        assert abs(image.info["dpi"][0] - 301) < 0.03
        assert abs(image.info["dpi"][1] - 301) < 0.03


@pytest.mark.parametrize("dimension", [{"width": 123}, {"height": 123}])
def test_orientation_then_resize_retains_aspect(redProbe, outFolder, dimension):
    path = outFolder / "rotate.jpg"
    exif = Image.Exif()
    exif[274] = 6
    Image.new("RGB", (120, 80), "red").save(path, exif=exif)
    result = exportOptions(redProbe, path, "PNG", dimension, outFolder)
    with Image.open(result) as image:
        width, height = image.size
        assert image.getexif().get(274, 1) == 1
        assert abs(width / height - 2 / 3) < 0.006
        if "width" in dimension:
            assert width == 123
        else:
            assert height == 123


@pytest.mark.parametrize("format", ["JPEG", "HEIC"])
def test_quality_adjustment_affects_actual_encoding(redProbe, noiseSource, outFolder, format):
    low = exportOptions(redProbe, noiseSource, format, {"quality": 0.05}, outFolder)
    high = exportOptions(redProbe, noiseSource, format, {"quality": 0.98}, outFolder)
    assert low.stat().st_size < high.stat().st_size
    assert low.read_bytes() != high.read_bytes()


@pytest.mark.parametrize("format", ["JPEG", "HEIC"])
def test_reachable_target_bytes_keeps_requested_pixels(redProbe, noiseSource, outFolder, format):
    low = exportOptions(redProbe, noiseSource, format, {"width": 160, "quality": 0}, outFolder)
    high = exportOptions(redProbe, noiseSource, format, {"width": 160, "quality": 0.92}, outFolder)
    target = (low.stat().st_size + high.stat().st_size) // 2
    result = exportOptions(redProbe, noiseSource, format, {"width": 160, "targetBytes": target}, outFolder)
    assert result.stat().st_size <= target
    meta = redProbe("meta", result)
    assert (meta["orientedWidth"], meta["orientedHeight"]) == (160, 120)


@pytest.mark.parametrize("format", FORMATS)
def test_impossible_target_leaves_no_result_or_pixel_shrink(redProbe, noiseSource, outFolder, format):
    destination = outFolder / "impossible"
    destination.mkdir()
    redProbe("sdr-options", noiseSource, format, json.dumps({"targetBytes": 1, "width": 160}),
             destination, success=False)
    assert list(destination.iterdir()) == []


@pytest.mark.parametrize("options", [
    {"quality": -0.001}, {"quality": 1.001}, {"dpi": 0}, {"dpi": 2401},
    {"width": 0}, {"height": -1}, {"width": 20, "height": 20}, {"targetBytes": 0},
    {"width": 100000},
])
def test_invalid_options_fail_without_artifact(redProbe, noiseSource, outFolder, options):
    destination = outFolder / "invalid"
    destination.mkdir()
    redProbe("sdr-options", noiseSource, "JPEG", json.dumps(options), destination, success=False)
    assert list(destination.iterdir()) == []


def test_real_transparency_survives_resize_and_png(redProbe, outFolder):
    source = ROOT / "hdr-sticker/example.png"
    before = digest(source)
    result = exportOptions(redProbe, source, "PNG", {"height": 297}, outFolder)
    with Image.open(result) as image:
        alpha = np.asarray(image.convert("RGBA"))[:, :, 3]
        assert image.size == (360, 297)
        assert alpha.min() == 0 and alpha.max() == 255
    assert digest(source) == before


def test_real_pq_png_to_sdr_and_pq_options_metadata(redProbe, outFolder):
    source = ROOT / "hdr/b614d537-4817-46fc-9120-498f090161e2.png"
    before = digest(source)
    sdr = exportOptions(redProbe, source, "PNG", {"width": 150}, outFolder)
    assert not redProbe("meta", sdr)["isHDR"]
    output = Path(redProbe("hdr-options", source, "PNG", 203,
                          json.dumps({"width": 150, "dpi": 300}), outFolder)["path"])
    meta = redProbe("meta", output)
    assert meta["depth"] == 16 and meta["isHDR"]
    assert (meta["orientedWidth"], meta["orientedHeight"]) == (150, 100)
    assert abs(meta["dpiWidth"] - 300) < 0.03
    assert digest(source) == before


def test_real_p3_to_srgb_against_independent_lcms(redProbe, outFolder):
    source = ROOT / "GainMap-vs-HDR/sdrOriginal.jpg"
    result = exportOptions(redProbe, source, "PNG", {}, outFolder)
    with Image.open(source) as original, Image.open(result) as converted:
        profile = ImageCms.ImageCmsProfile(io.BytesIO(original.info["icc_profile"]))
        expected = ImageCms.profileToProfile(original, profile, ImageCms.createProfile("sRGB"),
                                            renderingIntent=1, outputMode="RGB")
        left = np.asarray(expected, dtype=float) / 255
        right = np.asarray(converted.convert("RGB"), dtype=float) / 255
    referenceLab = colour.XYZ_to_Lab(colour.sRGB_to_XYZ(left))
    actualLab = colour.XYZ_to_Lab(colour.sRGB_to_XYZ(right))
    differences = colour.delta_E(referenceLab, actualLab, method="CIE 2000")
    summary = {"meanDeltaE00": float(differences.mean()),
               "p95DeltaE00": float(np.quantile(differences, 0.95)),
               "maxDeltaE00": float(differences.max())}
    (OUTPUT / "lcms-reference.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    # 本次跨解码器/跨CMM工程容差，非设备校准或通用人眼可见阈值。
    assert summary["meanDeltaE00"] < 1
    assert summary["p95DeltaE00"] < 3
