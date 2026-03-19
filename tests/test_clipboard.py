from ohmyvoice.clipboard import copy_to_clipboard, get_clipboard_text


def test_copy_and_read_back():
    text = "OhMyVoice test 你好 React TypeScript"
    copy_to_clipboard(text)
    result = get_clipboard_text()
    assert result == text
