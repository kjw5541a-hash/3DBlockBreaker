extends SceneTree

func _initialize() -> void:
	_test_length_scales_with_speed()
	_test_color_scales_with_speed()
	_test_history_is_bounded()
	_test_fire_overrides_the_speed_color()
	print("test_ball_trail: OK")
	quit()

# 플레이어가 알아야 할 유일한 숨은 상태는 "지금 공이 센가 약한가"다.
# 트레일이 그 상태를 그대로 비춰야 한다.
func _test_length_scales_with_speed() -> void:
	var slow := BallTrail.sample_count(Tuning.v_min())
	var fast := BallTrail.sample_count(Tuning.V_MAX)
	assert(fast > slow, "빠른 공의 트레일이 더 길어야 한다: %d vs %d" % [fast, slow])
	assert(slow >= BallTrail.MIN_SAMPLES, "가장 느릴 때도 선이 보여야 한다: %d" % slow)

func _test_color_scales_with_speed() -> void:
	var slow := BallTrail.color_for(Tuning.v_min())
	var fast := BallTrail.color_for(Tuning.V_MAX)
	assert(fast.get_luminance() > slow.get_luminance(),
		"빠른 공이 더 밝아야 한다: %f vs %f" % [fast.get_luminance(), slow.get_luminance()])

# 불이 붙은 동안은 트레일이 속도계 노릇을 잠깐 그만둔다. 속도는 언제나 볼 수
# 있지만 불은 몇 초짜리 상태라, 지금 뚫리는 중인지가 더 급한 정보다.
func _test_fire_overrides_the_speed_color() -> void:
	for speed in [Tuning.v_min(), Tuning.V_MAX]:
		var fire := BallTrail.color_for(speed, true)
		assert(fire.is_equal_approx(Tuning.FIRE_COLOR),
			"불타는 트레일이 불 색이 아니다: %s" % fire)
		assert(not fire.is_equal_approx(BallTrail.color_for(speed)),
			"불이 붙었는데 평소 색과 같다: %s" % fire)

func _test_history_is_bounded() -> void:
	var t := BallTrail.new()
	for i in 500:
		t.push(Vector2(float(i) * 0.01, 5.0), Tuning.V_MAX)
	assert(t.point_count() <= BallTrail.sample_count(Tuning.V_MAX),
		"이력이 무한히 쌓인다: %d" % t.point_count())
	t.free()
