extends SceneTree

# Godot 기본 폰트에는 한글 글리프가 없다. 그대로 두면 HUD 와 일시정지·게임오버
# 화면의 한글이 전부 두부(□)로 나오고, 영문인 "GAME OVER" 만 멀쩡해 보인다.
# 그래서 한글 subset 폰트를 프로젝트 기본 폰트로 깐다.
#
# subset 이라 화면에 나오는 글자만 들어 있다. UI 에 한글을 새로 쓰면 그 글자는
# 폰트에 없어 조용히 두부가 된다 — 여기서 잡는다. 터지면 tools/make_font.sh 를
# 다시 돌리면 된다.
const FONT_PATH := "res://assets/NotoSansKR-subset.ttf"

func _initialize() -> void:
	_test_the_project_font_is_the_korean_subset()
	_test_every_glyph_the_ui_shows_is_in_the_font()
	print("test_font: OK")
	quit()

func _test_the_project_font_is_the_korean_subset() -> void:
	var setting := str(ProjectSettings.get_setting("gui/theme/custom_font", ""))
	assert(setting == FONT_PATH,
		"프로젝트 기본 폰트가 한글 subset 이 아니다: '%s'" % setting)

func _test_every_glyph_the_ui_shows_is_in_the_font() -> void:
	var font := load(FONT_PATH) as Font
	assert(font != null, "subset 폰트를 못 불러왔다: %s" % FONT_PATH)
	# 화면에 나오는 글자의 출처는 씬의 text = "..." 과 스크립트의 .text = "..." 둘뿐이다.
	# 주석은 일부러 안 훑는다 — 이 저장소는 주석이 전부 한글이라 그것까지 넣으면
	# subset 이 폰트 전체가 된다.
	#
	# 두 출처를 따로 세는 것은 한쪽 훑기가 깨져도 다른 쪽이 한글을 채워 넣어
	# 합계만 보면 반만 도는 것을 못 잡기 때문이다.
	var from_scenes := _collect("res://scenes", "(?m)^text = \"(.*)\"$")
	var from_scripts := _collect("res://scripts", "\\.text = \"(.*?)\"")
	assert(_korean_count(from_scenes) >= 5,
		"씬에서 찾은 한글이 %d 자뿐이다 — 훑기가 헛돈다" % _korean_count(from_scenes))
	assert(_korean_count(from_scripts) >= 5,
		"스크립트에서 찾은 한글이 %d 자뿐이다 — 훑기가 헛돈다" % _korean_count(from_scripts))
	var seen := {}
	for c in from_scenes + from_scripts:
		if seen.has(c):
			continue
		seen[c] = true
		assert(font.has_char(c.unicode_at(0)),
			"화면에 나오는 '%s' 가 폰트에 없다 — 두부로 뜬다. tools/make_font.sh 를 다시 돌릴 것" % c)

static func _korean_count(s: String) -> int:
	var n := 0
	for c in s:
		if c.unicode_at(0) > 0x7f:
			n += 1
	return n

func _collect(dir: String, pattern: String) -> String:
	var re := RegEx.create_from_string(pattern)
	var out := ""
	for f in DirAccess.get_files_at(dir):
		# 임포트된 프로젝트에서는 .gd 옆에 .uid 가 같이 놓인다.
		if not (f.ends_with(".tscn") or f.ends_with(".gd")):
			continue
		for m in re.search_all(FileAccess.get_file_as_string(dir.path_join(f))):
			out += m.get_string(1)
	return out
