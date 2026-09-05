#!/bin/sh
# /usr/bin/speedtestpp-run.sh
# 封装 speedtestpp 做一次完整测速（download + upload），后台跑并输出到文件
# LuCI 轮询该文件取结果。
# speedtestpp 非交互，参数: --download --upload --output text

OUT=/tmp/speedtestpp_result.txt
PIDF=/tmp/speedtestpp.pid
BIN=/usr/bin/speedtestpp

[ -x "$BIN" ] || { echo '{"ok":false,"err":"speedtestpp 未安装"}'; exit 1; }

case "$1" in
start)
	rm -f "$OUT"
	# 后台跑 download+upload，text 输出写文件
	( "$BIN" --download --upload --output text > "$OUT" 2>&1; echo "RC=$?" >> "$OUT" ) &
	echo $! > "$PIDF"
	echo "started"
	;;
stop)
	[ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null
	rm -f "$PIDF"
	echo "stopped"
	;;
status)
	if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
		echo "running"
	else
		echo "idle"
	fi
	;;
result)
	cat "$OUT" 2>/dev/null
	;;
*)
	echo "usage: start|stop|status|result"
	;;
esac
exit 0
