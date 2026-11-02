extends SceneTree
# Real Godot 4.3 font-glyph smoke. Runs after the pinned font is fetched.
func _initialize() -> void:
    var font := load("res://assets/fonts/NotoSansJP.ttf") as Font
    if font == null:
        push_error("RELEASE_JP_FONT_MISSING")
        quit(1)
        return
    for ch in "日本語次の塔完了残り秒最速照射中予告被弾再開一時停止再スタート頭上番号順移動橙紫転送光る帯避けようクリア時間切れ罠失い中央戻されました":
        if not font.has_char(ch.unicode_at(0)):
            push_error("RELEASE_JP_GLYPH_MISSING: " + ch)
            quit(1)
            return
    print("PASS: pinned Noto Sans JP has actual Japanese glyph coverage")
    quit(0)
