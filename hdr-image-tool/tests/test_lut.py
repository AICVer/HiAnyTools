"""sRGB码值输入/线性BT.2020输出的真实GPU执行；HiEnhance独立三线性对照。"""
from pathlib import Path
import sys

import numpy as np
import pytest
from PIL import Image

from test_hdr_engine import probe, imageDirectory


def writeCube(path: Path, size: int, function, domain: tuple = (0, 1)) -> Path:
    """生成R最快排列的合成LUT。"""
    values = [function(np.array([r, g, b]) / (size-1))
              for b in range(size) for g in range(size) for r in range(size)]
    header = [f'LUT_3D_SIZE {size}', 'DOMAIN_MIN '+' '.join([str(domain[0])]*3),
              'DOMAIN_MAX '+' '.join([str(domain[1])]*3)]
    path.write_text('\n'.join(header + [' '.join(map(str, row)) for row in values]))
    return path


def test_encoded_input_and_linear_output_not_double_decoded(probe, imageDirectory):
    cube = writeCube(imageDirectory/'affine.cube', 2, lambda p: p*[2,3,4] - [.1,.2,.3])
    colors = np.array([[.4,.6,.8,1], [.8,.2,.1,.5], [0,0,0,1], [1,1,1,1]])
    # 半透明输入必须预乘，色表值仍是直通色。
    inputs = colors.copy()
    inputs[:, :3] *= inputs[:, 3:]
    actual = np.array(probe('lut-sample', cube, ','.join(map(str,inputs.ravel())))['pixels']).reshape(-1,4)
    expected = colors.copy()
    expected[:,:3] = (colors[:,:3]*[2,3,4]-[.1,.2,.3])*colors[:,3:]
    np.testing.assert_allclose(actual, expected, atol=2e-5)


def test_domain_is_applied_and_outside_input_is_clamped(probe, imageDirectory):
    cube = writeCube(imageDirectory/'domain.cube', 2, lambda p: p, (.2,.8))
    data = probe('lut-sample', cube, '.1,.5,.9,1')['pixels']
    np.testing.assert_allclose(data[:3], [0,.5,1], atol=2e-5)


@pytest.mark.parametrize('text', ['LUT_3D_SIZE 1', 'LUT_1D_SIZE 2\n0 0 0',
    'LUT_3D_SIZE 2\n0 0 0', 'LUT_3D_SIZE 2\nNaN 0 0', 'LUT_3D_SIZE 1000000'])
def test_invalid_lut_is_rejected(probe, imageDirectory, text):
    cube = imageDirectory/'invalid.cube'
    cube.write_text(text)
    assert probe('lut-sample', cube, '0,0,0,1', success=False)


def test_real_user_lut_matches_hi_enhance_trilinear(probe):
    root = Path('/Users/wangshupeng/Downloads/HueTools/HiEnhance')
    cube = root/'results/bt709_to_bt2020_catd65_linear.cube'
    if not cube.exists():
        pytest.skip('本机指定LUT不可用')
    sys.path.insert(0, str(root))
    previous = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        from hienhance.lutio import parseCubeFile, buildLutGrid
        from hienhance.interp import applyLutTrilinear
    finally:
        sys.dont_write_bytecode = previous
    size, values = parseCubeFile(cube)
    rgb = np.random.default_rng(23).uniform(.02,.98,(50,3))
    rgba = np.column_stack([rgb,np.ones(len(rgb))])
    actual = np.array(probe('lut-sample', cube, ','.join(map(str,rgba.ravel())))['pixels']).reshape(-1,4)
    np.testing.assert_allclose(actual[:,:3], applyLutTrilinear(buildLutGrid(values,size),rgb), atol=2e-5)


def test_lut_changes_distribution_and_exports_bt2020(probe, imageDirectory):
    cube = writeCube(imageDirectory/'red.cube', 2, lambda p: np.array([.5,0,0]))
    source = imageDirectory/'source.png'
    Image.new('RGB',(8,8),(80,120,160)).save(source)
    distribution = probe('lut-distribution', cube, source)
    np.testing.assert_allclose(distribution['points'][0]['xy'], [.708,.292], atol=.0002)
    exported = probe('lut-export', cube, source, '{"sdrColorSpace":"BT.2020"}', imageDirectory)
    assert Path(exported['path']).exists()


def test_hdr_source_is_rejected(probe, imageDirectory):
    cube = writeCube(imageDirectory/'identity.cube', 2, lambda p: p)
    source = imageDirectory/'hdr.png'
    probe('hdrfixture', source)
    assert probe('lut-distribution', cube, source, success=False)


def test_comments_and_bom_are_supported(probe, imageDirectory):
    cube = writeCube(imageDirectory/'comments.cube', 2, lambda p: p)
    cube.write_text('\ufeff# 测试说明\nTITLE "example"\n'+cube.read_text()+'\n# done\n')
    actual = probe('lut-sample', cube, '.25,.5,.75,1')['pixels']
    np.testing.assert_allclose(actual[:3], [.25,.5,.75], atol=2e-5)


def test_invalid_domain_is_rejected(probe, imageDirectory):
    cube = writeCube(imageDirectory/'bad-domain.cube', 2, lambda p: p, (1, 1))
    assert probe('lut-sample', cube, '0,0,0,1', success=False)
