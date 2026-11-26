part of 'profile_screen.dart';

/// Черновик нового друга из нижнего листа.
class _FriendDraft {
  final String name;
  final int colorIndex;
  final int score;

  /// Своя аватарка из галереи, если её выбрали в листе. `null` — показываем
  /// сгенерированный вариант по [colorIndex].
  final String? imagePath;
  const _FriendDraft(this.name, this.colorIndex, this.score, {this.imagePath});
}

/// Максимальная длина имени друга.
const int _kFriendNameMax = 30;

/// Максимальное число знаков в очках рейтинга.
const int _kFriendScoreMax = 7;

/// Высота одной строки рейтинга. Фиксирована: строки живут в общем «слое»
/// на вычисленных позициях, и переезд при смене очков — это анимация `top`.
const double _leaderRowHeight = 52;

/// Случайные «весёлые» очки 40…990.
///
/// Раньше число выводилось детерминированно из имени (хэш строки), и кнопка
/// «кубик» выдавала ОДНО И ТО ЖЕ значение при каждом нажатии — «случайные
/// очки» не рандомили вовсе. Теперь источник — настоящий ГПСЧ, а имя лишь
/// сдвигает диапазон, чтобы число не выглядело совсем произвольным.
String _funScore(String seed) {
  var h = 7;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  final r = math.Random().nextInt(951);
  return '${40 + ((r + h) % 951)}';
}

/// Пул названий для треков подборки: с эмодзи и по-человечески, как
/// подписал бы плейлист живой человек. Держим один набор на все языки —
/// текст берётся из `songTitleN` в переводах.
const List<String> _kSongTitles = [
  '🌙 Три часа ночи, город ещё дышит',
  '🌧 Дождь по стеклу и бас на фоне',
  '🚗 Пустая трасса до самого рассвета',
  '🌆 Неон растекается по мокрому асфальту',
  '☕ Остывший кофе и последний трек',
  '🛞 Шины шуршат по ночному кольцу',
  '💤 Бессонница в наушниках',
  '🎧 Громкость на семнадцати',
  '🌫 Туман над рекой, ни одной машины',
  '🕯 Свет в окне напротив',
  '🖤 Кто-то влюбился в этот бит',
  '🌃 Огни этажей вместо звёзд',
  '🚦 Красный уже минуту, а трек всё идёт',
  '🛣 Разметка уходит в темноту',
  '🎹 Синт, который помнит девяностые',
  '🌀 Голова кружится от сабвуфера',
  '🥀 Тёплый вечер, холодный бас',
  '🏙 Крыша, ветер и пачка сигарет',
  '🔥 Мотор остывает, музыка нет',
  '☎️ Звонок в четыре утра',
  '🧊 Холодный воздух, горячий бит',
  '🌠 Желание, загаданное под бас',
  '🛋 Возвращение домой в тишине',
  '💿 Диск крутится, как эти дни',
  '🌊 Волны баса по бетонным стенам',
  '🕯 Тёмная комната, один свет — экран',
  '🎚 Саб сквозь пол и соседей',
  '🌑 Луна через жалюзи',
  '🐈 Кот на подоконнике, дождь за окном',
  '🍜 Ночная лавка и дым над миской',
  '🎒 Последний автобус уже ушёл',
  '🪩 Знакомый грув из чужого окна',
  '🧣 Куртка нараспашку, мороз по коже',
  '📻 Волна ловит только этот бит',
  '🌁 Мост, туман и пустота',
  '🕰 Часы на башне отстают на жизнь',
];

int _titleHash(String seed) {
  var h = 17;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}

/// Название из пула по индексу. Пул — только запасной русский вариант:
/// на экране всегда берём перевод текущей локали.
String _songTitleAt(int i, BuildContext context) {
  final index = i % _kSongTitles.length;
  return Translations.t('songTitle$index', context, _kSongTitles[index]);
}

/// Строка без ведущего эмодзи: «🌙 Три часа ночи» → «Три часа ночи».
String _titleBody(String title) {
  final space = title.indexOf(' ');
  return space > 0 ? title.substring(space + 1) : title;
}

