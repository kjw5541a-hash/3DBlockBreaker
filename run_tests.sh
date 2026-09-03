#!/usr/bin/env bash
set -uo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 실패한 assert는 Godot 4.7.2 헤드리스를 무한 정지시킨다. 타임아웃으로 실패 처리한다.
TEST_TIMEOUT="${TEST_TIMEOUT:-20}"

if [ ! -x "$GODOT" ]; then
	echo "godot 실행 파일을 찾을 수 없음: $GODOT"
	echo "GODOT 환경변수로 경로를 지정하세요."
	exit 1
fi

# 자식만 죽이고 자신은 정상 종료한다 — 셸이 시그널 사망 진단을 찍지 않게 하려는 것.
guarded() {
	perl -e 'my $t = shift; my $pid = fork; exit 127 if !defined $pid; if ($pid == 0) { exec @ARGV; exit 127 } $SIG{ALRM} = sub { kill "KILL", $pid; waitpid $pid, 0; exit 142 }; alarm $t; waitpid $pid, 0; my $r = $?; alarm 0; exit($r == 0 ? 0 : (($r >> 8) || 1))' "$TEST_TIMEOUT" "$@"
}

# class_name 전역 등록은 .godot/ 임포트 캐시에서 온다. 이게 없으면 다른 스크립트는
# 물론 자기 자신도 class_name을 식별하지 못한다. 새 class_name이 생기면 캐시가 낡으므로
# 매 실행마다 갱신한다. 출력은 버린다 — 아직 없는 main_scene 경고가 섞여 나온다.
guarded "$GODOT" --headless --path "$PROJECT_DIR" --import >/dev/null 2>&1

failed=0
for test_file in "$PROJECT_DIR"/tests/test_*.gd; do
	name="$(basename "$test_file")"
	echo "--- $name"
	stem="${name%.gd}"
	out="$(guarded "$GODOT" --headless --path "$PROJECT_DIR" --script "res://tests/$name" 2>&1)"
	code=$?
	printf '%s\n' "$out"
	if [ "$code" -eq 142 ]; then
		echo "TIMEOUT(${TEST_TIMEOUT}초): $name — 실패한 assert가 CLI 디버거에서 멈춘 것일 수 있다. 위 SCRIPT ERROR 참고"
	fi
	# Godot은 파스 에러에도, 단언이 아닌 런타임 오류에도 종료 코드 0을 낸다.
	# 성공 표식이 있어야 하고, 동시에 SCRIPT ERROR가 하나도 없어야 통과로 친다.
	# 표식만 보면 부족하다 — 범위 밖 읽기 같은 오류는 오류를 찍고도 계속 실행돼
	# 표식까지 도달한다.
	if [ "$code" -ne 0 ]; then
		echo "FAIL: $name"
		failed=1
	elif ! printf '%s\n' "$out" | grep -qx "$stem: OK"; then
		echo "성공 표식 '$stem: OK'가 출력에 없음 — 파스 에러이거나 테스트가 끝까지 도달하지 못했다"
		echo "FAIL: $name"
		failed=1
	elif printf '%s\n' "$out" | grep -q "SCRIPT ERROR"; then
		echo "SCRIPT ERROR가 출력에 있음 — 표식이 찍혔어도 통과로 치지 않는다"
		echo "FAIL: $name"
		failed=1
	fi
done

if [ "$failed" -ne 0 ]; then
	echo "테스트 실패"
	exit 1
fi
echo "전체 통과"
