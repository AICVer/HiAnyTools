#!/bin/zsh
# 在本机 base 环境启动窗口，路径包含空格时同样可用。
cd -- "${0:A:h}" || exit 1
exec /Users/wangshupeng/miniforge3/bin/conda run --no-capture-output -n base python image_to_pdf.py gui
