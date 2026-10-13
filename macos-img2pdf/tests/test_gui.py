"""真实 Tk 控件与转换线程协作测试，需本机桌面会话。"""

from pathlib import Path
import gc
import time
import tkinter as tk
from unittest.mock import Mock

from PIL import Image
import pytest

import image_to_pdf_gui as gui


@pytest.fixture
def app() -> gui.ConverterApp:
    """构造隐藏的真实窗口，并在测试后清理。"""
    # Tk 对象必须在主线程回收，避免前一个用例的窗口被工作线程 GC 回收。
    gc.collect()
    root = tk.Tk()
    root.withdraw()
    converter = gui.ConverterApp(root)
    yield converter
    root.destroy()
    del converter, root
    gc.collect()


@pytest.fixture
def photo(tmp_path: Path) -> Path:
    """准备有效图片。"""
    path = tmp_path / "photo.png"
    with Image.new("RGB", (60, 40), "red") as image:
        image.save(path)
    return path


def test_select_clear_and_cancel(app: gui.ConverterApp, photo: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """文件与文件夹选择去重、保存目录选择和取消操作有效。"""
    monkeypatch.setattr(gui.filedialog, "askopenfilenames", lambda **kwargs: [str(photo)])
    app.chooseFiles()
    monkeypatch.setattr(gui.filedialog, "askdirectory", lambda **kwargs: str(photo.parent))
    app.chooseFolder()
    assert app.paths == [photo]
    app.chooseOutput()
    assert app.outputDir.get() == str(photo.parent)
    monkeypatch.setattr(gui.filedialog, "askopenfilenames", lambda **kwargs: ())
    monkeypatch.setattr(gui.filedialog, "askdirectory", lambda **kwargs: "")
    app.chooseFiles()
    app.chooseFolder()
    app.chooseOutput()
    assert app.paths == [photo]
    app.clearFiles()
    assert app.paths == []
    assert app.table.get_children() == ()


def test_validation_and_busy_close(app: gui.ConverterApp, photo: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """空输入、空目录有提示；运行时禁止重入及关闭。"""
    warning = Mock()
    info = Mock()
    monkeypatch.setattr(gui.messagebox, "showwarning", warning)
    monkeypatch.setattr(gui.messagebox, "showinfo", info)
    app.startConversion()
    app.addPaths([photo])
    app.outputDir.set(" ")
    app.startConversion()
    assert warning.call_count == 2
    app.busy = True
    app.startConversion()
    app.closeWindow()
    info.assert_called_once()


def test_collection_failure(app: gui.ConverterApp, monkeypatch: pytest.MonkeyPatch) -> None:
    """目录读取失败显示错误。"""
    errorDialog = Mock()
    monkeypatch.setattr(gui, "collectImages", Mock(side_effect=PermissionError("unreadable")))
    monkeypatch.setattr(gui.messagebox, "showerror", errorDialog)
    app.addPaths([Path("unreadable")])
    errorDialog.assert_called_once()


def test_real_background_conversion(app: gui.ConverterApp, photo: Path, tmp_path: Path) -> None:
    """真实线程完成一成一败，并在第二次运行跳过已存在结果。"""
    broken = tmp_path / "broken.png"
    broken.write_bytes(b"bad")
    app.addPaths([photo, broken])
    app.outputDir.set(str(tmp_path / "output"))
    for expected in [dict(success=1, skipped=0, failed=1), dict(success=0, skipped=1, failed=1)]:
        app.startConversion()
        assert str(app.startButton["state"]) == "disabled"
        deadline = time.monotonic() + 10
        while app.busy and time.monotonic() < deadline:
            app.root.update()
            time.sleep(0.01)
        assert not app.busy
        assert app.counts == expected
        assert app.progress["value"] == 2
        assert str(app.startButton["state"]) == "normal"
        assert "处理完成" in app.status.get()
    assert (tmp_path / "output" / "photo.pdf").is_file()


def test_poll_empty_queue(app: gui.ConverterApp, monkeypatch: pytest.MonkeyPatch) -> None:
    """队列暂时为空时安排下一轮主线程检查。"""
    after = Mock()
    monkeypatch.setattr(app.root, "after", after)
    app.pollResults()
    after.assert_called_once_with(100, app.pollResults)


def test_close_idle(app: gui.ConverterApp, monkeypatch: pytest.MonkeyPatch) -> None:
    """空闲窗口允许关闭。"""
    destroy = Mock()
    monkeypatch.setattr(app.root, "destroy", destroy)
    app.closeWindow()
    destroy.assert_called_once()


def test_launch_gui(monkeypatch: pytest.MonkeyPatch) -> None:
    """启动入口构建应用并进入事件循环。"""
    root = Mock()
    constructor = Mock()
    monkeypatch.setattr(gui.tk, "Tk", lambda: root)
    monkeypatch.setattr(gui, "ConverterApp", constructor)
    gui.launchGui()
    constructor.assert_called_once_with(root)
    root.mainloop.assert_called_once()
