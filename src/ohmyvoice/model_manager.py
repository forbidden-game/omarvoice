from pathlib import Path
from huggingface_hub import scan_cache_dir, snapshot_download

class ModelManager:
    MODELS = {
        "Qwen3-ASR-0.6B": {
            "hf_id": "Qwen/Qwen3-ASR-0.6B",
            "size_estimate": "1.2 GB",
            "quantizations": ["fp16"],
        },
    }

    def __init__(self, cache_dir: Path | None = None):
        if cache_dir is None:
            cache_dir = Path.home() / ".cache" / "huggingface" / "hub"
        self._cache_dir = cache_dir

    @property
    def cache_dir(self) -> Path:
        return self._cache_dir

    def get_model_info(self) -> dict:
        return {
            "name": "Qwen3-ASR-0.6B",
            "hf_id": "Qwen/Qwen3-ASR-0.6B",
            "quantization": "fp16",
            "size_estimate": "1.2 GB",
        }

    def is_downloaded(self, model_id: str = "Qwen/Qwen3-ASR-0.6B") -> bool:
        try:
            cache_info = scan_cache_dir(self._cache_dir)
            for repo in cache_info.repos:
                if repo.repo_id == model_id:
                    return True
        except Exception:
            pass
        return False

    def download(self, model_id: str = "Qwen/Qwen3-ASR-0.6B", progress_callback=None) -> Path:
        path = snapshot_download(model_id, cache_dir=self._cache_dir)
        return Path(path)
