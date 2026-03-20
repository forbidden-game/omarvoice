#!/usr/bin/env python3
"""
独立可视化测试：打开设置窗口，不影响正在运行的 OhMyVoice 进程。

用法：python test_preferences_visual.py
退出：关闭窗口后按 Ctrl+C，或直接 Ctrl+C
"""

import sys
sys.path.insert(0, "src")

from AppKit import NSApplication, NSApplicationActivationPolicyRegular
from ohmyvoice.settings import Settings
from ohmyvoice.preferences import PreferencesWindow


class _MockEngine:
    """模拟 ASREngine，不加载任何模型。"""
    is_loaded = True
    def load(self, **kw): pass
    def unload(self): pass


class _MockApp:
    """模拟 OhMyVoiceApp，提供设置窗口所需的最小接口。"""
    def __init__(self):
        self._settings = Settings()  # 读取真实 ~/.config/ohmyvoice/settings.json
        self._engine = _MockEngine()
        self._hotkey = None
        self._recorder = None


def main():
    app = NSApplication.sharedApplication()
    # 让窗口能正常获得焦点（不然窗口会在后面）
    app.setActivationPolicy_(NSApplicationActivationPolicyRegular)

    mock = _MockApp()
    prefs = PreferencesWindow(mock)
    prefs.show()

    print("设置窗口已打开。关闭窗口后按 Ctrl+C 退出。")
    print(f"当前读取的设置文件：~/.config/ohmyvoice/settings.json")

    from PyObjCTools import AppHelper
    AppHelper.runEventLoop()


if __name__ == "__main__":
    main()
