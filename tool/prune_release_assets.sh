#!/usr/bin/env bash
# Удаляет APK-ассеты у всех релизов, кроме последних KEEP.
#
# Зачем: ship.yml публикует релиз на каждый пуш в main (бывало 18 за сутки),
# по три APK ~80 МБ на каждый. За ноябрь набралось 126 релизов и ~10 ГБ при
# рекомендации GitHub ≤5 ГБ на репозиторий. Байты живут ТОЛЬКО в ассетах,
# поэтому удаляем ассеты, а записи релизов оставляем нетронутыми:
#   * экран «Что нового» в приложении строится из списка релизов
#     (lib/screens/changelog_screen.dart) — с удалёнными релизами он потерял бы
#     историю;
#   * Obtainium читает список релизов, чтобы выбирать версию и ABI.
#
# Запуск:
#   ./tool/prune_release_assets.sh [KEEP] [DRY_RUN]
# KEEP по умолчанию 20, DRY_RUN по умолчанию 1 (смета без удалений).
# В CI вызывается как `... 10 0`.
#
# Требует: gh и jq (есть на ubuntu-latest), GITHUB_REPOSITORY, GITHUB_TOKEN.
set -euo pipefail

KEEP="${1:-20}"
DRY_RUN="${2:-1}"

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY не задан (в GitHub Actions есть сам)}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN не задан (в Actions: secrets.GITHUB_TOKEN)}"

echo "Репозиторий: $GITHUB_REPOSITORY"
echo "Сохраняем ассеты ${KEEP} самых свежих релизов"
echo "DRY_RUN: $DRY_RUN"

# Тег текущего releases/latest защищён от удаления ВСЕГДА, независимо от
# позиции в списке: именно его ищет автообновление в приложении.
LATEST_TAG="$(gh api "repos/$GITHUB_REPOSITORY/releases/latest" \
  --jq '.tag_name' 2>/dev/null || true)"
if [ -z "$LATEST_TAG" ]; then
  # Не можем определить latest → не удаляем ничего. Ложное удаление APK
  # хуже неубранных гигабайт.
  echo "releases/latest не читается — пропускаю чистку."
  exit 0
fi
echo "releases/latest: $LATEST_TAG (не удаляем никогда)"

# Ключ сортировки — id релиза, а НЕ номер версии из тега. Причина проверена
# на живых данных: из тега «v1.6.192-rc1» вытаскивание последних цифр даёт
# «1», и rc-релиз уехал бы в хвост списка, то есть его APK удалились бы как
# древние. id растёт монотонно при создании релиза и есть у любого релиза всегда.
#
# При этом id и «номер версии» не одно и то же: 2026-11-15 у v1.6.190 id
# 446113442 больше, чем у v1.6.191 id 446113108 — их прогоны (ship и
# release-on-tag) шли параллельно. Оба попадают в топ, так что безвредно, но
# полагаться на «первые N строк из API» мы не стали: API отдаёт порядок по
# created_at, а он в этом же случае расходится и с id, и с версией.
rows="$(gh api "repos/$GITHUB_REPOSITORY/releases?per_page=100" --paginate \
  --jq '.[] | [(.id|tostring), .tag_name, (.assets | map(.id|tostring) | join(" "))] | join("\t")')"

if [ -z "$rows" ]; then
  echo "Релизов нет — нечего чистить."
  exit 0
fi

order="$(printf '%s\n' "$rows" | cut -f1 | sort -rn)"

n=0
targets=0
kept=0
while read -r rel_id; do
  [ -n "${rel_id:-}" ] || continue
  n=$((n + 1))
  row="$(printf '%s\n' "$rows" | awk -F'\t' -v id="$rel_id" '$1==id {print; exit}')"
  tag="$(printf '%s' "$row" | cut -f2)"
  ids="$(printf '%s' "$row" | cut -f3)"

  if [ "$n" -le "$KEEP" ] || [ "$tag" = "$LATEST_TAG" ]; then
    kept=$((kept + 1))
    [ "$n" -le "$KEEP" ] && echo "  оставляем #$n $tag"
    continue
  fi

  [ -n "${ids// /}" ] || continue
  for aid in $ids; do
    targets=$((targets + 1))
    if [ "$DRY_RUN" = "1" ]; then
      echo "  будет удалён: asset #$aid ($tag)"
    else
      gh api -X DELETE "repos/$GITHUB_REPOSITORY/releases/assets/$aid" >/dev/null
    fi
  done
done <<<"$order"

echo "Релизов просмотрено: $n (оставлено: $kept)"
if [ "$DRY_RUN" = "1" ]; then
  echo "DRY_RUN: задето ассетов: $targets (ничего не удалено)"
else
  echo "Готово: удалено ассетов: $targets"
fi

# Затем сами записи релизов — отдельным скриптом, чтобы его можно было
# запустить и руками: ./tool/prune_releases.sh 20 1
here="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$here/prune_releases.sh" ]; then
  bash "$here/prune_releases.sh" "$KEEP" "$DRY_RUN"
fi
