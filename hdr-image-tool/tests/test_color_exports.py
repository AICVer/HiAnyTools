"""新导出空间及灰度合成：以独立像素/元数据核对实际 Swift 输出。"""
import json
import io
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageCms
import pytest

from test_hdr_engine import probe, imageDirectory, sdr, pngChunks


def test_gray_composition_formula(probe, sdr):
    data = probe("compose", sdr, "self", 600 / 203)
    base = np.array(data["sdr"]).reshape(-1, 4)
    gray = np.array(data["gray"]).reshape(-1, 4)
    hdr = np.array(data["hdr"]).reshape(-1, 4)
    y = np.clip(base[:, :3] @ [0.2627, 0.6780, 0.0593], 0, 1)
    np.testing.assert_allclose(gray[:, 0], y, atol=2e-4)
    np.testing.assert_allclose(hdr[:, :3], base[:, :3] * (600 / 203) ** y[:, None], atol=5e-4)


@pytest.mark.parametrize("gain", [1, 4, 16])
def test_external_gray_alignment(probe, sdr, imageDirectory, gain):
    path = imageDirectory / "white.png"
    Image.new("RGB", (9, 3), (255, 255, 255)).save(path)
    data = probe("compose", sdr, path, gain)
    assert (data["width"], data["height"]) == (5, 1)
    np.testing.assert_allclose(np.array(data["hdr"]).reshape(-1, 4)[:, :3],
                               np.array(data["sdr"]).reshape(-1, 4)[:, :3] * gain, atol=.003)


@pytest.mark.parametrize("gain", [0, -1, 17, "nan"])
def test_gain_rejects_invalid(probe, sdr, gain):
    assert "增益" in probe("compose", sdr, "self", gain, success=False)


@pytest.mark.parametrize("space", ["BT.2020", "Display P3"])
@pytest.mark.parametrize("fmt", ["GainMap JPEG", "GainMap HEIC"])
def test_gainmap_export(probe, imageDirectory, space, fmt):
    source = imageDirectory / "base.png"
    Image.new("RGB", (64, 64), (220, 220, 220)).save(source)
    opts = {"hdrColorSpace": space, "quality": 1, "dpi": 300}
    path = probe("compose", source, "self", 4, fmt, json.dumps(opts), imageDirectory)["path"]
    meta = probe("meta", path)
    assert meta["hasISOGainMap"]
    assert meta["rawContainerType"] == ("public.jpeg" if fmt.endswith("JPEG") else "public.heic")
    assert meta["maxRGB"] > 1.7
    assert meta["rawWidth"] == 64
    assert "2020" in meta["profileName"] if space == "BT.2020" else "P3" in meta["profileName"]
    expected = probe("compose", source, "self", 4)
    expected = np.array(expected["hdr"]).reshape(-1, 4)[:, :3].mean()
    assert abs(meta["maxRGB"] - expected) / expected < .05
    assert abs(meta["dpiWidth"] - 300) < 1


@pytest.mark.parametrize("fmt", ["PNG", "TIFF"])
def test_p3_pq_export(probe, sdr, imageDirectory, fmt):
    path = probe("hdr-options", sdr, fmt, 600, json.dumps({"hdrColorSpace": "Display P3"}), imageDirectory)["path"]
    info = probe("inspect", path)
    assert "P3" in info["space"] and "PQ" in info["space"]
    assert abs(max(info["linear"]) - 600 / 203) < .01
    if fmt == "PNG":
        assert pngChunks(Path(path))[b"cICP"][:2] == bytes([12, 16])


@pytest.mark.parametrize("space", ["sRGB", "Display P3", "Adobe RGB"])
@pytest.mark.parametrize("fmt", ["PNG", "JPEG", "HEIC", "BMP"])
def test_sdr_space_roundtrip(probe, sdr, imageDirectory, space, fmt):
    if fmt == "BMP" and space != "sRGB":
        assert "色彩空间" in probe("sdr-options", sdr, fmt, json.dumps({"sdrColorSpace": space}), imageDirectory, success=False)
        return
    path = probe("sdr-options", sdr, fmt, json.dumps({"sdrColorSpace": space}), imageDirectory)["path"]
    meta = probe("meta", path)
    token = {"sRGB": "sRGB", "Display P3": "P3", "Adobe RGB": "Adobe"}[space]
    if fmt == "BMP":
        assert max(probe("inspect", path)["linear"]) > .98
    else:
        assert token in meta["profileName"]


def test_rgb_passthrough_keeps_source_codes(probe, imageDirectory):
    original = imageDirectory / "source.png"
    Image.new("RGB", (32, 32), (180, 70, 40)).save(original)
    p3 = probe("sdr-options", original, "PNG", json.dumps({"sdrColorSpace": "Display P3"}), imageDirectory)["path"]
    direct = probe("sdr-options", p3, "PNG", json.dumps({"sdrColorSpace": "Adobe RGB", "sdrMapping": "RGB 直通"}), imageDirectory)["path"]
    xyz = probe("sdr-options", p3, "PNG", json.dumps({"sdrColorSpace": "Adobe RGB"}), imageDirectory)["path"]
    a, b, c = [np.array(Image.open(p).convert("RGB"), dtype=float) for p in (p3, direct, xyz)]
    assert np.max(abs(a-b)) <= 1
    assert np.max(abs(b-c)) > 5
    sourceProfile = ImageCms.ImageCmsProfile(io.BytesIO(Image.open(p3).info["icc_profile"]))
    targetProfile = ImageCms.ImageCmsProfile(io.BytesIO(Image.open(xyz).info["icc_profile"]))
    reference = ImageCms.profileToProfile(Image.open(p3).convert("RGB"), sourceProfile, targetProfile, renderingIntent=1)
    assert np.max(abs(np.array(reference, dtype=float)-c)) <= 2


