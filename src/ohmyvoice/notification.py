def send_notification(text: str, title: str = "OhMyVoice") -> None:
    preview = text[:80] + ("…" if len(text) > 80 else "")
    try:
        import rumps
        rumps.notification(
            title=title,
            subtitle="转写完成",
            message=preview,
        )
    except Exception:
        pass
