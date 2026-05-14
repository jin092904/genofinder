#!/usr/bin/env bash
# 대기 + chain: 지정된 PID 의 process 가 종료될 때까지 기다린 뒤,
# 지정된 다음 script 를 실행한다. 단독 detached 프로세스로 살아 SSH 끊겨도 동작.
#
# 실행:
#   nohup bash scripts/a100-wait-and-chain.sh <PID> <NEXT_SCRIPT_PATH> > /tmp/chain.log 2>&1 &
#   disown
set -euo pipefail

WAIT_PID="${1:?PID 인자 필요}"
NEXT_SCRIPT="${2:?다음 실행할 script 경로 필요}"

# 현재 process command (PID reuse 방지용 비교 — empty 면 skip)
EXPECT_CMD=$(ps -p "$WAIT_PID" -o cmd= 2>/dev/null || true)
echo "[$(date '+%F %T')] waiting for PID=$WAIT_PID (cmd: ${EXPECT_CMD:-already gone})"

# 5분 polling
while kill -0 "$WAIT_PID" 2>/dev/null; do
  # PID reuse 방어: command 가 우리가 기대한 것과 다르면 이미 종료된 것으로 판단
  if [ -n "$EXPECT_CMD" ]; then
    CUR_CMD=$(ps -p "$WAIT_PID" -o cmd= 2>/dev/null || true)
    if [ "$CUR_CMD" != "$EXPECT_CMD" ]; then
      echo "[$(date '+%F %T')] PID $WAIT_PID 의 command 가 변경됨 — 이전 process 종료로 판단"
      break
    fi
  fi
  sleep 300
done

echo "[$(date '+%F %T')] preceding batch finished, starting NEXT_SCRIPT=$NEXT_SCRIPT"
exec bash "$NEXT_SCRIPT"
