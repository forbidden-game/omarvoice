from pathlib import Path
from ohmyvoice.model_manager import ModelManager

def test_model_info():
    mm = ModelManager()
    info = mm.get_model_info()
    assert "name" in info
    assert "quantization" in info

def test_model_cache_dir():
    mm = ModelManager()
    cache_dir = mm.cache_dir
    assert isinstance(cache_dir, Path)

def test_is_downloaded_false_for_nonexistent():
    mm = ModelManager(cache_dir=Path("/tmp/nonexistent_model_cache_test"))
    assert mm.is_downloaded("fake-model-9999") is False
