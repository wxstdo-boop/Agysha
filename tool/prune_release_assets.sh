#!/usr/bin/env bash
# Удаляет APK-ассеты у всех релизов, кроме последних KEEP.
#
# Зачем это вообще нужно: ship.yml публикует релиз на каждый пуш в main, их
# набралось 126, по три APK (~80 МБ) на каждый — ~10 ГБ на релизах при
# рекомендации GitHub ≤5 ГБ на репозиторий. Байты живут ТОЛЬКО в ассетах,
# поэтому удаляем именно ассеты, а сами релизы-записи оставляем нетронутыми:
#   * экран «Что нового» в приложении тянется из живых релизов
#     (lib/screens/changelog_screen.dart) — с удалёнными релизами он потерял бы
#     историю;
#   * Obtainium читает список релизов, чтобы выбирать версию и ABI.
#
# Ассеты последних KEEP релизов нужны как раз для этого: автообновление
# (UpdateService) и ручная установка скачивают APK именно оттуда.
#
# Запуск:
#   ./tool/prune_release_assets.sh [KEEP] [DRY_RUN]
# KEEP по умолчанию 10, DRY_RUN по умолчанию 1 (ничего не удаляет, только
# печатает смету). В CI вызывается с DRY_RUN=0.
#
# Требует: gh (есть на ubuntu-latest), GITHUB_REPOSITORY, GITHUB_TOKEN.
set -euo pipefail

KEEP="${1:-10}"
DRY_RUN="${2:-1}"

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY не задан (в GitHub Actions есть сам)}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN не задан (в Actions: secrets.GITHUB_TOKEN)}"

echo "Репозиторий: $GITHUB_REPOSITORY"
echo "Сохраняем ассеты последних релизов: $KEEP"
echo "DRY_RUN: $DRY_RUN"

# ОДНИМ пагинированным запросом берём id релиза и id его ассетов: список
# релизов уже отдаёт ассеты inline. Отдельные запросы /releases/{id}/assets на
# каждый релиз только выбивали rate limit токена Actions (1000 запросов/час).
rows="$(gh api "repos/$GITHUB_REPOSITORY/releases?per_page=100" --paginate \
  --jq '.[] | [(.id|tostring), .tag_name, (.assets | map(.id|tostring) | join(" "))] | join("\t")')"

if [ -z "$rows" ]; then
  echo "Релизов нет — нечего чистить."
  exit 0
fi

# GitHub отдаёт релизы в порядке убывания created_at — первые KEEP и есть
# самые свежие, поэтому список нигде не пересортирован: пересортировка
# удалила бы свежие APK вместо старых.
n=0
targets=0
while IFS=$'\t' read -r rel_id tag ids; do
  [ -n "${rel_id:-}" ] || continue
  n=$((n + 1))
  if [ "$n" -le "$KEEP" ]; then
    echo "  оставляем #$n $tag"
    continue
  fi
  [ -n "${ids// /}" ] || continue
  for aid in $ids; do
    targets=$((targets + 1))
    if [ "$DRY_RUN" = "1" ]; then
      echo "  будет удалён: asset #$aid ($tag)"
    else
      gh api -X DELETE "repos/$GITHUB_REPOSITORY/releases/assets/$aid" >/dev/null
      echo "  удалён asset #$aid ($tag)"
    fi
  done
done <<<"$rows"

echo "Релизов просмотрено: $n"
if [ "$DRY_RUN" = "1" ]; then
  echo "DRY_RUN: задето ассетов: $targets (ничего не удалено)"
else
  echo "Готово: удалено ассетов: $targets"
fi
