# HDR Image Lab 图标

参考：`/Users/wangshupeng/Downloads/HueTools/HiMagic/packages/resources/icon.png`。

本地矢量重绘，保留深色底、光谱渐变轨道与三个彩色节点，中心改为高光星芒。参考文件只读；未上传图片或使用远程生成服务。

- 可编辑源：`AppIcon.svg`，1024×1024，满版深色底，不预制iOS圆角。
- App资源：`../Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`，8位RGB、无透明通道。
- Xcode主图标名称：`AppIcon`；由资源编译器生成设备所需尺寸。

本机重绘命令（项目根目录，复用系统Quick Look与已有ImageMagick，无安装依赖）：

```sh
mkdir -p output/icon-render
qlmanage -t -s 1024 -o output/icon-render artwork/AppIcon.svg
magick output/icon-render/AppIcon.svg.png -alpha off -colorspace sRGB -depth 8 PNG24:Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

ImageMagick当前SVG后端不能正确绘制此渐变，因此仅用于已栅格化PNG的格式整理；最终图已检查1024与64像素视图。
