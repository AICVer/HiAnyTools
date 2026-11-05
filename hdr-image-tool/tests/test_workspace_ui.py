"""在临时 Xcode 工程中测试真实 App 导航，不修改生产工程或签名。"""

from pathlib import Path
import json
import shutil
import subprocess
import uuid

from PIL import Image


PROJECT = Path(__file__).resolve().parents[1]


def test_workspace_empty_navigation():
    """四页均可进入，无图时导入入口可达，返回查看页不崩溃。"""
    output = PROJECT / "output" / "workspace-ui" / uuid.uuid4().hex
    output.mkdir(parents=True)
    project = output / "HDRImageLab.xcodeproj"
    shutil.copytree(PROJECT / "HDRImageLab.xcodeproj", project)
    (output / "Sources").symlink_to(PROJECT / "Sources", target_is_directory=True)
    (output / "UITests").mkdir()
    fixture = output / "fixture.png"
    image = Image.new("RGB", (128, 96))
    image.putdata([(x * 255 // 127, y * 255 // 95, (x + y) * 255 // 222)
                   for y in range(96) for x in range(128)])
    image.save(fixture)
    for source in sorted((PROJECT / "tests").glob("*UITests.swift")):
        (output / "UITests" / source.name).write_text(
            source.read_text().replace('"__WORKSPACE_TEST_IMAGE__"', json.dumps(str(fixture), ensure_ascii=False)))
    # 复用产品配置，仅给临时工程添加 UI 测试目标及 App 依赖。
    objects = '''
        B10000000000000000000001 = {isa = PBXNativeTarget; name = WorkspaceUITests;
            productName = WorkspaceUITests; productType = "com.apple.product-type.bundle.ui-testing";
            productReference = B10000000000000000000002;
            buildConfigurationList = B10000000000000000000003;
            buildPhases = (B10000000000000000000004, B10000000000000000000005,);
            dependencies = (B10000000000000000000006,);
            fileSystemSynchronizedGroups = (B10000000000000000000008,); };
        B10000000000000000000002 = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle;
            path = WorkspaceUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
        B10000000000000000000003 = {isa = XCConfigurationList;
            buildConfigurations = (B10000000000000000000009,);
            defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
        B10000000000000000000004 = {isa = PBXSourcesBuildPhase;
            buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
        B10000000000000000000005 = {isa = PBXFrameworksBuildPhase;
            buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
        B10000000000000000000006 = {isa = PBXTargetDependency;
            target = A10000000000000000000005; targetProxy = B10000000000000000000007; };
        B10000000000000000000007 = {isa = PBXContainerItemProxy;
            containerPortal = A10000000000000000000001; proxyType = 1;
            remoteGlobalIDString = A10000000000000000000005; remoteInfo = HDRImageLab; };
        B10000000000000000000008 = {isa = PBXFileSystemSynchronizedRootGroup;
            explicitFileTypes = {}; explicitFolders = (); path = UITests; sourceTree = "<group>"; };
        B10000000000000000000009 = {isa = XCBuildConfiguration; name = Debug;
            buildSettings = {GENERATE_INFOPLIST_FILE = YES; PRODUCT_NAME = "$(TARGET_NAME)";
                PRODUCT_BUNDLE_IDENTIFIER = local.hdrimagelab.uitests; SWIFT_VERSION = 5.0;
                IPHONEOS_DEPLOYMENT_TARGET = 18.0; TARGETED_DEVICE_FAMILY = 1;
                SDKROOT = iphoneos; TEST_TARGET_NAME = HDRImageLab; }; };
'''
    pbxPath = project / "project.pbxproj"
    pbx = pbxPath.read_text().replace("objects = {", "objects = {\n" + objects, 1)
    pbx = pbx.replace("targets = (", "targets = (B10000000000000000000001,", 1)
    pbx = pbx.replace("children = (", "children = (B10000000000000000000008,", 1)
    pbxPath.write_text(pbx)
    schemeDirectory = project / "xcshareddata" / "xcschemes"
    schemeDirectory.mkdir(parents=True, exist_ok=True)
    reference = ('<BuildableReference BuildableIdentifier="primary" '
                 'BlueprintIdentifier="B10000000000000000000001" '
                 'BuildableName="WorkspaceUITests.xctest" BlueprintName="WorkspaceUITests" '
                 'ReferencedContainer="container:HDRImageLab.xcodeproj"/>')
    (schemeDirectory / "WorkspaceUITests.xcscheme").write_text(
        '<?xml version="1.0" encoding="UTF-8"?><Scheme version="1.3">'
        '<BuildAction buildImplicitDependencies="YES"><BuildActionEntries>'
        '<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" '
        'buildForArchiving="NO" buildForAnalyzing="NO">' + reference +
        '</BuildActionEntry></BuildActionEntries></BuildAction>'
        '<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES">'
        '<Testables><TestableReference skipped="NO">' + reference +
        '</TestableReference></Testables></TestAction></Scheme>')
    listing = subprocess.run(["xcrun", "simctl", "list", "devices", "booted", "-j"],
                             capture_output=True, text=True, check=True)
    devices = [device for group in json.loads(listing.stdout)["devices"].values()
               for device in group if device["name"].startswith("iPhone")]
    assert devices, "请先启动一台 iPhone 模拟器，再运行本套 UI 测试。"
    with (output / "xcodebuild.txt").open("w") as log:
        result = subprocess.run([
            "xcodebuild", "-project", str(project), "-scheme", "WorkspaceUITests",
            "-destination", f'platform=iOS Simulator,id={devices[0]["udid"]}',
            "-derivedDataPath", str(output / "DerivedData"), "-resultBundlePath",
            str(output / "result.xcresult"), "-parallel-testing-enabled", "NO",
            "-enableCodeCoverage", "YES",
            "CODE_SIGNING_ALLOWED=NO", "test",
        ], stdout=log, stderr=subprocess.STDOUT, timeout=360)
    assert result.returncode == 0, f"UI 测试失败，详情：{output / 'xcodebuild.txt'}"