/// Название, которого ещё нет в [taken] (сравнение без регистра).
///
/// Пока в пуле есть свободные строки — берём из них. Когда пул исчерпан
/// (подборка до 499 треков), собираем пару «строка · строка»: так имена
/// остаются человеческими и не повторяются, а не превращаются в «Трек 47».
String _freshSongTitle(
  Set<String> taken,
  BuildContext context, {
  String? seed,
}) {
  final used = taken.map((t) => t.toLowerCase().trim()).toSet();
  for (var i = 0; i < _kSongTitles.length; i++) {
    final candidate = _songTitleAt(i, context);
    if (!used.contains(candidate.toLowerCase().trim())) return candidate;
  }
  final start = _titleHash(
    seed ?? DateTime.now().microsecondsSinceEpoch.toString(),
  );
  for (var step = 0; step < 8192; step++) {
    final a = (start + step * 37) % _kSongTitles.length;
    final b = (start ~/ 7 + step * 53 + 11) % _kSongTitles.length;
    if (a == b) continue;
    final candidate =
        '${_songTitleAt(b, context)} · ${_titleBody(_songTitleAt(a, context))}';
    if (!used.contains(candidate.toLowerCase().trim())) return candidate;
  }
  return _songTitleAt(start, context);
}

/// Вставка символа в поле с учётом выделения и лимита длины.
///
/// Своя клавиатура пишет в контроллер напрямую, а не через IME, поэтому
/// `inputFormatters` поля здесь не работают — лимит и фильтр проверяем сами.
void _kbInsert(TextEditingController c, String ch, {required int maxLength}) {
  final text = c.text;
  final sel = c.selection;
  final start = sel.isValid ? sel.start.clamp(0, text.length) : text.length;
  final end = sel.isValid ? sel.end.clamp(0, text.length) : text.length;
  final next = text.replaceRange(start, end, ch);
  if (next.length > maxLength) return;
  c.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: start + ch.length),
  );
}

void _kbBackspace(TextEditingController c) {
  final text = c.text;
  if (text.isEmpty) return;
  final sel = c.selection;
  if (sel.isValid && sel.end > sel.start) {
    c.value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, ''),
      selection: TextSelection.collapsed(offset: sel.start),
    );
    return;
  }
  final at = sel.isValid ? sel.start.clamp(1, text.length) : text.length;
  c.value = TextEditingValue(
    text: text.replaceRange(at - 1, at, ''),
    selection: TextSelection.collapsed(offset: at - 1),
  );
}

/// Встроенная клавиатура листов друга: ТА ЖЕ панель, что в чате Ады
/// (`InlineKeyboard`), с ручкой и плавным сворачиванием в узкую полоску.
/// Системная клавиатура в этих листах больше не поднимается: поля
/// `readOnly`, панель живёт внутри листа и подчиняется теме.
Widget _friendsKeyboard({
  required bool open,
  required VoidCallback onOpen,
  required VoidCallback onClose,
  required ValueChanged<String> onChar,
  required VoidCallback onBackspace,
  required VoidCallback onSpace,
}) {
  return AnimatedSize(
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeInOutCubic,
    alignment: Alignment.topCenter,
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) {
        final t = Curves.easeOutCubic.transform(animation.value);
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: AlwaysStoppedAnimation(t),
            // axisAlignment: -1 у вертикального SizeTransition = левый верх.
            alignment: Alignment.topLeft,
            child: child,
          ),
        );
      },
      child: open
          ? Padding(
              key: const ValueKey('friends_kb_open'),
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 12),
              child: InlineKeyboard(
                keyHeight: 46,
                onChar: onChar,
                onBackspace: onBackspace,
                onSpace: onSpace,
                onCollapse: onClose,
              ),
            )
          : InlineKeyboardHandle(
              key: const ValueKey('friends_kb_handle'),
              onExpand: onOpen,
            ),
    ),
  );
}

/// Добавление друга: имя, аватарка, стартовые очки.
class _AddFriendSheet extends StatefulWidget {
  /// Выбор своей картинки из галереи. Лист сам системный пикер не открывает
  /// (см. `_addFriend`): владелец экрана возвращает готовый путь копии либо
  /// `null`, если выбор отменили или копирование не удалось.
  final Future<String?> Function() onPickImage;

  const _AddFriendSheet({required this.onPickImage});

