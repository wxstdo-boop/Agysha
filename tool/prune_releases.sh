#!/usr/bin/env bash
# Оставляет в репозитории только последние KEEP релизов вместе с их тегами.
#
# Зачем: ship.yml выпускает релиз на каждый пуш в main, и без уборки список
# растягивается на сотни записей. Владелец проекта договорился держать ровно
# 10 последних — остальные удаляются вместе с тегами.
#
# releases/latest не удаляется никогда: его читает автообновление в приложении.
# Драфты не трогаем.
#
# Запуск:
#   ./tool/prune_releases.sh [KEEP] [DRY_RUN]
# KEEP по умолчанию 10, DRY_RUN по умолчанию 1 (только показать).
# В CI вызывается как `... 10 0`.
#
# Требует: gh и jq, GITHUB_REPOSITORY, GITHUB_TOKEN.
set -euo pipefail

KEEP="${1:-10}"
DRY_RUN="${2:-1}"

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY не задан (в GitHub Actions есть сам)}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN не задан (в Actions: secrets.GITHUB_TOKEN)}"

echo "Репозиторий: $GITHUB_REPOSITORY"
echo "Оставляем последние ${KEEP} релизов"
echo "DRY_RUN: $DRY_RUN"

LATEST_TAG="$(gh api "repos/$GITHUB_REPOSITORY/releases/latest" \
  --jq '.tag_name' 2>/dev/null || true)"
if [ -z "$LATEST_TAG" ]; then
  # Без latest не понимаем, что защищено, — лучше не удалять ничего.
  echo "releases/latest не читается — пропускаю чистку."
  exit 0
fi
echo "releases/latest: $LATEST_TAG (не удаляем никогда)"

# Порядок API — created_at по убыванию, но id надёжнее при равных секундах:
# ship и release-on-tag умеют создать два релиза одновременно.
rows="$(gh api "repos/$GITHUB_REPOSITORY/releases?per_page=100" --paginate \
  --jq '.[] | select(.draft | not) | [(.id|tostring), .tag_name] | join("\t")')"

if [ -z "$rows" ]; then
  echo "Релизов нет — нечего чистить."
  exit 0
fi

order="$(printf '%s\n' "$rows" | cut -f1 | sort -rn)"

n=0
deleted=0
while read -r rel_id; do
  [ -n "${rel_id:-}" ] || continue
  n=$((n + 1))
  tag="$(printf '%s\n' "$rows" | awk -F'\t' -v id="$rel_id" '$1==id {print $2; exit}')"

  if [ "$n" -le "$KEEP" ] || [ "$tag" = "$LATEST_TAG" ]; then
    echo "  оставляем #$n $tag"
    continue
  fi

  deleted=$((deleted + 1))
  if [ "$DRY_RUN" = "1" ]; then
    echo "  будет удалён: $tag (вместе с тегом)"
  else
    gh release delete "$tag" --yes --cleanup-tag >/dev/null
    echo "  удалён: $tag"
  fi
done <<<"$order"

echo "Релизов просмотрено: $n"
if [ "$DRY_RUN" = "1" ]; then
  echo "DRY_RUN: задето релизов: $deleted (ничего не удалено)"
else
  echo "Готово: удалено релизов: $deleted"
fi
