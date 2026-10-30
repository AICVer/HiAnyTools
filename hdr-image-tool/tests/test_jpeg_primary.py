"""R8：原始JPEG主图隔离，保留扫描/ICC/EXIF并正确跳过缩略图标记。"""

import io

from PIL import Image, ImageCms
import pytest

from test_hdr_engine import imageDirectory, probe


def segment(marker, payload):
    """构造 JPEG 长度段，供独立 framing 用例使用。"""
    return bytes([255,marker]) + (len(payload)+2).to_bytes(2,"big") + payload


@pytest.mark.parametrize("progressive", [False, True])
def test_primary_keeps_exact_scan_icc_and_exif(probe, imageDirectory, progressive):
    original = imageDirectory / "original.jpg"
    exif = Image.Exif()
    exif[274] = 6
    exif[37510] = b"ASCII\0\0\0thumbnail-like bytes: \xff\xd8\xff\xda\x00\x02\xff\xd9"
    profile = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    Image.new("RGB", (40,60), (80,160,40)).save(original, quality=93,
        progressive=progressive, exif=exif, icc_profile=profile)
    originalBytes = original.read_bytes()
    second = io.BytesIO()
    Image.new("RGB", (4,4), "gray").save(second, format="JPEG")
    extra = segment(0xe1,b"http://ns.adobe.com/xap/1.0/\0<x:xmpmeta>HDR</x:xmpmeta>")
    extra += segment(0xe2,b"MPF\0diagnostic")
    extra += segment(0xe2,b"urn:iso:std:iso:ts:21496:-1\0diagnostic")
    source = imageDirectory / "container.jpg"
    source.write_bytes(originalBytes[:2]+extra+originalBytes[2:]+second.getvalue())
    before = source.read_bytes()
    output = imageDirectory / "primary.jpg"
    probe("jpeg-primary", source, output)
    assert output.read_bytes() == originalBytes
    assert source.read_bytes() == before
    with Image.open(output) as image:
        assert image.info["icc_profile"] == profile
        assert image.getexif()[274] == 6


@pytest.mark.parametrize("data", [b"notjpeg", b"\xff\xd8\xff\xe1\xff\xff",
    b"\xff\xd8\xff\xda\x00\x02\xff", b"\xff\xd8\xff\xe1\x00\x01"])
def test_truncated_primary_fails_without_output(probe, imageDirectory, data):
    source = imageDirectory / "broken.jpg"
    source.write_bytes(data)
    output = imageDirectory / "output.jpg"
    probe("jpeg-primary", source, output, success=False)
    assert not output.exists()
