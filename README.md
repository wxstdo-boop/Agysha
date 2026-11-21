<div align="center">
  <img src="assets/agysha.png" alt="Agysha" width="112" height="112" />

  <h1>Agysha</h1>

  <p><strong>Будильник, который не даёт уснуть обратно.</strong><br />
  Задачи, привычки, питание и ИИ-ассистент Ада — в одном приложении.</p>

  <p>
    <a href="https://github.com/wxstdo-boop/agysha/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/wxstdo-boop/agysha/ci.yml?branch=main&label=CI&color=2ea44f" /></a>
    <a href="https://github.com/wxstdo-boop/agysha/releases/latest"><img alt="Последний релиз" src="https://img.shields.io/github/v/release/wxstdo-boop/agysha?label=%D1%80%D0%B5%D0%BB%D0%B8%D0%B7&color=c2185b" /></a>
    <a href="LICENSE"><img alt="Лицензия MIT" src="https://img.shields.io/badge/license-MIT-2ea44f" /></a>
    <img alt="Flutter 3.47.5" src="https://img.shields.io/badge/Flutter-3.47.5-02569a?logo=flutter&logoColor=white" />
    <img alt="Dart 3.12+" src="https://img.shields.io/badge/Dart-3.12%2B-0175C2?logo=dart&logoColor=white" />
    <img alt="Android 8.0+" src="https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white" />
  </p>

  <p>
    <a href="https://github.com/wxstdo-boop/agysha/releases/latest"><strong>Скачать APK</strong></a>
    &nbsp;·&nbsp;
    <a href="docs/BUILD.md">Собрать самому</a>
    &nbsp;·&nbsp;
    <a href="docs/ARCHITECTURE.md">Архитектура</a>
    &nbsp;·&nbsp;
    <a href="CONTRIBUTING.md">Участие</a>
  </p>
</div>

---

**Agysha** — свободное Android-приложение без рекламы, аккаунтов и облака.
Данные лежат на телефоне в зашифрованных JSON-файлах, работа офлайн, а
единственные сетевые запросы — к GitHub за обновлениями и к ИИ-провайдеру,
которого пользователь выбрал сам.

## Возможности

### Будильники
- Точное срабатывание: `SCHEDULE_EXACT_ALARM` + `USE_EXACT_ALARM`, foreground-сервис
  держит процесс живым, `WAKE_LOCK` будит CPU.
- **Wake-task** — к будильнику можно привязать задание, которое нужно выполнить,
  чтобы выключить звонок.
- Переживает перезагрузку телефона: `RECEIVE_BOOT_COMPLETED` и перепланировка
  всех будильников.
- Полноэкранный интент, чтобы будильник появился поверх блокировки.
- Пять мелодий: classic, default, digital, gentle, nature.

### Задачи и привычки
- Задачи с приоритетом, дедлайном и повторением.
- Привычки со стриками, дневными и суммарными нормами.
- **Reality checks** — честная проверка «а не врёшь ли ты себе».
- Свайп для удаления, перетаскивание, пружинные анимации.

### Питание и статистика
- Приёмы пищи, нормы по БЖУ, тренды за 30 дней.
- Кольцевой прогресс по каждой норме и общая статистика.

### Приватность
- PIN-защита и экран блокировки приложения.
- AES-256-GCM для данных на устройстве; ключ — в системном хранилище.
- Экспорт своих данных одним файлом.

### Ада — ИИ-ассистент
Ада живёт прямо в приложении и понимает обычную речь:

> «поставь будильник на 7 утра на рабочие»
> «завтра в 18:30 напомни купить молоко»
> «посчитай сколько я съел»

- Создаёт, меняет и удаляет будильники, задачи, привычки, проверки и приёмы пищи.
- **Умеет отменять**: «Отменить» откатывает последнее действие.
- Работает в **окошке поверх других приложений**.
- Несколько провайдеров на выбор; ключ хранится только на устройстве.

### Система
- **Автообновление** из GitHub Releases: подтверждение, сверка SHA-256 и установка
  системным установщиком поверх старой версии. Данные сохраняются.
- **«Что нового»** тянется из живых релизов, а не из зашитого списка.
- Material You: цвета из системной темы, тёмная тема.
- Тумблеры **вибрации** и **«убрать анимации»**; системная настройка
  «упростить движение» уважается всегда.
- Локализация: **русский / English / Français**.

## Установка