def test_center_crop_and_transparent_gain_source(probe, imageDirectory):
    base = imageDirectory / "base.png"
    gray = imageDirectory / "gray.png"
    Image.new("RGBA", (16,16), (150,100,50,128)).save(base)
    values = np.zeros((16,48,4), dtype=np.uint8)
    values[:,:,3] = 255
    values[:,16:32,:] = 255
    Image.fromarray(values).save(gray)
    data = probe("compose", base, gray, 4)
    before = np.array(data["sdr"]).reshape(-1,4)
    after = np.array(data["hdr"]).reshape(-1,4)
    np.testing.assert_allclose(after[:,:3], before[:,:3]*4, atol=.001)
    np.testing.assert_allclose(after[:,3], before[:,3], atol=1e-6)
    Image.new("RGBA", (16,16), (255,255,255,0)).save(gray)
    noGain = probe("compose", base, gray, 4)
    np.testing.assert_allclose(noGain["hdr"],noGain["sdr"],atol=1e-6)


@pytest.mark.parametrize("fmt", ["GainMap JPEG", "GainMap HEIC"])
def test_gainmap_budget_resize_and_hdr_preservation(probe, imageDirectory, fmt):
    source = imageDirectory / "gain.jpg"
    probe("gainmap", source)
    opts = {"width":32, "targetBytes":50000, "hdrColorSpace":"Display P3"}
    path = probe("hdr-options",source,fmt,203,json.dumps(opts),imageDirectory)["path"]
    assert Path(path).stat().st_size <= 50000
    meta=probe("meta",path)
    assert meta["rawWidth"] == 32 and meta["hasISOGainMap"]
    expected=probe("meta",source)["maxRGB"]
    assert abs(meta["maxRGB"]-expected)/expected < .06
    opts["targetBytes"]=1
    assert "无法达到" in probe("hdr-options",source,fmt,203,json.dumps(opts),imageDirectory,success=False)


def test_bmp_embedded_profile_drives_native_read(probe, imageDirectory):
    # 本机原生解码拒绝V5 ICC：生产必须拒绝该输出组合，不能谎报保留了P3。
    source=imageDirectory / "color.png"
    Image.new("RGB",(16,16),(150,80,40)).save(source)
    png=probe("sdr-options",source,"PNG",json.dumps({"sdrColorSpace":"Display P3"}),imageDirectory)["path"]
    assert "色彩空间" in probe("sdr-options",source,"BMP",json.dumps({"sdrColorSpace":"Display P3"}),imageDirectory,success=False)
    assert Path(png).exists()


def test_p3_clli_uses_output_rgb_not_working_rgb(probe, imageDirectory):
    original=imageDirectory / "red.png"
    Image.new("RGB",(16,16),(255,0,0)).save(original)
    p3=probe("sdr-options",original,"PNG",json.dumps({"sdrColorSpace":"Display P3","sdrMapping":"RGB 直通"}),imageDirectory)["path"]
    pq=probe("hdr-options",p3,"PNG",203,json.dumps({"hdrColorSpace":"Display P3"}),imageDirectory)["path"]
    maxCLL,maxFALL=struct.unpack(">II",pngChunks(Path(pq))[b"cLLI"])
    assert abs(maxCLL/10000-203) < .1
    assert abs(maxFALL/10000-203) < .1


@pytest.mark.parametrize("gain", [1,4])
@pytest.mark.parametrize("fmt", ["GainMap JPEG","GainMap HEIC"])
def test_colored_p3_gainmap_preserves_linear_rgb(probe, imageDirectory, gain, fmt):
    original=imageDirectory / "red.png"
    gray=imageDirectory / "gray.png"
    Image.new("RGB",(64,64),(220,80,50)).save(original)
    Image.new("RGB",(64,64),(255,255,255)).save(gray)
    p3=probe("sdr-options",original,"PNG",json.dumps({"sdrColorSpace":"Display P3","sdrMapping":"RGB 直通"}),imageDirectory)["path"]
    expected=np.array(probe("compose",p3,gray,gain)["hdr"]).reshape(-1,4)[:,:3].mean(axis=0)
    if gain == 1:
        assert "未超过 SDR 参考白" in probe("compose",p3,gray,gain,fmt,json.dumps({"hdrColorSpace":"Display P3","quality":1}),imageDirectory,success=False)
        return
    path=probe("compose",p3,gray,gain,fmt,json.dumps({"hdrColorSpace":"Display P3","quality":1}),imageDirectory)["path"]
    actual=np.array(probe("inspect",path)["linear"]).reshape(-1,4)[:,:3].mean(axis=0)
    np.testing.assert_allclose(actual,expected,atol=.015,rtol=.06)
