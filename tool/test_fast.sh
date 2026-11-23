#!/usr/bin/env bash
# Быстрый локальный прогон тестов: вместо всех 100+ файлов запускает только
# те, которые задевает текущая правка.
#
# Зачем: полный `flutter test` на этом железе идёт около пяти минут, а на
# каждый файл Flutter заново собирает тестовый бандл — время почти целиком
# уходит на компиляцию, а не на сами проверки. При правке одного экрана
# ждать пять минут незачем.
#
# Что берём:
#   1. тест-файлы, в тексте которых есть имя изменённого файла (тесты читают
#      исходники через readLibrary и обычно упоминают путь);
#   2. тест-файлы, названием совпадающие с изменённым (profile_screen.dart →
#      profile_*_test.dart);
#   3. всегда — быстрые «дымовые» тесты, которые страдают от правок в общих
#      местах (main.dart, сервисы).
#
# Использование:
#   tool/test_fast.sh            # по изменениям против HEAD
#   tool/test_fast.sh --all      # полный прогон (то же, что flutter test -j 1)
#   tool/test_fast.sh lib/screens/profile_screen.dart   # явный путь
#
# Параллельность жёстко 1: на машине с 4 ГБ параллельный прогон уходит в OOM.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

if [[ "${1:-}" == "--all" ]]; then
  exec flutter test -j 1 --reporter compact
fi

# Изменённые и новые файлы. Если передан путь — только он.
if [[ $# -gt 0 ]]; then
  changed=("$@")
else
  mapfile -t changed < <(
    git diff --name-only HEAD -- 'lib/**' 'test/**' 2>/dev/null
    git ls-files --others --exclude-standard -- 'lib/**' 2>/dev/null
  )
fi

if [[ ${#changed[@]} -eq 0 ]]; then
  echo "Изменений нет — гоняю полный набор."
  exec flutter test -j 1 --reporter compact
fi

declare -A picked=()

# В прогон идут ТОЛЬКО тест-файлы: `source_scope.dart` и прочие помощники
# лежат рядом, в них нет ни одного теста, а `flutter test` на них падает.
pick() { [[ -f $1 && $1 == *_test.dart ]] && picked["$1"]=1; }

# 1. Ссылки на изменённые файлы в тексте тестов.
for path in "${changed[@]}"; do
  [[ $path == lib/* ]] || continue
  base=$(basename "$path")          # settings_screen.dart
  stem=${base%.dart}                # settings_screen
  # Имена классов из змеиного регистра: settings_screen → SettingsScreen.
  # Ищем ДВА тега: имя файла и имя класса. Раньше здесь стоял голый `stem`,
  # и `main` совпадал с `main(` в каждом тесте — скрипт гонял весь набор.
  pascal=$(printf '%s' "$stem" | awk -F_ '{for(i=1;i<=NF;i++) printf "%s", toupper(substr($i,1,1)) substr($i,2)}')
  while IFS= read -r hit; do pick "$hit"; done < <(
    grep -rlF -- "$base" test/ 2>/dev/null
    [[ ${#pascal} -ge 6 ]] && grep -rlF -- "$pascal" test/ 2>/dev/null
  )
  # 2. Одноимённый тест-файл (profile_screen.dart → profile_screen_test.dart).
  pick "test/${stem}_test.dart"
done

# Изменённые тесты — всегда.
for path in "${changed[@]}"; do
  [[ $path == test/* && $path == *_test.dart ]] && pick "$path"
done

# 3. Дымовые: общий старт, логирование, конфигурация сборки.
for smoke in \
  test/swallow_test.dart \
  test/boot_backdrop_colors_test.dart \
  test/widget_polish_behaviour_test.dart \
  test/startup_*_test.dart; do
  [[ -e $smoke ]] && pick "$smoke"
done

files=("${!picked[@]}")
if [[ ${#files[@]} -eq 0 ]]; then
  echo "Связанных тестов не нашлось — гоняю полный набор."
  exec flutter test -j 1 --reporter compact
fi

echo "Файлов в прогоне: ${#files[@]}"
printf '  %s\n' "${files[@]}" | head -20
echo

exec flutter test -j 1 --reporter compact "${files[@]}"
