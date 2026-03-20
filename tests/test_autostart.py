import sys
from pathlib import Path
from unittest.mock import patch
from ohmyvoice.autostart import get_plist_path


def test_plist_path():
    path = get_plist_path()
    assert "LaunchAgents" in str(path)
    assert "ohmyvoice" in str(path).lower()


def test_generate_plist_dev_mode():
    """Dev mode: plist uses python -m ohmyvoice.app."""
    from ohmyvoice.autostart import generate_plist
    xml = generate_plist()
    assert "com.ohmyvoice.app" in xml
    assert sys.executable in xml
    assert "-m" in xml
    assert "ohmyvoice.app" in xml


def test_generate_plist_frozen_mode(tmp_path):
    """Frozen mode: plist uses open <app_path>."""
    fake_exe = str(tmp_path / "OhMyVoice.app" / "Contents" / "MacOS" / "ohmyvoice")
    with patch.object(sys, "frozen", True, create=True), \
         patch.object(sys, "executable", fake_exe):
        from importlib import reload
        import ohmyvoice.autostart
        reload(ohmyvoice.autostart)
        xml = ohmyvoice.autostart.generate_plist()

    assert "<string>open</string>" in xml
    assert str(tmp_path / "OhMyVoice.app") in xml
    assert "-m" not in xml