### Готовый APK
1. Открой [Releases](https://github.com/wxstdo-boop/agysha/releases/latest).
2. Скачай `Agysha-<версия>+<код>-<abi>.apk` под свой процессор:
   `arm64-v8a` — почти все современные телефоны, `armeabi-v7a` — старые,
   `x86_64` — эмуляторы.
3. Разреши установку из этого источника, если система попросит.
4. При обновлении данные не пропадут — APK ставится поверх старого.

> Требуется Android 8.0 (API 26) или новее.

> **Play Protect может предупредить об установке.** APK распространяется не
> через Google Play, поэтому система иногда показывает «требуется проверка»
> или «вредоносное приложение». Нажми «Всё равно установить»; если установка
> заблокирована, разреши её для Agysha в Настройки → Безопасность → Play Protect
> (в приложении есть кнопка, ведущая туда).

### Obtainium
[Obtainium](https://github.com/ImranR98/Obtainium) следит за GitHub Releases и
сам предлагает обновления, сверяя APK по SHA-256. Добавь ссылку:

```
https://github.com/wxstdo-boop/agysha
```

### F-Droid
Приложение готовится к публикации в F-Droid. Рецепт сборки и инструкция по
подаче — в [docs/publishing-fdroid.md](docs/publishing-fdroid.md).

### Из исходников
```bash
git clone https://github.com/wxstdo-boop/agysha.git
cd agysha
flutter pub get
flutter run
```

Требования к SDK и решение проблем — в [docs/BUILD.md](docs/BUILD.md).

## Документация

| Документ | О чём |
|---|---|
| [docs/BUILD.md](docs/BUILD.md) | Сборка, запуск, требования, типовые поломки |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Слои, хранение, нативный слой, локализация |
| [docs/TESTS.md](docs/TESTS.md) | Что и как проверяется |
| [docs/RELEASE.md](docs/RELEASE.md) | Релизный процесс и версии |
| [docs/publishing-fdroid.md](docs/publishing-fdroid.md) | F-Droid и другие каталоги |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Стиль, локализация, чек-лист перед PR |
| [SECURITY.md](SECURITY.md) | Как сообщить об уязвимости |

## Архитектура

Обычное Flutter-приложение, Android-first: надёжные будильники обеспечивает
нативный код на Kotlin.

```
lib/
├── main.dart          точка входа, навигация, startup, автосохранение
├── l10n/              переводы (ru/en/fr) и провайдер локали
├── models/            8 моделей: Alarm, Habit, Task, RealityCheck, …
├── screens/           42 экрана и их компоненты
├── services/          39 сервисов: данные, уведомления, ИИ, обновления
├── overlay/           оверлей Ады + мост (io / web)
├── theme/             единый построитель темы (app_theme.dart)
├── utils/             иконки, анимации, токены дизайна
└── widgets/           66 UI-компонентов

android/app/src/main/kotlin/com/wetcorp/agysha/
├── MainActivity.kt             точка входа Android, каналы плагинов
├── AlarmSchedulerPlugin.kt     планирование setAlarmClock, догон
├── AlarmReceiver.kt            приём срабатывания будильника
├── AlarmForegroundService.kt   удержание процесса во время звонка
├── BootReceiver.kt             перепланировка после перезагрузки
├── ScreenReaderService.kt      доступность: чтение экрана
└── AlarmLog.kt                 чёрный ящик срабатываний

third_party/
├── flutter_overlay_window/      форк: регистрирует плагины в оверлее Ады
└── flutter_keyboard_visibility/ форк: поднят compileSdk
```

### Токены дизайна
Геометрия, отступы, длительности и начертания живут в одном файле —
`lib/utils/design_tokens.dart`. Тема (`lib/theme/app_theme.dart`) собирается из
этих шкал, поэтому «ещё один магический радиус» не появляется незаметно.

### Хранение данных
Без базы данных и без облака. Каждая сущность — отдельный зашифрованный
JSON-файл в каталоге документов приложения, настройки — в `SharedPreferences`.
На вебе тот же код пишет в `localStorage`. Запись атомарная (`flush: true`),
с межпроцессной блокировкой и слиянием независимых изменений.

### Стек
| Слой | Что используется |
|---|---|
| UI | Flutter 3.47.5, Material 3, `dynamic_color` для Material You |
| Состояние | `ChangeNotifier` + `ValueNotifier`, без внешних пакетов |
| Хранилище | JSON-файлы + `shared_preferences` |
| Уведомления | `flutter_local_notifications`, `timezone` |
| Оверлей | форк `flutter_overlay_window` |
| ИИ | `http` к выбранному провайдеру, `uuid` для идентификаторов диалогов |

## Тесты

```bash
flutter test --concurrency=1
```

Сьют покрывает стрики привычек, анимации, счётчики, слайдер-пикер, логику
ворк-леда, локализацию диалогов и смоук-тесты экранов. Текущее состояние и
разбор прошлых падений — в [docs/TESTS.md](docs/TESTS.md).

## Релизы

Релизы собирает GitHub Actions по тегу вида `v1.6.233+45305` (тот же формат,
что в `pubspec.yaml`). Workflow восстанавливает keystore из секретов, собирает
`--split-per-abi`, переименовывает ассеты в `Agysha-<версия>+<код>-<abi>.apk`
и публикует в Releases.

```bash
git tag v1.6.233+45305
git push --tags
```

> **`versionCode` должен быть строго выше установленного на телефоне.**
> Flutter прибавляет к номеру из `pubspec.yaml` индекс ABI: `armeabi-v7a` +1000,
> `arm64-v8a` +2000, `x86_64` +4000. Иначе `adb install -r` падает с
> `INSTALL_FAILED_VERSION_DOWNGRADE`.

Подробный разбор — в [docs/RELEASE.md](docs/RELEASE.md).

## Участие

Приветствуются баги, идеи и PR. Перед правкой прочитай
[CONTRIBUTING.md](CONTRIBUTING.md): там договорённости по стилю, локализации и
тому, как не сломать сборку.

## Лицензия

MIT — см. [LICENSE](LICENSE). Приложение бесплатное и открытое. Свои данные
никуда не отправляются, кроме запросов к ИИ-провайдеру, которого ты сам выбрал
в настройках.

## Благодарности

- Flutter и команде Dart.
- Всем, кто присылал баги и идеи по Аде.
