"""像素凸包：用SciPy独立核对包含性、体积和退化数据。"""
from collections import Counter
import json

import numpy as np
import pytest
from scipy.spatial import ConvexHull

from test_hdr_engine import probe


@pytest.mark.parametrize('seed', [1,23,42])
def test_3d_hull_contains_samples_and_matches_volume(probe, seed):
    points = np.random.default_rng(seed).normal(size=(180,3))
    actual = probe('pixel-hull', json.dumps(points.tolist()))
    vertices = np.array(actual['vertices'])
    faces = np.array(actual['triangles'])
    assert actual['dimension'] == 3
    edges = Counter(tuple(sorted(pair)) for a,b,c in faces for pair in [(a,b),(b,c),(c,a)])
    assert set(edges.values()) == {2}
    assert len(vertices)-len(edges)+len(faces) == 2
    volume = 0
    for a,b,c in vertices[faces]:
        normal = np.cross(b-a,c-a)
        assert np.max((points-a)@normal) < 1e-7
        volume += np.dot(a,np.cross(b,c))/6
    assert volume == pytest.approx(ConvexHull(points).volume, rel=1e-8)


@pytest.mark.parametrize('points,dimension', [([], -1), ([[1,2,3]]*4,0),
    ([[i,2*i,3*i] for i in range(10)],1),
    ([[x,y,3*x+2*y] for x in range(3) for y in range(3)],2)])
def test_degenerate_cloud_does_not_invent_volume(probe, points, dimension):
    result = probe('pixel-hull',json.dumps(points))
    assert result['dimension'] == dimension
    if dimension < 2:
        assert result['triangles'] == []


def test_2d_polygon_matches_independent_hull(probe):
    points = np.random.default_rng(23).uniform(size=(100,2))
    actual = probe('pixel-polygon',json.dumps(points.tolist()))['vertices']
    expected = points[ConvexHull(points).vertices]
    assert set(map(tuple,actual)) == set(map(tuple,expected))


@pytest.mark.parametrize('points,count', [([],0), ([[1,2]]*4,1), ([[i,2*i] for i in range(10)],2)])
def test_2d_degenerate_boundary(probe, points, count):
    assert len(probe('pixel-polygon',json.dumps(points))['vertices']) == count


def test_cube_facets_are_closed_with_coplanar_corners(probe):
    points = [[x,y,z] for x in [0,1] for y in [0,1] for z in [0,1]]
    mesh = probe('pixel-hull',json.dumps(points))
    assert len(mesh['vertices']) == 8
    assert len(mesh['triangles']) == 12


def test_real_image_lut_hulls_cover_both_point_clouds(probe):
    from pathlib import Path
    source = Path('/Users/wangshupeng/Downloads/IMG_3920.JPG')
    cube = Path('/Users/wangshupeng/Downloads/HueTools/HiEnhance/results/bt709_to_bt2020_catd65_linear.cube')
    if not source.exists() or not cube.exists():
        pytest.skip('用户指定本机测试数据不可用')
    before = probe('distribution', source, 203)
    after = probe('lut-distribution', cube, source)
    assert (before['width'],before['height']) == (after['width'],after['height'])
    assert len(before['points']) == len(after['points'])
    for data in (before, after):
        for name in ['lab','cam16','ictcp']:
            points = np.array([p[name] for p in data['points'] if name in p])
            mesh = probe('pixel-hull',json.dumps(points.tolist()))
            assert mesh['dimension'] == 3
            vertices = np.array(mesh['vertices'])
            volume = 0
            for a,b,c in vertices[np.array(mesh['triangles'])]:
                normal = np.cross(b-a,c-a)
                # 相对曲面尺度的数值容差；不以凸包代替真实设备边界。
                assert np.max((points-a)@normal) <= 1e-7*max(1,np.linalg.norm(normal))
                volume += np.dot(a,np.cross(b,c))/6
            assert volume == pytest.approx(ConvexHull(points).volume, rel=1e-6)