  @override
  State<_AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends State<_AddFriendSheet> {
  final _ctrl = TextEditingController();
  int _avatar = 0;

  /// Своя аватарка друга, выбранная в этом листе. Пока задана — крупный
  /// кружок показывает её, а не сгенерированный вариант по [_avatar].
  String? _imagePath;

  /// Идёт ли выбор картинки: пока системный пикер открыт, повторные тапы по
  /// аватарке не должны запускать второй запрос.
  bool _picking = false;
  final _scoreCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  final _scoreFocus = FocusNode();

  /// Своя клавиатура развёрнута. Системный IME здесь не поднимается:
  /// поля `readOnly`, вся панель живёт внутри листа.
  bool _kbOpen = false;

  /// Куда писать символ: в имя или в очки. Определяется тапом по полю.
  bool _kbScore = false;

  @override
  void initState() {
    super.initState();
    // Очки при открытии — «весёлое» число из имени-заглушки, а не сухой ноль.
    _scoreCtrl.text = _funScore('');
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _scoreFocus.dispose();
    _ctrl.dispose();
    _scoreCtrl.dispose();
    super.dispose();
  }

  void _kbChar(String ch) {
    if (_kbScore) {
      if (!RegExp(r'^[0-9]$').hasMatch(ch)) return;
      _kbInsert(_scoreCtrl, ch, maxLength: _kFriendScoreMax);
    } else {
      _kbInsert(_ctrl, ch, maxLength: _kFriendNameMax);
    }
  }

  void _kbSpace() {
    if (!_kbScore) _kbInsert(_ctrl, ' ', maxLength: _kFriendNameMax);
  }

  void _kbDelete() {
    _kbBackspace(_kbScore ? _scoreCtrl : _ctrl);
  }

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    final score = int.tryParse(_scoreCtrl.text.trim()) ?? 0;
    Navigator.of(
      context,
    ).pop(_FriendDraft(name, _avatar, score, imagePath: _imagePath));
  }

