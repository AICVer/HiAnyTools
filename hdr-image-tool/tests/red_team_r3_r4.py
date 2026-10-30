"""红军门禁 2：真实 HDR/GainMap 识别与带余量的浮点预览。"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import uuid

import pytest


PROJECT = Path(__file__).resolve().parents[1]
ROOT = Path("/Users/wangshupeng/workspace/项目工作/画质研发团队/📚画质技术栈📚/技术洞察 | 画质技术标准/技术标准 | Gainmap")
OUTPUT = PROJECT / "output/red-team/round2"
CASES = [
    ("sdr", "GainMap-vs-HDR/sdrOriginal.jpg", False, False),
    ("pq-png", "hdr/b614d537-4817-46fc-9120-498f090161e2.png", True, False),
    ("pq-avif", "PQ-RGBW.avif", True, False),
    ("pq-heic", "1. ISO_22028-5_HDR_PQ_4.93/image_001_HDR_PQ_4.93.heic", True, False),
    ("apple", "IMG_3853.HEIC", True, True),
    ("iso-heic", "4. ISO_21496-1_Adaptive_HDR/image_025_AdaptiveHDR.heic", True, True),
    ("dual-jpeg", "GainMap-vs-HDR/gainMap.jpg", True, True),
    ("adobe-jpeg", "Ultra_HDR_Samples/Originals/Ultra_HDR_Samples_Originals_01.jpg", True, True),
]


@pytest.fixture(scope="session")
def round2Probe():
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


@pytest.mark.parametrize("kind,name,hdr,gain", CASES)
def test_actual_file_encoding_and_gainmap_classification(round2Probe, kind, name, hdr, gain):
    path = ROOT / name
    data = path.read_bytes()
    before = hashlib.sha256(data).hexdigest()
    info = round2Probe("meta", path)
    if data.startswith(b"\xff\xd8"):
        expectedType = "public.jpeg"
    elif data.startswith(b"\x89PNG\r\n\x1a\n"):
        expectedType = "public.png"
    else:
        assert data[4:8] == b"ftyp"
        expectedType = "public.avif" if b"avif" in data[8:32] else "public.heic"
    assert info["type"] == expectedType, "HDR 内部表示不得冒充原始容器格式"
    assert info["rawContainerType"] == expectedType
    assert info["isHDR"] == hdr
    assert (info["hasAppleGainMap"] or info["hasISOGainMap"]) == gain
    assert info["orientedWidth"] > 0 and info["orientedHeight"] > 0
    if hdr:
        assert info["maxRGB"] > 1, f"{kind} HDR 重建或解码缺少超参考白像素"
    assert hashlib.sha256(path.read_bytes()).hexdigest() == before
    (OUTPUT / f"{kind}-meta.json").write_text(json.dumps(info, indent=2), encoding="utf-8")


@pytest.mark.parametrize("kind,name,hdr,gain", [case for case in CASES if case[2]])
def test_hdr_preview_retains_extended_values_and_explicit_headroom(round2Probe, kind, name, hdr, gain):
    preview = round2Probe("preview-meta", ROOT / name, "HDR", 203)
    assert max(preview["width"], preview["height"]) <= 2048
    assert preview["bitsPerComponent"] == 16
    assert preview["contentHeadroom"] > 1
    assert preview["maxRGB"] > 1
    assert preview["contentHeadroom"] + max(0.01, preview["maxRGB"] * 0.001) >= preview["maxRGB"], \
        "headroom 不足以描述预览超白像素，可能导致系统映射裁切"
    assert "Linear" in preview["colorSpace"] or "linear" in preview["colorSpace"]
    (OUTPUT / f"{kind}-preview.json").write_text(json.dumps(preview, indent=2), encoding="utf-8")


@pytest.mark.parametrize("kind,name,hdr,gain", CASES)
def test_sdr_preview_is_separate_eight_bit_surface(round2Probe, kind, name, hdr, gain):
    preview = round2Probe("preview-meta", ROOT / name, "SDR", 600)
    assert preview["bitsPerComponent"] == 8
    assert preview["maxRGB"] <= 1.02
    assert preview["contentHeadroom"] <= 1


def test_hdr_tagging_does_not_turn_sdr_into_hdr_source(round2Probe):
    source = ROOT / "GainMap-vs-HDR/sdrOriginal.jpg"
    infoBefore = round2Probe("meta", source)
    round2Probe("preview-meta", source, "HDR", 600)
    infoAfter = round2Probe("meta", source)
    assert not infoBefore["isHDR"] and not infoAfter["isHDR"]
    assert infoBefore["maxRGB"] == infoAfter["maxRGB"]
