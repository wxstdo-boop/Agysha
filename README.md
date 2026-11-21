<div align="center">
  <img src="assets/agysha.png" alt="Agysha" width="112" height="112" />

  <h1>Agysha</h1>

  <p><strong>Будильник, задачи, привычки и еда — в одном приложении.</strong><br />
  Плюс Ада: ей можно просто сказать, что нужно сделать.</p>

  <p>
    <a href="https://github.com/wxstdo-boop/Agysha/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/wxstdo-boop/Agysha/ci.yml?branch=main&label=CI&color=2ea44f" /></a>
    <a href="https://github.com/wxstdo-boop/Agysha/releases/latest"><img alt="Последний релиз" src="https://img.shields.io/github/v/release/wxstdo-boop/Agysha?label=%D1%80%D0%B5%D0%BB%D0%B8%D0%B7&color=c2185b" /></a>
    <a href="LICENSE"><img alt="Лицензия MIT" src="https://img.shields.io/badge/license-MIT-2ea44f" /></a>
    <img alt="Flutter 3.47.5" src="https://img.shields.io/badge/Flutter-3.47.5-02569a?logo=flutter&logoColor=white" />
    <img alt="Dart 3.12+" src="https://img.shields.io/badge/Dart-3.12%2B-0175C2?logo=dart&logoColor=white" />
    <img alt="Android 8.0+" src="https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white" />
  </p>

  <p>
    <a href="https://github.com/wxstdo-boop/Agysha/releases/latest"><strong>Скачать APK</strong></a>
    &nbsp;·&nbsp;
    <a href="https://apps.obtainium.imranr.dev/redirect?r=obtainium://app/%7B%22id%22%3A%22com.wetcorp.agysha%22%2C%22url%22%3A%22https%3A%2F%2Fgithub.com%2Fwxstdo-boop%2FAgysha%22%2C%22author%22%3A%22wxstdo-boop%22%2C%22name%22%3A%22Agysha%22%7D">Добавить в Obtainium</a>
    &nbsp;·&nbsp;
    <a href="docs/BUILD.md">Собрать самому</a>
    &nbsp;·&nbsp;
    <a href="docs/ARCHITECTURE.md">Как устроено</a>
    &nbsp;·&nbsp;
    <a href="CONTRIBUTING.md">Помочь</a>
  </p>
</div>

---

Agysha — бесплатное Android-приложение. Без рекламы, без аккаунтов, без
облака: всё лежит на телефоне, в обычных JSON-файлах, зашифрованных AES-256-GCM.
Работает офлайн. В сеть ходит только за обновлениями с GitHub и к тому
ИИ-провайдеру, которого ты сам выберешь в настройках.

## Что умеет

### Будильники

- Срабатывают точно и не теряются после перезагрузки телефона.
- **Wake-task**: чтобы выключить звонок, нужно выполнить задание. Просто
  нажать «стоп» спросонья не получится.
- Полноэкранное окно поверх блокировки.
- Пять мелодий: classic, default, digital, gentle, nature.
- Лог срабатываний — если будильник когда-нибудь подведёт, будет видно, почему.

### Задачи и привычки

- Задачи с приоритетом, дедлайном и повтором.
- Привычки со стриками и нормами на день и на всё время.
- **Проверки реальности** — короткие честные вопросы самому себе.
- Свайпы, перетаскивание, пружинные анимации.

### Еда и статистика

- Приёмы пищи, нормы по БЖУ, тренды за 30 дней.
- Кольца прогресса и общая сводка.

### Приватность

- PIN и экран блокировки приложения.
- Ключ шифрования хранится в системном хранилище.
- Экспорт всех данных одним файлом.

### Ада

Ада — помощник внутри приложения. Понимает обычную речь:

> «поставь будильник на 7 утра на рабочие»
> «завтра в 18:30 напомни купить молоко»
> «посчитай, сколько я съел»

- Заводит и правит будильники, задачи, привычки, проверки и приёмы пищи.
- Последнее действие можно отменить одной кнопкой.
- Работает в окошке поверх других приложений.
- Провайдера ИИ выбираешь сам; ключ остаётся на телефоне.

### Мелочи, которые заметны

- **Автообновление** из GitHub Releases: подтверждение, проверка SHA-256,
  установка поверх старой версии. Данные не пропадают.
- «Что нового» берётся из настоящих релизов, а не из зашитого списка.
- Material You: цвета под системную тему, тёмная тема.
- Отдельные переключатели вибрации и анимаций; системное «упростить движение»
  учитывается всегда.
- Русский, English, Français.

## Установка

### APK