  /// Тап по крупной аватарке: своя картинка из галереи. Пока выбор идёт —
  /// повторные тапы игнорируются, а по возвращении путь мягко подставляется
  /// в кружок (кроссфейд делает сам `ProfileAvatar`).
  Future<void> _pickImage() async {
    if (_picking) return;
    setState(() => _picking = true);
    final path = await widget.onPickImage();
    if (!mounted) return;
    setState(() {
      _picking = false;
      if (path != null) _imagePath = path;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: Radii.sheetTop,
        ),
        child: SafeArea(
          top: false,
          // Когда системная клавиатура поднята, низ экрана уже занят ею:
          // без этого условия между листом и панелью была бы лишняя щель.
          bottom: MediaQuery.viewInsetsOf(context).bottom == 0,
          // Своя клавиатура внизу листа: он не выше 88% экрана, поэтому панель
          // с ручкой и кнопка действия всегда остаются в экране.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.88,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Spacing.md,
                            Spacing.md,
                            Spacing.md,
                            Spacing.sm,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                Translations.t(
                                  'profileAddFriend',
                                  context,
                                  'Добавить друга',
                                ),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: Weights.bold,
                                ),
                              ),
                              const SizedBox(height: Spacing.md),
                              Row(
                                children: [
                                  // Крупная аватарка — сама по себе кнопка «своя из
                                  // галереи»: тап открывает пикер, выбранная картинка
                                  // встаёт на место градиента кроссфейдом. Значок
                                  // камеры подсказывает, что кружок нажимается.
                                  PressScale(
                                    pressedScale: 0.9,
                                    duration: const Duration(milliseconds: 240),
                                    releaseDuration: const Duration(
                                      milliseconds: 460,
                                    ),
                                    child: GestureDetector(
                                      onTap: _pickImage,
                                      behavior: HitTestBehavior.opaque,
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          ProfileAvatar(
                                            index: _avatar,
                                            size: 52,
                                            imagePath: _imagePath,
                                            showIcon: _imagePath == null,
                                          ),
                                          Positioned(
                                            right: -2,
                                            bottom: -2,
                                            child: Container(
                                              padding: const EdgeInsets.all(3),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color:
                                                    theme.colorScheme.surface,
                                                border: Border.all(
                                                  color: theme
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: 0.45),
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.photo_camera_outlined,
                                                size: 13,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: Spacing.md),
                                  Expanded(
                                    child: SmoothTyping(
                                      controller: _ctrl,
                                      style: theme.textTheme.bodyLarge,
                                      // Без «призраков»: при быстром стирании десяток
                                      // гаснущих копий читался как заедание. Появление
                                      // букв остаётся плавным, а удаление — мгновенным
                                      // и ровным.
                                      ghosts: false,
                                      builder: (style) => TextField(
                                        controller: _ctrl,
                                        style: style,
                                        focusNode: _nameFocus,
                                        // Имя набирается СВОЕЙ клавиатурой внизу
                                        // листа: поле только каретка и выделение,
                                        // системный IME не поднимается.
                                        readOnly: true,
                                        showCursor: true,
                                        onTap: () => setState(() {
                                          _kbScore = false;
                                          _kbOpen = true;
                                          _nameFocus.requestFocus();
                                        }),
                                        magnifierConfiguration:
                                            TextMagnifierConfiguration.disabled,
                                        contextMenuBuilder:
                                            minimalContextMenuBuilder,
                                        cursorOpacityAnimates: true,
                                        maxLength: _kFriendNameMax,
                                        inputFormatters: [
                                          LengthLimitingTextInputFormatter(
                                            _kFriendNameMax,
                                          ),
                                        ],
                                        decoration: _fieldDecoration(
                                          theme,
                                          hint: Translations.t(
                                            'profileFriendName',
                                            context,
                                            'Имя друга',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: Spacing.md),
                              SizedBox(
                                height: 46,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: profileAvatarVariants.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: Spacing.xs),
                                  itemBuilder: (context, i) => PressScale(
                                    pressedScale: 0.86,
                                    duration: const Duration(milliseconds: 180),
                                    releaseDuration: const Duration(
                                      milliseconds: 340,
                                    ),
                                    child: GestureDetector(
                                      // Выбор градиента снимает свою картинку: иначе
                                      // непонятно, что показывать в кружке, — и аватарка
                                      // мягко возвращается к сгенерированному варианту.
                                      onTap: () => setState(() {
                                        _imagePath = null;
                                        _avatar = i;
                                      }),
                                      child: AnimatedContainer(
                                        duration: MotionPrefs.shouldReduceMotion
                                            ? Duration.zero
                                            : Motion.normal,
                                        curve: Curves.easeOutCubic,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: i == _avatar
                                                ? theme.colorScheme.primary
                                                : Colors.transparent,
                                            width: 2.5,
                                          ),
                                        ),
                                        padding: const EdgeInsets.all(2),
                                        child: ProfileAvatar(
                                          index: i,
                                          size: 34,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: Spacing.md),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: SmoothTyping(
                                      controller: _scoreCtrl,
                                      style: theme.textTheme.bodyLarge,
                                      ghosts: false,
                                      builder: (style) => TextField(
                                        controller: _scoreCtrl,
                                        style: style,
                                        focusNode: _scoreFocus,
                                        // Очки — тоже своя клавиатура; из неё в это
                                        // поле проходят только цифры (см. _kbChar).
                                        readOnly: true,
                                        showCursor: true,
                                        onTap: () => setState(() {
                                          _kbScore = true;
                                          _kbOpen = true;
                                          _scoreFocus.requestFocus();
                                        }),
                                        magnifierConfiguration:
                                            TextMagnifierConfiguration.disabled,
                                        contextMenuBuilder:
                                            minimalContextMenuBuilder,
                                        cursorOpacityAnimates: true,
                                        maxLength: _kFriendScoreMax,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                          LengthLimitingTextInputFormatter(
                                            _kFriendScoreMax,
                                          ),
                                        ],
                                        decoration: _fieldDecoration(
                                          theme,
                                          label: Translations.t(
                                            'profileFriendScore',
                                            context,
                                            'Очки рейтинга',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: Spacing.xs),
                                  PressScale(
                                    pressedScale: 0.9,
                                    child: IconButton.filledTonal(
                                      tooltip: Translations.t(
                                        'profileFriendScoreRandom',
                                        context,
                                        'Случайные очки',
                                      ),
                                      onPressed: () => setState(
                                        () => _scoreCtrl.text = _funScore(
                                          _ctrl.text,
                                        ),
                                      ),
                                      icon: const Icon(Icons.casino_outlined),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: Spacing.xs),
                              Text(
                                Translations.t(
                                  'profileFriendScoreHint',
                                  context,
                                  'Очки — за активность: привычки, задачи, дни в логе. '
                                      'Чем больше — тем выше в рейтинге.',
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Главное действие — ОТДЕЛЬНАЯ широкая кнопка под полями:
                        // так она не отъедает место у набора и читается как действие,
                        // а не как ещё одна клавиша.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Spacing.md,
                            Spacing.xs,
                            Spacing.md,
                            Spacing.sm,
                          ),
                          child: PressScale(
                            pressedScale: 0.97,
                            duration: const Duration(milliseconds: 200),
                            releaseDuration: const Duration(milliseconds: 340),
                            child: SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: FilledButton(
                                onPressed: _submit,
                                child: Text(
                                  Translations.t('add', context, 'Добавить'),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _friendsKeyboard(
                  open: _kbOpen,
                  onOpen: () => setState(() {
                    _kbOpen = true;
                    (_kbScore ? _scoreFocus : _nameFocus).requestFocus();
                  }),
                  onClose: () {
                    Haptics.light();
                    setState(() => _kbOpen = false);
                  },
                  onChar: _kbChar,
                  onBackspace: _kbDelete,
                  onSpace: _kbSpace,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Итог листа над другом: сохранённые очки либо удаление.
sealed class _FriendOutcome {
  const _FriendOutcome();
}

class _FriendScoreSaved extends _FriendOutcome {
  final ProfileFriend friend;
  const _FriendScoreSaved(this.friend);
}

class _FriendRemoved extends _FriendOutcome {
  const _FriendRemoved();
}

/// Один лист над другом: сначала «Очки/Удалить», по тапу на «Очки» он же
/// ПЕРЕТЕКАЕТ в правку очков.
///
/// Раньше это были два отдельных маршрута: лист действий закрывался, а лист
/// очков открывался следом. Из-за этого затемнения двух маршрутов коротко
/// складывались — позади окна появлялся «второй тёмный фон», а пауза перед
/// открытием читалась торможением. Теперь маршрут ОДИН: затемнение одно и
/// живёт непрерывно, переключение — мягкая смена содержимого с плавной
/// высотой, без закрытия/открытия.
class _FriendSheet extends StatefulWidget {
  final ProfileFriend friend;

  /// Выбор своей картинки из галереи (см. `_copyPickedImageToPrivateDir`).
  /// Передаётся в шаги, чтобы аватарку друга можно было сменить прямо из
  /// листа: тап по кружку — пикер, картинка встаёт на место градиента
  /// кроссфейдом, а в рейтинге строка обновляется тем же сохранением.
  final Future<String?> Function() onPickImage;

  const _FriendSheet({required this.friend, required this.onPickImage});

  @override
  State<_FriendSheet> createState() => _FriendSheetState();
}

class _FriendSheetState extends State<_FriendSheet> {
  bool _score = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MotionPrefs.shouldReduceMotion;
    return AnimatedSize(
      duration: reduce ? Duration.zero : Motion.slow,
      curve: Motion.emphasized,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : Motion.normal,
        // Кривая с НУЛЕВОЙ скоростью на обоих концах: шаг не «выстреливает»
        // в первый кадр и не щёлкает в последнем — переход читается мягким.
        switchInCurve: Motion.emphasized,
        switchOutCurve: Motion.emphasized,
        // Кросс-фейд шагов выравниваем ПО ВЕРХУ: у шага очков высота больше
        // (там поле ввода и кнопка), и при центрировании короткий список
        // действий «прыгал» бы вверх. Ширину/высоту тянет `AnimatedSize` выше.
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        // Проявление + лёгкий «доезд» снизу: шаг не подменяется кадром, а
        // всплывает на место. Оба направления симметричны, поэтому не нужен
        // разбор «входящий/уходящий» по ключу.
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.035),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: _score
            ? _FriendScoreSheet(
                key: const ValueKey('friend_score'),
                friend: widget.friend,
                onSave: (updated) =>
                    Navigator.of(context).pop(_FriendScoreSaved(updated)),
              )
            : _FriendActionsSheet(
                key: const ValueKey('friend_actions'),
                friend: widget.friend,
                onScore: () => setState(() => _score = true),
                onRemove: () =>
                    Navigator.of(context).pop(const _FriendRemoved()),
                // Смена аватарки сохраняется сразу: лист закрывается с новым
                // другом, и строка рейтинга перетекает на его новую картинку.
                onAvatar: () async {
                  final path = await widget.onPickImage();
                  if (path == null || !context.mounted) return;
                  Navigator.of(context).pop(
                    _FriendScoreSaved(widget.friend.copyWith(imagePath: path)),
                  );
                },
              ),
      ),
    );
  }
}

/// Действия над другом: изменить очки или удалить.
class _FriendActionsSheet extends StatelessWidget {
  final ProfileFriend friend;
  final VoidCallback onScore;
  final VoidCallback onRemove;

  /// Тап по аватарке друга: сменить её на свою из галереи.
  final VoidCallback onAvatar;

  const _FriendActionsSheet({
    super.key,
    required this.friend,
    required this.onScore,
    required this.onRemove,
    required this.onAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: Radii.sheetTop,
          ),
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Row(
                  children: [
                    // Кружок нажимается: своя аватарка друга из галереи.
                    // Значок камеры — подсказка, что аватарка меняется.
                    PressScale(
                      pressedScale: 0.9,
                      duration: const Duration(milliseconds: 240),
                      releaseDuration: const Duration(milliseconds: 460),
                      child: GestureDetector(
                        onTap: onAvatar,
                        behavior: HitTestBehavior.opaque,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ProfileAvatar(
                              index: friend.colorIndex,
                              size: 44,
                              imagePath: friend.imagePath,
                              showIcon: !friend.hasImage,
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: theme.colorScheme.surface,
                                  border: Border.all(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.45,
                                    ),
                                  ),
                                ),
                                child: Icon(
                                  Icons.photo_camera_outlined,
                                  size: 12,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Text(
                      friend.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: Weights.semibold,
                      ),
                    ),
                  ],
                ),
              ),
              // Отдача «вдавливанием» на обеих строках: раньше тап по «Очки»
              // и «Удалить» срабатывал без отклика, и палец не чувствовал
              // нажатия.
              _actionTile(
                context,
                theme,
                icon: Icons.tune,
                label: Translations.t('profileFriendSetScore', context, 'Очки'),
                // Смена шага — сразу, без искусственной паузы: плавность
                // теперь несёт сам переход (`SlideTransition` + `AnimatedSize`),
                // а задержка только добавляла лаг между пальцем и откликом.
                onTap: onScore,
              ),
              _actionTile(
                context,
                theme,
                icon: Icons.delete_outline,
                label: Translations.t('delete', context, 'Удалить'),
                danger: true,
                onTap: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionTile(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final color = danger
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    // Раньше строка была `ListTile`: его чернильная волна заливала
    // ПРЯМОУГОЛЬНИК на всю ширину листа, и подсветка читалась «квадратом».
    // `InkWell` со скруглением повторяет форму строки — вспышка под пальцем
    // мягкая и округлая.
    return PressScale(
      // Медленнее и глубже: строка ощутимо «уходит» под палец и мягко
      // возвращается — раньше 150 мс читались как резкий щелчок.
      pressedScale: 0.95,
      duration: const Duration(milliseconds: 240),
      releaseDuration: const Duration(milliseconds: 380),
      child: Material(
        // Свой Material: без него чернильная волна уходила под фон
        // `Container` листа, и Flutter ругался на невидимые splashes.
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm,
            ),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: Spacing.md),
                Text(label, style: TextStyle(color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Изменение очков друга.
class _FriendScoreSheet extends StatefulWidget {
  final ProfileFriend friend;

  /// Отдать сохранённые очки НАРУЖУ. Раньше лист сам делал `pop`, потому что
  /// был отдельным маршрутом; теперь он лишь шаг внутри [_FriendSheet], и
  /// закрывать общий маршрут должен его владелец.
  final ValueChanged<ProfileFriend> onSave;

  const _FriendScoreSheet({
    super.key,
    required this.friend,
    required this.onSave,
  });

  @override
  State<_FriendScoreSheet> createState() => _FriendScoreSheetState();
}

class _FriendScoreSheetState extends State<_FriendScoreSheet> {
  late final TextEditingController _ctrl = TextEditingController(
    text: '${widget.friend.score}',
  );
  final _focus = FocusNode();

  /// Своя клавиатура развёрнута (системный IME здесь не поднимается).
  bool _kbOpen = false;

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _kbChar(String ch) {
    if (!RegExp(r'^[0-9]$').hasMatch(ch)) return;
    _kbInsert(_ctrl, ch, maxLength: _kFriendScoreMax);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: Radii.sheetTop,
        ),
        child: SafeArea(
          top: false,
          // Когда системная клавиатура поднята, низ экрана уже занят ею:
          // без этого условия между листом и панелью была бы лишняя щель.
          bottom: MediaQuery.viewInsetsOf(context).bottom == 0,
          // Своя клавиатура внизу листа: он не выше 88% экрана, поэтому панель
          // с ручкой и кнопка действия всегда остаются в экране.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.88,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Spacing.md,
                            Spacing.md,
                            Spacing.md,
                            Spacing.sm,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Шапка — как у листа действий: аватарка и имя друга.
                              // Раньше окно очков открывалось «с пустого места» — было
                              // не понять, кому правишь счёт.
                              Row(
                                children: [
                                  ProfileAvatar(
                                    index: widget.friend.colorIndex,
                                    size: 40,
                                    imagePath: widget.friend.imagePath,
                                    showIcon: !widget.friend.hasImage,
                                  ),
                                  const SizedBox(width: Spacing.sm),
                                  Expanded(
                                    child: Text(
                                      widget.friend.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: Weights.semibold,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: Spacing.md),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: SmoothTyping(
                                      controller: _ctrl,
                                      style: theme.textTheme.bodyLarge,
                                      ghosts: false,
                                      builder: (style) => TextField(
                                        controller: _ctrl,
                                        style: style,
                                        keyboardType: TextInputType.number,
                                        magnifierConfiguration:
                                            TextMagnifierConfiguration.disabled,
                                        contextMenuBuilder:
                                            minimalContextMenuBuilder,
                                        cursorOpacityAnimates: true,
                                        maxLength: _kFriendScoreMax,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                          LengthLimitingTextInputFormatter(
                                            _kFriendScoreMax,
                                          ),
                                        ],
                                        decoration: _fieldDecoration(
                                          theme,
                                          label: Translations.t(
                                            'profileFriendScore',
                                            context,
                                            'Очки рейтинга',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: Spacing.xs),
                                  PressScale(
                                    pressedScale: 0.9,
                                    child: IconButton.filledTonal(
                                      tooltip: Translations.t(
                                        'profileFriendScoreRandom',
                                        context,
                                        'Случайные очки',
                                      ),
                                      onPressed: () => setState(
                                        () => _ctrl.text = _funScore(
                                          widget.friend.name,
                                        ),
                                      ),
                                      icon: const Icon(Icons.casino_outlined),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: Spacing.md),
                              SizedBox(
                                width: double.infinity,
                                child: PressScale(
                                  pressedScale: 0.96,
                                  pressOverlay: pressGloss(
                                    BorderRadius.circular(999),
                                    strength: 0.22,
                                  ),
                                  maxTiltAngle: 0.22,
                                  child: FilledButton.tonal(
                                    onPressed: () {
                                      final score =
                                          int.tryParse(_ctrl.text.trim()) ?? 0;
                                      widget.onSave(
                                        widget.friend.copyWith(score: score),
                                      );
                                    },
                                    style: _roundButtonStyle(),
                                    child: Text(
                                      Translations.t(
                                        'save',
                                        context,
                                        'Сохранить',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _friendsKeyboard(
                  open: _kbOpen,
                  onOpen: () => setState(() {
                    _kbOpen = true;
                    _focus.requestFocus();
                  }),
                  onClose: () {
                    Haptics.light();
                    setState(() => _kbOpen = false);
                  },
                  onChar: _kbChar,
                  onBackspace: () => _kbBackspace(_ctrl),
                  onSpace: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
