import re
import threading
import time

import rumps
from AppKit import NSImage, NSImageRep


_FILLER_WORDS = r'(?:呃|嗯|啊|哦|额|唔|那个|就是说|然后吧)+'


def _clean_text(text: str) -> str:
    """Remove filler words and clean up punctuation artifacts."""
    # Remove fillers optionally surrounded by punctuation
    text = re.sub(rf'[，、。]*{_FILLER_WORDS}[，、。]*', '，', text)
    # Collapse repeated punctuation
    text = re.sub(r'[，、。]{2,}', '，', text)
    # Strip leading/trailing punctuation
    text = re.sub(r'^[，、。\s]+|[，、\s]+$', '', text)
    return text.strip()

from ohmyvoice.asr import ASREngine
from ohmyvoice.audio_feedback import play_done, play_start
from ohmyvoice.clipboard import copy_to_clipboard
from ohmyvoice.history import HistoryDB
from ohmyvoice.hotkey import HotkeyManager
from ohmyvoice.notification import send_notification
from ohmyvoice.recorder import Recorder
from ohmyvoice.settings import Settings
from ohmyvoice.ui_bridge import UIBridge

from ohmyvoice.paths import get_resources_dir
_ICONS = get_resources_dir() / "icons"
_ICON_POINT_SIZE = (18, 18)


def _load_status_icon(icon_name: str, template: bool) -> NSImage:
    """Build a status bar icon with 1x and 2x image reps."""
    image = NSImage.alloc().initWithSize_(_ICON_POINT_SIZE)
    base_path = _ICONS / icon_name
    retina_path = base_path.with_name(f"{base_path.stem}@2x{base_path.suffix}")

    for path in (base_path, retina_path):
        if not path.exists():
            continue
        rep = NSImageRep.imageRepWithContentsOfFile_(str(path))
        if rep is None:
            continue
        rep.setSize_(_ICON_POINT_SIZE)
        image.addRepresentation_(rep)

    image.setTemplate_(template)
    return image


class OhMyVoiceApp(rumps.App):
    def __init__(self):
        super().__init__(
            name="OhMyVoice",
            icon=None,
            template=True,
            quit_button=None,
        )
        self._set_icon("mic_idle.png", template=True)
        self._settings = Settings()
        self._history = HistoryDB()
        self._recorder = Recorder(
            sample_rate=16000, device=self._settings.input_device
        )
        self._engine = ASREngine()
        self._hotkey: HotkeyManager | None = None
        self._ui_bridge = UIBridge(self)
        self._state = "idle"
        self._build_menu()
        self._load_model_async()

    def _build_menu(self):
        self.menu = [
            rumps.MenuItem("状态: 加载中...", callback=None),
            None,
            rumps.MenuItem("最近转写", callback=None),
            None,
            rumps.MenuItem("设置...", callback=self._on_settings),
            rumps.MenuItem("全部历史", callback=self._on_history),
            None,
            rumps.MenuItem("退出", callback=self._on_quit),
        ]

    def _load_model_async(self):
        def _load():
            try:
                bits = int(self._settings.model_quantization.replace("bit", ""))
                self._engine.load(quantize_bits=bits)
                self._set_state("idle")
                self.menu[
                    "状态: 加载中..."
                ].title = f"就绪 · {self._settings.hotkey_display}"
                self._start_hotkey()
            except Exception as e:
                self.menu["状态: 加载中..."].title = f"模型加载失败: {e}"

        threading.Thread(target=_load, daemon=True).start()

    def _start_hotkey(self):
        self._hotkey = HotkeyManager(
            modifiers=self._settings.hotkey_modifiers,
            key=self._settings.hotkey_key,
            on_press=self._on_hotkey_press,
            on_release=self._on_hotkey_release,
        )
        ok = self._hotkey.start()
        if not ok:
            self.menu["状态: 加载中..."].title = "需要辅助功能权限"

    def _on_hotkey_press(self):
        if self._state != "idle" or not self._engine.is_loaded:
            return
        self._set_state("recording")
        if self._settings.sound_feedback:
            play_start()
        self._recorder.start()

    def _on_hotkey_release(self):
        if self._state != "recording":
            return
        audio = self._recorder.stop()
        if len(audio) < 1600:  # < 0.1s, ignore accidental taps
            print("[DEBUG] Audio too short, ignoring")
            self._set_state("idle")
            return
        self._set_state("processing")
        threading.Thread(
            target=self._process_audio, args=(audio,), daemon=True
        ).start()

    def _process_audio(self, audio):
        try:
            context = self._settings.get_active_prompt()
            result = self._engine.transcribe(audio, context=context)
            text = _clean_text(result.text)
            if text:
                copy_to_clipboard(text)
                self._history.add(text, duration=result.duration_seconds)
                self._history.prune(self._settings.history_max_entries)
                self._update_recent_menu()
                if self._settings.sound_feedback:
                    play_done()
                if self._settings.notification_on_complete:
                    send_notification(text)
            self._set_state("done")
            time.sleep(1)
            self._set_state("idle")
        except Exception as e:
            print(f"ASR error: {e}")
            self._set_state("idle")

    def _set_state(self, state: str):
        self._state = state
        icon_map = {
            "idle": ("mic_idle.png", True),
            "recording": ("mic_recording.png", False),
            "processing": ("mic_processing.png", False),
            "done": ("mic_done.png", False),
        }
        icon_name, template = icon_map.get(state, ("mic_idle.png", True))
        self._set_icon(icon_name, template)

    def _set_icon(self, icon_name: str, template: bool):
        self._icon = str(_ICONS / icon_name)
        self._template = template
        self._icon_nsimage = _load_status_icon(icon_name, template)
        if hasattr(self, "_nsapp"):
            self._nsapp.setStatusBarIcon()

    def _update_recent_menu(self):
        try:
            records = self._history.recent(3)
            sub = self.menu["最近转写"]
            # Remove old items (sub.clear() crashes when no submenu exists)
            for key in list(sub.keys()):
                del sub[key]
            for r in records:
                preview = r["text"][:40] + ("…" if len(r["text"]) > 40 else "")
                sub[preview] = rumps.MenuItem(
                    preview,
                    callback=lambda _, text=r["text"]: copy_to_clipboard(text),
                )
        except Exception:
            pass  # non-critical: menu display only

    def _on_settings(self, _):
        self._ui_bridge.open_preferences()

    def _on_history(self, _):
        self._ui_bridge.open_history()

    def _on_quit(self, _):
        if self._hotkey:
            self._hotkey.stop()
        self._history.close()
        rumps.quit_application()


def main():
    OhMyVoiceApp().run()


if __name__ == "__main__":
    main()
