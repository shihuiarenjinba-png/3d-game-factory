extends RefCounted
## Local user:// ConfigFile only. Empty/corrupt/untrusted values safely reset.
static func load_data(path: String) -> Dictionary:
    var cfg := ConfigFile.new()
    if cfg.load(path) != OK:
        return {"best_seconds": -1.0, "language": "en"}
    var best = cfg.get_value("progress", "best_seconds", -1.0)
    var language = cfg.get_value("settings", "language", "en")
    if not (best is float or best is int):
        best = -1.0
    elif best != best or best <= 0.0 or best > 120.0:
        best = -1.0
    if language != "en" and language != "ja":
        language = "en"
    return {"best_seconds": float(best), "language": language}

static func save_data(path: String, best_seconds: float, language: String) -> bool:
    if language != "en" and language != "ja":
        return false
    if best_seconds != -1.0 and (best_seconds != best_seconds or best_seconds <= 0.0 or best_seconds > 120.0):
        return false
    var cfg := ConfigFile.new()
    cfg.set_value("progress", "best_seconds", best_seconds)
    cfg.set_value("settings", "language", language)
    return cfg.save(path) == OK
