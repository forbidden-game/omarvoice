import sys
from pathlib import Path

_LABEL = "com.ohmyvoice.app"


def get_plist_path() -> Path:
    return Path.home() / "Library" / "LaunchAgents" / f"{_LABEL}.plist"


def generate_plist() -> str:
    if getattr(sys, "frozen", False):
        app_path = str(Path(sys.executable).parent.parent.parent)
        program_args = f"""
        <string>open</string>
        <string>{app_path}</string>"""
    else:
        program_args = f"""
        <string>{sys.executable}</string>
        <string>-m</string>
        <string>ohmyvoice.app</string>"""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{_LABEL}</string>
    <key>ProgramArguments</key>
    <array>{program_args}
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>"""


def enable():
    path = get_plist_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(generate_plist())


def disable():
    path = get_plist_path()
    if path.exists():
        path.unlink()


def is_enabled() -> bool:
    return get_plist_path().exists()