1. Открой [Releases](https://github.com/wxstdo-boop/Agysha/releases/latest).
2. Скачай файл под свой процессор:
   `arm64-v8a` — почти все современные телефоны, `armeabi-v7a` — старые,
   `x86_64` — эмуляторы.
3. Разреши установку из этого источника, если система спросит.
4. При обновлении ставь APK поверх старого — данные останутся.

Нужен Android 8.0 (API 26) или новее.

> Play Protect иногда ругается на APK не из Google Play. Это нормально:
> жми «Всё равно установить». Если установка заблокирована, разреши её для
> Agysha в Настройки → Безопасность → Play Protect. В приложении есть кнопка,
> которая ведёт туда же.

### Obtainium

[Obtainium](https://github.com/ImranR98/Obtainium) сам следит за релизами на
GitHub и сверяет APK по SHA-256 — обновления приходят сами, магазин не нужен.

<a href="https://apps.obtainium.imranr.dev/redirect?r=obtainium://app/%7B%22id%22%3A%22com.wetcorp.agysha%22%2C%22url%22%3A%22https%3A%2F%2Fgithub.com%2Fwxstdo-boop%2FAgysha%22%2C%22author%22%3A%22wxstdo-boop%22%2C%22name%22%3A%22Agysha%22%7D"><img src="assets/badge_obtainium.png" alt="Добавить в Obtainium" height="48" /></a>

Кнопка откроет Obtainium с уже заполненной формой. Вручную — просто добавь
ссылку:

```
https://github.com/wxstdo-boop/Agysha
```

### F-Droid

Заявка отправлена и ждёт ревью — как только её примут, Agysha появится в
каталоге и обновления пойдут через него. Рецепт сборки и детали подачи —
в [docs/publishing-fdroid.md](docs/publishing-fdroid.md).

### Из исходников

```bash
git clone https://github.com/wxstdo-boop/Agysha.git
cd Agysha
flutter pub get
flutter run
```

Требования к SDK и типовые проблемы — в [docs/BUILD.md](docs/BUILD.md).

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

## Как устроено

Обычное Flutter-приложение, Android-first. Надёжные будильники — на Kotlin.

```
lib/
├── main.dart          точка входа, навигация, старт, автосохранение
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
этих шкал, поэтому случайный радиус или отступ не появляется незаметно.

### Хранение данных

Ни базы данных, ни облака. Каждая сущность — отдельный зашифрованный JSON-файл
в документах приложения, настройки — в `SharedPreferences`. На вебе тот же код
пишет в `localStorage`. Запись атомарная, с блокировкой и слиянием независимых
изменений.

### Стек

| Слой | Что используется |
|---|---|
| UI | Flutter 3.47.5, Material 3, `dynamic_color` для Material You |
| Состояние | `ChangeNotifier` + `ValueNotifier`, без внешних пакетов |
| Хранилище | JSON-файлы + `shared_preferences` |
| Уведомления | `flutter_local_notifications`, `timezone` |
| Оверлей | форк `flutter_overlay_window` |
| ИИ | `http` к выбранному провайдеру, `uuid` для диалогов |

## Тесты

```bash
flutter test --concurrency=1
```

Проверяются стрики привычек, анимации, счётчики, слайдер-пикер, логика
ворк-леда, локализация диалогов и смоук-тесты экранов. Текущее состояние —
в [docs/TESTS.md](docs/TESTS.md).

## Релизы

Релизы собирает GitHub Actions по тегу вида `v1.6.234+45306` (тот же формат,
что в `pubspec.yaml`). Workflow достаёт keystore из секретов, собирает
`--split-per-abi`, переименовывает файлы в `Agysha-<версия>+<код>-<abi>.apk`
и публикует в Releases.

```bash
git tag v1.6.234+45306
git push --tags
```

> **versionCode должен быть выше установленного на телефоне.** Flutter
> прибавляет к номеру из `pubspec.yaml` индекс ABI: `armeabi-v7a` +1000,
> `arm64-v8a` +2000, `x86_64` +4000. Иначе `adb install -r` упадёт с
> `INSTALL_FAILED_VERSION_DOWNGRADE`.

Подробности — в [docs/RELEASE.md](docs/RELEASE.md).

## Участие

Баги и идеи — в issues, правки — в PR. Перед этим загляни в
[CONTRIBUTING.md](CONTRIBUTING.md): там про стиль, локализацию и то, как не
сломать сборку.

## Лицензия

MIT, см. [LICENSE](LICENSE). Приложение бесплатное. Твои данные никуда не
уходят, кроме запросов к ИИ-провайдеру, которого ты выбрал сам.

## Спасибо

- Flutter и команде Dart.
- Всем, кто присылал баги и идеи.
