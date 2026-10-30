"""红军最终门禁：直方图域/计数/透明及真实 GainMap 三视图。"""

from __future__ import annotations

import hashlib
import io
import json
from pathlib import Path
import subprocess
import uuid

import colour
import numpy as np
from PIL import Image, ImageCms
import pytest


PROJECT = Path(__file__).resolve().parents[1]
ROOT = Path("/Users/wangshupeng/workspace/项目工作/画质研发团队/📚画质技术栈📚/技术洞察 | 画质技术标准/技术标准 | Gainmap")
OUTPUT = PROJECT / "output/red-team/round4"
GAINMAPS = [
    "IMG_3853.HEIC",
    "4. ISO_21496-1_Adaptive_HDR/image_025_AdaptiveHDR.heic",
    "GainMap-vs-HDR/gainMap.jpg",
    "Ultra_HDR_Samples/Originals/Ultra_HDR_Samples_Originals_01.jpg",
]


@pytest.fixture(scope="session")
def round4Probe():
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
    assert before == after, "门禁期间源码变化，结论无效"


@pytest.fixture
def round4Folder():
    folder = OUTPUT / "files" / uuid.uuid4().hex
    folder.mkdir(parents=True)
    return folder


def saveSRGB(image: Image.Image, path: Path) -> Path:
    """明确嵌入sRGB，避免缺失ICC时的隐式空间解释干扰参考。"""
    profile = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    image.save(path, icc_profile=profile)
    return path


def meanOfBins(channel: dict) -> float:
    """从公开轴范围和桶计数估算均值，容差按桶宽设置。"""
    counts = np.asarray(channel["bins"], dtype=float)
    assert len(counts) == 256 and counts.sum() > 0
    step = (channel["upperBound"] - channel["lowerBound"]) / 256
    centers = channel["lowerBound"] + (np.arange(256) + 0.5) * step
    return float(np.dot(centers, counts) / counts.sum())


def assertConserved(report: dict) -> None:
    """验证所有有效/透明/非法像素与七通道计数守恒。"""
    assert report["sampledPixelCount"] == report["sampledWidth"] * report["sampledHeight"]
    assert report["hdrPixelCount"] + report["transparentHDRCount"] + report["invalidHDRCount"] == report["sampledPixelCount"]
    assert report["hsvPixelCount"] + report["transparentSDRCount"] == report["sampledPixelCount"]
    assert set(report["channels"]) == set("RGBYHSV")
    for name, channel in report["channels"].items():
        assert len(channel["bins"]) == 256
        assert all(isinstance(value, int) and value >= 0 for value in channel["bins"])
        count = sum(channel["bins"]) + channel["underflowCount"] + channel["overflowCount"] + channel["undefinedCount"]
        assert count == report["hdrPixelCount"] if name in "RGBY" else count == report["hsvPixelCount"]


@pytest.mark.parametrize("rgb,hue", [((255,0,0),0), ((0,255,0),120), ((0,0,255),240)])
def test_primary_colors_have_independent_linear_and_hsv_domains(round4Probe, round4Folder, rgb, hue):
    path = saveSRGB(Image.new("RGB", (32,16), rgb), round4Folder / "color.png")
    report = round4Probe("histogram", path, 203)
    assertConserved(report)
    expected = colour.RGB_to_RGB(np.asarray(rgb)/255, "sRGB", "ITU-R BT.2020",
                                 apply_cctf_decoding=True, apply_cctf_encoding=False)
    for index, name in enumerate("RGB"):
        channel = report["channels"][name]
        step = (channel["upperBound"] - channel["lowerBound"]) / 256
        assert abs(meanOfBins(channel) - expected[index]) <= 2 * step + 0.002
    y = report["channels"]["Y"]
    expectedY = float(np.dot(expected, [0.2627,0.6780,0.0593]) * 203)
    assert abs(meanOfBins(y) - expectedY) <= 2 * (y["upperBound"]-y["lowerBound"]) / 256 + 0.3
    assert abs(meanOfBins(report["channels"]["H"]) - hue) <= 360 / 256
    for name in "SV":
        assert report["channels"][name]["bins"][-1] == 512
    assert "2020" in report["hdrDomain"] and "nit" in report["hdrDomain"].lower()
    assert "srgb" in report["hsvDomain"].lower()


