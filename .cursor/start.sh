#!/usr/bin/env bash
# 제로 서치 — 부팅마다 실행. PostgreSQL 데몬을 올리고 준비될 때까지 대기한다.
# (API·Flutter 서버는 terminals 에서 기동 — start 는 데몬 조정만 하고 즉시 종료)
set -euo pipefail

PG_VERSION="16"

sudo pg_ctlcluster "${PG_VERSION}" main start 2>/dev/null || true
for _ in $(seq 1 30); do
  if sudo -u postgres pg_isready -q; then
    echo "PostgreSQL 준비됨"
    exit 0
  fi
  sleep 1
done

echo "PostgreSQL 가 준비되지 않았습니다" >&2
exit 1
