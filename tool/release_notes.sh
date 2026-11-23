#!/usr/bin/env bash
# Фильтр заметок релиза.
#
# На вход — строки вида «- <заголовок коммита>» (их печатает
# `git log --no-merges --pretty=format:'- %s'`). На выход — только те, что
# интересны пользователю.
#
# Зачем: заметки релиза и fastlane-changelog собираются из заголовков коммитов,
# и служебные коммиты («F-Droid: рецепт на тег…», «docs(AGENTS): …», «ship: …»)
# утекали в «Что нового» на GitHub и в F-Droid. Пользователь видел внутреннюю
# кухню вместо изменений приложения.
#
# Правило простое: отбрасываем строки с префиксом Conventional Commits из
# служебного набора (docs/chore/ci/style/test/build/refactor) и наши
# локальные префиксы (F-Droid/fdroid/ship/release/Документация/Переименование).
# Всё остальное — пользовательское («Полировка…», «Питание: …», «feat…»).
#
# Два режима:
#   без флагов  — плоский список для fastlane-changelog (F-Droid режет его по
#                 500 символам, поэтому ни заголовков, ни подписей);
#   --sections  — тело GitHub-релиза: короткий человеческий ввод, пункты по
#                 блокам «Новое / Плавнее / Починили» и подпись. Заголовки без
#                 `#`, чтобы текст не выглядел мусором, если его отдадут
#                 fastlane.
#
# Скрипт намеренно всегда завершается успешно: пустой поток — не ошибка, а
# повод для вызывающей стороны подставить запасной текст.
set -uo pipefail

# Служебные префиксы, плюс отдельно вычищаем зависимости: строки dependabot
# и «Bump x from a to b» — это не изменения приложения, и в заметках они
# выглядели как мусор из чужого бота.
grep -vE '^- (F-Droid|fdroid|ship|release|Документация|Переименование|docs|chore|ci|style|test|build|refactor|deps)(\([^)]*\))?(:|$)' \
  | grep -viE 'dependabot|^- bump[ (:]|^- bump$' \
  | python3 -c '
import re, sys

SECTIONS = "--sections" in sys.argv[1:]

# Темы для эмодзи. Порядок важен: первое совпадение выигрывает, поэтому
# узкие темы идут выше общих.
EMOJI_RULES = [
    (("наклон", "тилт", "3d", "пин", "pin"), "🫧"),
    (("клавиат", "ввод", "букв"), "⌨️"),
    (("поиск", "источник"), "🔎"),
    (("ада", "ии", "провайдер", "ответ"), "🍑"),
    (("будильник", "тест"), "⏰"),
    (("питани", "лимит", "тренд", "приём", "прием"), "🍽️"),
    (("зачёрк", "зачерк", "зачёркиван"), "✍️"),
    (("скролл", "прокрут"), "🌊"),
    (("плавн", "анимац", "отдач"), "🫧"),
    (("баг", "фикс", "исправ", "чиним"), "🛠️"),
]

# Что считаем исправлением, а что — шлифовкой. Остальное попадает в «Новое».
FIX_WORDS = ("баг", "фикс", "исправ", "чиним", "почин", "не работа", "пада",
             "лома", "пропада", "зависа", "дёрга", "дерга", "тормоз", "лаг")
POLISH_WORDS = ("плавн", "анимац", "отдач", "полиров", "быстрее", "ускор",
                "мягч", "наклон", "тилт", "3d", "перелив", "свечен", "красив",
                "аккурат", "чище", "контраст", "читаем", "тише", "громче")

# Внутренний жаргон, который в заметках читается как тикет из трекера.
JARGON = [
    (r"\bфикс\b", "исправление"),
    (r"\bрегресс\b", "откат"),
    (r"\bрефактор\w*\b", "внутренняя уборка"),
    (r"\bмерж\w*\b", "слияние"),
    (r"\bкоммит\w*\b", "правка"),
]

def humanize(text):
    for pat, rep in JARGON:
        text = re.sub(pat, rep, text, flags=re.I)
    # «Тема: деталь» из заголовка коммита читается как предложение только с
    # тире — двоеточие оставляло ощущение списка из changelog.
    m = re.match(r"^([^:]{3,60}):\s+(.+)$", text)
    if m:
        head, tail = m.group(1), m.group(2)
        if not head.lower().startswith(("http", "https")):
            text = head + " — " + tail
    text = text.strip().rstrip(".")
    if text:
        text = text[0].upper() + text[1:]
    return text

def section_of(low):
    if any(k in low for k in FIX_WORDS):
        return "fix"
    if any(k in low for k in POLISH_WORDS):
        return "polish"
    return "new"

buckets = {"new": [], "polish": [], "fix": []}
order = []
seen = set()

for raw in sys.stdin:
    line = raw.rstrip("\n")
    # Перенос строки длинного пункта из changelog — не заголовок коммита,
    # отдаём как есть, иначе хвост пункта теряется.
    if not line.startswith("- "):
        print(line)
        continue
    text = re.sub(r"^(fix|feat|perf|improve|polish)(\([^)]*\))?:\s*", "",
                  line[2:], flags=re.I).strip()
    # Свой эмодзи-маркер ставим сами: если пункт пришёл с готовым значком
    # (старый changelog, повторный прогон), второй значок в начале читался
    # бы как «🫧 🫧 текст».
    text = re.sub(r"^[\U0001F000-\U0001FAFF\u2190-\u2BFF\uFE0F\u200D]+\s*",
                  "", text).strip()
    if not text:
        continue
    text = text[0].upper() + text[1:]
    low = text.lower()
    emoji = "✨"
    for keys, icon in EMOJI_RULES:
        if any(k in low for k in keys):
            emoji = icon
            break
    bullet = "- " + emoji + " " + text
    if bullet in seen:
        continue
    seen.add(bullet)
    order.append((emoji, text))
    buckets[section_of(low)].append((emoji, humanize(text)))

if not SECTIONS:
    # Порядок — как в истории: fastlane-заметки читают сверху вниз, и
    # перестановка сломала бы привычный ход «сначала главное».
    for emoji, text in order:
        print("- " + emoji + " " + text)
    raise SystemExit(0)

total = sum(len(v) for v in buckets.values())
if total == 0:
    raise SystemExit(0)

print("Свежая сборка Agysha — ставится поверх, вход и настройки на месте.")
print("")

TITLES = {
    "new": "✨ Новое",
    "polish": "🫧 Плавнее и приятнее",
    "fix": "🛠️ Починили",
}
for key in ("new", "polish", "fix"):
    items = buckets[key]
    if not items:
        continue
    print("**" + TITLES[key] + "**")
    for emoji, text in items:
        print("- " + emoji + " " + text)
    print("")

print("Обновляйся поверх — данные и настройки остаются. Спасибо, что ты с нами 💛")
' "$@" || true