def test_gray_separates_linear_rgb_from_encoded_hsv_value(round4Probe, round4Folder):
    source = saveSRGB(Image.new("RGB", (32,16), (128,128,128)), round4Folder / "gray.png")
    report = round4Probe("histogram", source, 203)
    assertConserved(report)
    linear = float(colour.models.eotf_sRGB(128/255))
    assert abs(meanOfBins(report["channels"]["R"]) - linear) < 0.01
    assert abs(meanOfBins(report["channels"]["V"]) - 128/255) < 0.005
    assert report["channels"]["H"]["undefinedCount"] == 512
    assert sum(report["channels"]["H"]["bins"]) == 0
    assert report["channels"]["S"]["bins"][0] == 512


def test_partial_alpha_unpremultiplies_and_zero_alpha_is_excluded(round4Probe, round4Folder):
    image = Image.new("RGBA", (6,1))
    image.putdata([(255,0,0,255),(255,0,0,128),(255,0,0,0),
                   (128,128,128,255),(128,128,128,128),(128,128,128,0)])
    source = saveSRGB(image, round4Folder / "alpha.png")
    report = round4Probe("histogram", source, 203)
    assertConserved(report)
    assert report["hdrPixelCount"] == report["hsvPixelCount"] == 4
    assert report["transparentHDRCount"] == report["transparentSDRCount"] == 2
    assert report["channels"]["H"]["undefinedCount"] == 2
    red = colour.RGB_to_RGB([1,0,0], "sRGB", "ITU-R BT.2020",
                           apply_cctf_decoding=True, apply_cctf_encoding=False)
    gray = float(colour.models.eotf_sRGB(128/255))
    assert abs(meanOfBins(report["channels"]["R"]) - (red[0] + gray) / 2) < 0.012


def test_completely_transparent_image_has_no_fake_statistics(round4Probe, round4Folder):
    source = saveSRGB(Image.new("RGBA", (16,8), (255,0,255,0)), round4Folder / "clear.png")
    report = round4Probe("histogram", source, 600)
    assertConserved(report)
    assert report["hdrPixelCount"] == report["hsvPixelCount"] == 0
    assert report["transparentHDRCount"] == report["transparentSDRCount"] == 128
    assert all(sum(channel["bins"]) == 0 for channel in report["channels"].values())


def test_hdr_values_and_nits_not_clipped_to_sdr(round4Probe, round4Folder):
    source = round4Folder / "1000.png"
    round4Probe("hdrfixture", source)
    first = round4Probe("histogram", source, 203)
    second = round4Probe("histogram", source, 600)
    assertConserved(first)
    assert first["channels"] == second["channels"]
    assert first["channels"]["R"]["upperBound"] > 4.9
    assert first["channels"]["Y"]["upperBound"] > 990
    assert abs(meanOfBins(first["channels"]["R"]) - (1 + 1000/203) / 2) < 0.05
    assert abs(meanOfBins(first["channels"]["Y"]) - 601.5) < 9


def test_sdr_enhancement_changes_hdr_histogram_but_not_source_hsv(round4Probe, round4Folder):
    source = round4Folder / "sdr.png"
    round4Probe("fixture", source)
    low = round4Probe("histogram", source, 203)
    high = round4Probe("histogram", source, 600)
    assertConserved(low)
    assertConserved(high)
    assert meanOfBins(high["channels"]["Y"]) > meanOfBins(low["channels"]["Y"]) + 80
    for name in "HSV":
        assert low["channels"][name] == high["channels"][name]


