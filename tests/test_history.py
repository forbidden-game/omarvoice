from ohmyvoice.history import HistoryDB

def test_add_and_list(tmp_path):
    db = HistoryDB(tmp_path / "test.db")
    db.add("hello world", duration=2.5)
    db.add("second entry", duration=1.0)
    records = db.recent(10)
    assert len(records) == 2
    assert records[0]["text"] == "second entry"
    assert records[1]["text"] == "hello world"

def test_recent_limit(tmp_path):
    db = HistoryDB(tmp_path / "test.db")
    for i in range(10):
        db.add(f"entry {i}", duration=1.0)
    records = db.recent(3)
    assert len(records) == 3
    assert records[0]["text"] == "entry 9"

def test_search(tmp_path):
    db = HistoryDB(tmp_path / "test.db")
    db.add("React Server Component", duration=2.0)
    db.add("TypeScript generics", duration=1.5)
    db.add("Python asyncio", duration=3.0)
    results = db.search("TypeScript")
    assert len(results) == 1
    assert results[0]["text"] == "TypeScript generics"

def test_prune_old_entries(tmp_path):
    db = HistoryDB(tmp_path / "test.db")
    for i in range(15):
        db.add(f"entry {i}", duration=1.0)
    db.prune(max_entries=10)
    assert len(db.recent(20)) == 10
    texts = [r["text"] for r in db.recent(20)]
    assert "entry 0" not in texts
    assert "entry 14" in texts

def test_clear(tmp_path):
    db = HistoryDB(tmp_path / "test.db")
    db.add("something", duration=1.0)
    db.clear()
    assert len(db.recent(10)) == 0

def test_get_by_id(tmp_path):
    db = HistoryDB(tmp_path / "test.db")
    db.add("find me", duration=2.0)
    records = db.recent(1)
    record = db.get(records[0]["id"])
    assert record["text"] == "find me"
