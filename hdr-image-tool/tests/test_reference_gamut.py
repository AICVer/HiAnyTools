"""参考包络：闭合拓扑、原色/峰值语义和独立colour-science坐标对照。"""
from collections import Counter

import colour
import numpy as np
import pytest

from test_hdr_engine import probe


@pytest.mark.parametrize("gamut,name", [("sRGB","sRGB"),("Display P3","Display P3"),("BT.2020","ITU-R BT.2020")])
@pytest.mark.parametrize("peak", [203,600,1000,10000])
def test_mesh_matches_independent_reference(probe, gamut, name, peak):
    data = probe("reference-mesh",gamut,peak)
    source = colour.RGB_COLOURSPACES[name]
    rgb = np.array(data["boundaryRGB"])
    xyz = rgb @ colour.normalised_primary_matrix(source.primaries,source.whitepoint).T * peak/203
    expectedLab = colour.XYZ_to_Lab(xyz,illuminant=source.whitepoint)
    expectedCam = colour.XYZ_to_CAM16UCS(xyz,XYZ_w=colour.xy_to_XYZ(source.whitepoint),
        L_A=100,Y_b=20,discount_illuminant=True)
    work = xyz @ colour.RGB_COLOURSPACES['ITU-R BT.2020'].matrix_XYZ_to_RGB.T
    expectedICtCp = colour.RGB_to_ICtCp(work*203,method='ITU-R BT.2100-2 PQ')
    vertices = data["vertices"]
    assert all('cam16' in p and 'ictcp' in p for p in vertices)
    np.testing.assert_allclose([p['lab'] for p in vertices],expectedLab,atol=1e-5)
    np.testing.assert_allclose([p['cam16'] for p in vertices],expectedCam,atol=1e-5)
    np.testing.assert_allclose([p['ictcp'] for p in vertices],expectedICtCp,atol=1e-7)
    assert data['peakNits']==peak and data['gamut']==gamut
    white = np.flatnonzero(np.all(rgb==1,axis=1))
    black = np.flatnonzero(np.all(rgb==0,axis=1))
    assert len(white)==len(black)==1
    if peak == 203:
        assert abs(vertices[white[0]]['lab'][0]-100)<1e-6
    if peak == 10000:
        np.testing.assert_allclose(vertices[white[0]]['ictcp'],[1,0,0],atol=1e-7)


@pytest.mark.parametrize("divisions",[2,8,16])
def test_mesh_is_closed_outward_surface_not_convex_hull(probe, divisions):
    data=probe('reference-mesh','BT.2020',203,divisions)
    rgb=np.array(data['boundaryRGB'])
    faces=np.array(data['triangles'])
    assert len(rgb)==6*divisions**2+2
    assert len(faces)==12*divisions**2
    assert len(set(map(tuple,rgb)))==len(rgb)
    assert np.all(np.any((rgb==0)|(rgb==1),axis=1))
    edges=Counter()
    directed=Counter()
    for a,b,c in faces:
        assert len({a,b,c})==3
        for p,q in [(a,b),(b,c),(c,a)]:
            edges[tuple(sorted([p,q]))]+=1
            directed[(p,q)]+=1
        normal=np.cross(rgb[b]-rgb[a],rgb[c]-rgb[a])
        assert np.dot(normal,(rgb[a]+rgb[b]+rgb[c])/3-.5)>0
    assert set(edges.values())=={2}
    assert all(directed[(a,b)]==directed[(b,a)]==1 for a,b in edges)
    assert len(rgb)-len(edges)+len(faces)==2
    for a,b in data['edges']:
        assert tuple(sorted([a,b])) in edges
        assert np.count_nonzero(rgb[a]!=rgb[b])==1


@pytest.mark.parametrize("peak,divisions",[(0,8),(10001,8),('nan',8),(203,1),(203,17)])
def test_invalid_reference_parameters(probe,peak,divisions):
    assert probe('reference-mesh','sRGB',peak,divisions,success=False)


def test_icptcp_roundoff_tolerance_does_not_admit_real_overflow(probe):
    assert 'ictcp' in probe('coordinates',','.join([str(10000/203)]*3))
    assert 'ictcp' not in probe('coordinates',','.join([str(10000.01/203)]*3))