def test_sampling_limit_orientation_and_labels(round4Probe, round4Folder):
    source = saveSRGB(Image.new("RGB", (1536,1024), "red"), round4Folder / "large.png")
    report = round4Probe("histogram", source, 203)
    assertConserved(report)
    assert max(report["sampledWidth"], report["sampledHeight"]) == 512
    assert (report["originalWidth"], report["originalHeight"]) == (1536,1024)
    assert abs(report["sampledHeight"] - report["sampledWidth"] * 2/3) <= 1
    one = round4Probe("histogram", source, 203, 1)
    assert one["sampledPixelCount"] == 1
    assertConserved(one)
    rotated = round4Folder / "rotated.jpg"
    exif = Image.Exif()
    exif[274] = 6
    profile = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    Image.new("RGB", (80,48), "red").save(rotated, exif=exif, icc_profile=profile)
    oriented = round4Probe("histogram", rotated, 203, 50)
    assert (oriented["originalWidth"], oriented["originalHeight"]) == (48,80)
    assert (oriented["sampledWidth"], oriented["sampledHeight"]) == (30,50)
    assertConserved(oriented)


@pytest.mark.parametrize("limit", [0,-1,2049])
def test_invalid_sampling_limit_is_rejected(round4Probe, round4Folder, limit):
    source = saveSRGB(Image.new("RGB", (8,8), "white"), round4Folder / "input.png")
    round4Probe("histogram", source, 203, limit, success=False)


@pytest.mark.parametrize("name", GAINMAPS)
def test_actual_gainmaps_have_three_distinct_preview_paths(round4Probe, name):
    path = ROOT / name
    original = hashlib.sha256(path.read_bytes()).hexdigest()
    hdr = round4Probe("preview-meta", path, "HDR", 203)
    sdr = round4Probe("preview-meta", path, "SDR", 203)
    gain = round4Probe("preview-meta", path, "GainMap", 203)
    assert hdr["bitsPerComponent"] == 16 and hdr["maxRGB"] > 1
    assert sdr["bitsPerComponent"] == gain["bitsPerComponent"] == 8
    assert sdr["maxRGB"] <= 1.02 and gain["maxRGB"] <= 1.02
    assert gain["width"] > 0 and gain["height"] > 0
    assert hashlib.sha256(path.read_bytes()).hexdigest() == original


def test_real_pq_sampling_is_conserved_with_underflow_visible(round4Probe):
    path = ROOT / "PQ-RGBW.avif"
    report = round4Probe("histogram", path, 203)
    assertConserved(report)
    assert report["channels"]["R"]["upperBound"] > 49
    assert report["channels"]["Y"]["upperBound"] > 9900
    assert sum(report["channels"]["Y"]["bins"]) > 0


def test_missing_gainmap_never_produces_fake_gainmap_image(round4Probe, round4Folder):
    source = saveSRGB(Image.new("RGB", (8,8), "white"), round4Folder / "plain.png")
    assert "GainMap" in round4Probe("preview-meta", source, "GainMap", 203, success=False)


def test_gainmap_sdr_view_matches_independently_decoded_primary(round4Probe, round4Folder):
    source = ROOT / "GainMap-vs-HDR/gainMap.jpg"
    result = Path(round4Probe("sdr-export", source, "PNG", round4Folder)["path"])
    with Image.open(source) as original, Image.open(result) as converted:
        profile = ImageCms.ImageCmsProfile(io.BytesIO(original.info["icc_profile"]))
        expected = ImageCms.profileToProfile(original, profile, ImageCms.createProfile("sRGB"),
                                            renderingIntent=1, outputMode="RGB")
        left = np.asarray(expected,dtype=float) / 255
        right = np.asarray(converted.convert("RGB"),dtype=float) / 255
    difference = colour.delta_E(colour.XYZ_to_Lab(colour.sRGB_to_XYZ(left)),
                               colour.XYZ_to_Lab(colour.sRGB_to_XYZ(right)), method="CIE 2000")
    summary = {"meanDeltaE00":float(difference.mean()),"p95DeltaE00":float(np.quantile(difference,.95))}
    (OUTPUT / "sdr-primary-reference.json").write_text(json.dumps(summary,indent=2),encoding="utf-8")
    assert summary["meanDeltaE00"] < 1 and summary["p95DeltaE00"] < 3
