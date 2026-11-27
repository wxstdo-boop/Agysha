#!/usr/bin/env bash
# Уборка мусора в рабочей папке: кэши тестов, хвосты Flutter и старые логи.
# Ничего из нужного для сборки не трогает (.gradle, .pub-cache, SDK, исходники).
#
#   tool/disk_guard.sh            — разовая уборка, если диск занят >= 85%
#   tool/disk_guard.sh --force    — убрать сейчас, не глядя на порог
#   tool/disk_guard.sh --watch    — тихо проверять каждые 10 минут в фоне
#
# Порог меняется переменной DISK_GUARD_PERCENT (по умолчанию 85).

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="/tmp/agysha_disk_guard.log"
THRESHOLD="${DISK_GUARD_PERCENT:-85}"
MODE="${1:-auto}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

used_percent() { df --output=pcent / | tail -1 | tr -dc '0-9'; }

# Пока идёт тест или сборка, кэш трогать нельзя — иначе прогон падает.
busy() {
  pgrep -f 'flutter(_tools)? test|flutter build|flutter_tester|gradlew|GradleDaemon' >/dev/null 2>&1
}

clean() {
  local before after freed
  before=$(df --output=avail / | tail -1)
  rm -rf "$ROOT/build/test_cache" "$ROOT/build/unit_test_assets" 2>/dev/null
  rm -rf /tmp/flutter_tools.* 2>/dev/null
  rm -rf /tmp/agysha-p[0-9]* 2>/dev/null
  find /tmp -maxdepth 1 -name 'agysha_*.log' -mtime +2 -delete 2>/dev/null
  find /tmp -maxdepth 1 -name 'chromium-*' -mtime +1 -exec rm -rf {} + 2>/dev/null
  after=$(df --output=avail / | tail -1)
  freed=$(( (after - before) / 1024 ))
  log "cleaned: freed ${freed} MB, used now $(used_percent)%"
}

if [ "$MODE" = "--watch" ]; then
  log "watch started (threshold ${THRESHOLD}%)"
  while true; do
    if [ "$(used_percent)" -ge "$THRESHOLD" ] && ! busy; then
      clean
    fi
    sleep 600
  done
fi

if busy; then
  log "skip: сборка или тест ещё идут"
  exit 0
fi

if [ "$MODE" = "--force" ] || [ "$(used_percent)" -ge "$THRESHOLD" ]; then
  clean
  exit 0
fi

log "ok: used $(used_percent)%, ниже порога ${THRESHOLD}%"
