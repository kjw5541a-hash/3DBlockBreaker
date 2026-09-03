extends SceneTree

func _initialize() -> void:
	_test_length_scales_with_speed()
	_test_color_scales_with_speed()
	_test_history_is_bounded()
	print("test_ball_trail: OK")
	quit()

# 플레이어가 알아야 할 유일한 숨은 상태는 "지금 공이 센가 약한가"다.
# 트레일이 그 상태를 그대로 비춰야 한다.
func _test_length_scales_with_speed() -> void:
	var slow := BallTrail.sample_count(Tuning.v_min())
	var fast := BallTrail.sample_count(Tuning.V_MAX)
	assert(fast > slow, "빠른 공의 트레일이 더 길어야 한다: %d vs %d" % [fast, slow])
	assert(slow >= 2, "가장 느릴 때도 선이 보여야 한다: %d" % slow)

func _test_color_scales_with_speed() -> void:
	var slow := BallTrail.color_for(Tuning.v_min())
	var fast := BallTrail.color_for(Tuning.V_MAX)
	assert(fast.get_luminance() > slow.get_luminance(),
		"빠른 공이 더 밝아야 한다: %f vs %f" % [fast.get_luminance(), slow.get_luminance()])

func _test_history_is_bounded() -> void:
	var t := BallTrail.new()
	for i in 500:
		t.push(Vector2(float(i) * 0.01, 5.0), Tuning.V_MAX)
	assert(t.point_count() <= BallTrail.sample_count(Tuning.V_MAX),
		"이력이 무한히 쌓인다: %d" % t.point_count())
	t.free()
