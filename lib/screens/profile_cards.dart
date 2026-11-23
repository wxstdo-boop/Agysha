part of 'profile_screen.dart';

/// Карточки экрана профиля: шапка с аватаркой и талисманами, имя,
/// онлайн-статус, музыка, рейтинг, очки, подарки и события Agysha.
///
/// Вынесены из `profile_screen.dart` отдельным part-файлом: после нескольких
/// кругов правок файл вырос до трёх тысяч строк, и найти в нём нужную
/// карточку стало дороже, чем открыть новый файл. Поведение не менялось —
/// это тот же класс состояния, расширенный [extension] в той же библиотеке.
extension _ProfileCards on _ProfileScreenState {
  /// Шапка профиля: крупная аватарка со спектром, размашистыми талисманами вокруг карточки, имя и престижный титул.
  Widget _headerCard(ThemeData theme) {
    final name = _service.displayName.isEmpty
        ? Translations.t('profileAnonymous', context, 'Аноним')
        : _service.displayName;
    final talisman = _service.activeTalisman;
    final favGifts = _service.favoriteGifts;
    const spots = [
      _TalismanSpot(top: 8, left: 20),
      _TalismanSpot(top: 14, right: 26),
      _TalismanSpot(top: 56, left: 12),
      _TalismanSpot(top: 82, right: 16),
      _TalismanSpot(top: 112, left: 36),
    ];

    return _Card(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. Арт активных талисманов прямо на фоне карточки аватара (кибер-руны, созвездия)
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: favGifts.isNotEmpty
                  ? RepaintBoundary(
                      key: ValueKey(
                        'header_talisman_bg_${favGifts.map((g) => g.id).join('_')}',
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.xl),
                        child: CustomPaint(
                          painter: _HeaderCardTalismanPainter(
                            color: favGifts.first.rarity.color,
                            accent: BrandColors.red,
                            colors: favGifts
                                .map((g) => g.rarity.color)
                                .toList(),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('no_talisman_header_bg'),
                    ),
            ),
          ),
          // 2. Размашистые парящие NFT-талисманы вокруг карточки на фоне (до 5 избранных)
          ...spots.asMap().entries.map((entry) {
            final idx = entry.key;
            final spot = entry.value;
            final gift = idx < favGifts.length ? favGifts[idx] : null;
            return Positioned(
              top: spot.top,
              left: spot.left,
              right: spot.right,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 480),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.70, end: 1.0).animate(
                      CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                    ),
                    child: child,
                  ),
                ),
                child: gift != null
                    ? KeyedSubtree(
                        key: ValueKey('floating_talisman_${gift.id}'),
                        child: PressScale(
                          pressedScale: 0.90,
                          duration: const Duration(milliseconds: 180),
                          releaseDuration: const Duration(milliseconds: 240),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              Haptics.select();
                              showGiftDetailsSheet(context, gift, () {
                                if (mounted) refreshUi(() {});
                              });
                            },
                            child: Container(
                              width: 25,
                              height: 25,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF0C0E1A),
                                border: Border.all(
                                  color: gift.rarity.color,
                                  width: 1.1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: gift.rarity.color.withValues(
                                      alpha: 0.40,
                                    ),
                                    blurRadius: 6,
                                    spreadRadius: 0,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CustomPaint(
                                    painter: SharpArtifactPainter(
                                      giftId: gift.id,
                                      color: gift.rarity.color,
                                      isFavorite: true,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('empty_talisman_spot'),
                      ),
              ),
            );
          }),
          Column(
            children: [
              const SizedBox(height: Spacing.xs),
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.85,
                          end: 1.0,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: talisman != null
                        ? Container(
                            key: ValueKey('talisman_aura_${talisman.id}'),
                            width: 126,
                            height: 126,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  talisman.rarity.color.withValues(alpha: 0.38),
                                  BrandColors.red.withValues(alpha: 0.18),
                                  Colors.transparent,
                                ],
                                stops: const [0.35, 0.70, 1.0],
                              ),
                            ),
                          )
                        : const SizedBox(
                            key: ValueKey('no_talisman_aura'),
                            width: 126,
                            height: 126,
                          ),
                  ),
                  AudioSpectrumRing(
                    radius: 48,
                    child: SizedBox(
                      width: 96,
                      height: 96,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          // Аватарка с тактильным откликом и плавной сменой
                          PressScale(
                            pressedScale: 0.94,
                            duration: const Duration(milliseconds: 240),
                            releaseDuration: const Duration(milliseconds: 320),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _pickAvatar,
                              onLongPress: _pickAvatar,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 320),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, anim) =>
                                    FadeTransition(
                                      opacity: anim,
                                      child: ScaleTransition(
                                        scale: Tween<double>(
                                          begin: 0.92,
                                          end: 1.0,
                                        ).animate(anim),
                                        child: child,
                                      ),
                                    ),
                                child: ProfileAvatar(
                                  key: ValueKey(
                                    'avatar_${_service.avatarIndex}_${_service.avatarImagePath}',
                                  ),
                                  index: _service.avatarIndex,
                                  size: 96,
                                  glow: true,
                                  imagePath: _service.avatarImagePath,
                                  motion: _scrollCtrl,
                                  motionOf: () => _scrollCtrl.hasClients
                                      ? (_scrollCtrl.offset / 140)
                                      : 0.0,
                                ),
                              ),
                            ),
                          ),
                          // Компактный значок смены авы: строго зафиксирован на аватарке, никогда не съезжает
                          Positioned(
                            right: 2,
                            bottom: 2,
                            child: PressScale(
                              pressedScale: 0.88,
                              child: GestureDetector(
                                onTap: _pickAvatar,
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.colorScheme.surface,
                                      width: 1.8,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.40),
                                        blurRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.photo_camera_rounded,
                                    size: 13,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              // Кружок слева от имени
              Center(
                child: Transform.translate(
                  offset: Offset(-_dotOverhang, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OnlineDot(size: _dotSize, onTap: _toggleOnline),
                      const SizedBox(width: 1),
                      AnimatedSwitcher(
                        duration: MotionPrefs.shouldReduceMotion
                            ? Duration.zero
                            : Motion.normal,
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SizeTransition(
                            axis: Axis.horizontal,
                            sizeFactor: anim,
                            child: child,
                          ),
                        ),
                        child: Text(
                          name,
                          key: ValueKey(name),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: Weights.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Престижный титул (с непрерывным стадионным скруглением и плавной стрелочкой)
              PressScale(
                pressedScale: 0.94,
                child: GestureDetector(
                  onTap: _showPrestigeTitlePicker,
                  child: Container(
                    decoration: ShapeDecoration(
                      color: BrandColors.red.withValues(alpha: 0.10),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: BrandColors.red.withValues(alpha: 0.42),
                          width: 0.9,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            size: 14,
                            color: BrandColors.red,
                          ),
                          const SizedBox(width: 4),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.centerLeft,
                            clipBehavior: Clip.hardEdge,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              layoutBuilder: (currentChild, previousChildren) =>
                                  Stack(
                                    alignment: Alignment.centerLeft,
                                    children: [
                                      ...previousChildren.map(
                                        (p) => Positioned.fill(
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: p,
                                          ),
                                        ),
                                      ),
                                      ?currentChild,
                                    ],
                                  ),
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(opacity: anim, child: child),
                              child: Text(
                                _service.prestigeTitle,
                                key: ValueKey(_service.prestigeTitle),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          AnimatedRotation(
                            turns: _isPrestigePickerOpen ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const List<String> _prestigeTitles = [
    'Cyberpunk 2077 Legend',
    'Night City Legend',
    'Самурай сна',
    'Повелитель времени',
    'Кибер-ранняя пташка',
    'Неоновый призрак',
    'Мастер дзена',
    'Хранитель рассвета',
  ];

  void _showPrestigeTitlePicker() async {
    Haptics.select();
    refreshUi(() => _isPrestigePickerOpen = true);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: _sheetStyle(),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF12121C) : theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: BrandColors.red.withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.22,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  Translations.t(
                    'profilePrestigeTitle',
                    context,
                    'Престижный титул профиля',
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: Weights.bold,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Wrap(
                  spacing: Spacing.xs,
                  runSpacing: Spacing.xs,
                  children: _prestigeTitles.map((t) {
                    final isSelected = _service.prestigeTitle == t;
                    return PressScale(
                      pressedScale: 0.94,
                      child: GestureDetector(
                        onTap: () async {
                          await Haptics.select();
                          await _service.setPrestigeTitle(t);
                          if (mounted) refreshUi(() {});
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? BrandColors.red
                                : theme.colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(Radii.pill),
                            border: Border.all(
                              color: isSelected
                                  ? BrandColors.red
                                  : theme.colorScheme.outline.withValues(
                                      alpha: 0.25,
                                    ),
                              width: isSelected ? 1.4 : 1.0,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: BrandColors.red.withValues(
                                        alpha: 0.35,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            t,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (mounted) {
      refreshUi(() => _isPrestigePickerOpen = false);
    }
  }

  Widget _giftsCard(ThemeData theme) {
    final gifts = _service.gifts;
    return _Card(
      title: Translations.t(
        'profileArtifactsTitle',
        context,
        'Коллекция артефактов',
      ),
      icon: Icons.auto_awesome,
      // Наклонённая карточка не должна срезаться краем плашки.
      clipContent: false,
      trailing: Text(
        Translations.t(
          'countShort',
          context,
          '{n} шт.',
        ).replaceAll('{n}', '${gifts.length}'),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
      child: SizedBox(
        height: 220,
        // Ленивый список с фиксированной шириной карточки: коллекция на
        // сотни артефактов раньше строилась вся целиком при каждом кадре
        // прокрутки — отсюда рывки у краёв. Растяжение по краям — Bouncing.
        // Карточку больше не пересобираем на старте и конце прокрутки:
        // раньше из-за этого весь список перестраивался дважды за жест, и
        // на быстром листании карточки успевали пропасть на кадр. Теперь
        // карточка сама отличает листание от игры и гаснет без анимации.
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          itemExtent: GiftCard3D.defaultWidth + Spacing.sm,
          // Соседние карточки держим заранее собранными: иначе на быстром
          // листании крайняя карточка успевала появиться и пропасть.
          // Запас по краям шире одной карточки: при быстром листании
          // следующая карточка уже собрана и не успевает «прорадать».
          scrollCacheExtent: const ScrollCacheExtent.pixels(900),
          itemCount: gifts.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(right: Spacing.sm),
            // RepaintBoundary — внутри GiftCard3D, под поворотом: так наклон
            // не растрирует карточку заново на каждом кадре.
            child: GiftCard3D(
              key: ValueKey('gift_card_${gifts[i].id}'),
              gift: gifts[i],
              onFavoriteToggled: () => refreshUi(() {}),
            ),
          ),
        ),
      ),
    );
  }

  /// Видимый диаметр кружка онлайна у имени, px.
  static const double _dotSize = 11;

  /// «Свес» зоны тапа кружка влево от глифа: половина разницы между зоной
  /// тапа и самим глифом. На столько сдвигаем пару «кружок + имя», чтобы имя
  /// осталось по центру карточки.
  static const double _dotOverhang = (OnlineDot.tapTarget - _dotSize) / 2;

  /// Лимит короткого имени: 10 символов. Счётчик под полем не нужен —
  /// ввод просто обрезается, а подпись «Короткое имя» уже всё объясняет.
  static const int _nameMaxLength = 10;

  Widget _nameCard(ThemeData theme) {
    return _Card(
      title: Translations.t('profileName', context, 'Короткое имя'),
      icon: Icons.badge_outlined,
      child: Row(
        children: [
          Expanded(
            // Как в остальных полях приложения: буквы проявляются и гаснут
            // по одной ([SmoothTyping]), лупа выделения выключена, меню —
            // короткое (Копировать/Вставить/Вырезать). Само поле прозрачное,
            // «мозг» ввода — настоящий TextField внутри.
            //
            // Подсказка «Как вас звать?» нарисована ПОВЕРХ поля отдельным
            // слоем: штатный `hintText` исчезает мгновенно и не умеет
            // возвращаться плавно, а нам нужен мягкий фейд и при вводе, и при
            // стирании.
            child: Stack(
              children: [
                // Невидимое поле ловит тап и отдаёт фокус: тап по подсказке
                // должен открывать ввод, иначе «поле не работает».
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _nameFocus.requestFocus(),
                  ),
                ),
                SmoothTyping(
                  controller: _nameCtrl,
                  style: theme.textTheme.bodyLarge,
                  builder: (style) => TextField(
                    controller: _nameCtrl,
                    style: style,
                    magnifierConfiguration: TextMagnifierConfiguration.disabled,
                    contextMenuBuilder: minimalContextMenuBuilder,
                    focusNode: _nameFocus,
                    textInputAction: TextInputAction.done,
                    maxLength: _nameMaxLength,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(_nameMaxLength),
                    ],
                    onSubmitted: (_) => _saveName(),
                    cursorOpacityAnimates: true,
                    decoration: _fieldDecoration(theme),
                  ),
                ),
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _hintCtrl,
                    builder: (context, _) {
                      final t = _hintCtrl.value;
                      if (t <= 0.001) return const SizedBox.shrink();
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: Spacing.sm),
                          child: Opacity(
                            opacity: t,
                            child: Text(
                              Translations.t(
                                'profileNameHint',
                                context,
                                'Как вас звать?',
                              ),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.xs),
          // Отдача «вдавливанием», как у значка «Назад»: кнопка мягко
          // уменьшается под пальцем и так же возвращается.
          PressScale(
            pressedScale: 0.94,
            child: FilledButton.tonal(
              onPressed: _saveName,
              style: _roundButtonStyle(),
              child: Text(Translations.t('save', context, 'Сохранить')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _onlineCard(ThemeData theme) {
    return _Card(
      title: Translations.t('profileOnlineTitle', context, 'Онлайн-статус'),
      icon: Icons.podcasts_outlined,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Translations.t(
                    'profileOnlineSwitch',
                    context,
                    'Показывать красный кружок',
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  Translations.t(
                    'profileOnlineSwitchDesc',
                    context,
                    'Другие увидят, что вы на связи',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          // Тот же объёмный переключатель, что в настройках: статус не
          // выпадает из общего вида приложения.
          VolumetricSwitch(
            value: _service.online,
            onChanged: (_) => _toggleOnline(),
            activeColor: theme.colorScheme.primary,
            semanticLabel: Translations.t(
              'profileOnlineSwitch',
              context,
              'Показывать красный кружок',
            ),
          ),
        ],
      ),
    );
  }

  /// Логотип Agysha в размере глифа: заголовки карточек остаются одной
  /// высоты, а карточка музыки получает своё лицо.
  Widget _agyshaBadge(ThemeData theme) {
    const size = 20.0;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.asset(
        'assets/agysha.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Декодируем ровно под экранный размер: полный PNG в 20 px — это
        // лишние мегабайты в памяти на каждом кадре перестройки.
        cacheWidth: (size * dpr).round(),
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => Icon(
          Icons.music_note_outlined,
          size: 18,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _musicCard(ThemeData theme) {
    final tracks = _service.tracks;
    final cs = theme.colorScheme;
    final dur = MotionPrefs.shouldReduceMotion ? Duration.zero : Motion.slow;

    return _Card(
      title: Translations.t('profileMusic', context, 'Твоя музыка'),
      // Вместо глифа ноты — сама Agysha: карточка музыки узнаётся по лицу
      // приложения, а не по безликой иконке.
      badge: _agyshaBadge(theme),
      // Общая отдача карточки: нажатие вдавливает всю плашку, наклон
      // ловит палец. Жесты внутри строк трека сами выигрывают хит-тест,
      // поэтому тап по названию/корзине не спорит с этим эффектом.
      pressable: true,
      // Счётчик подборки меняется ПО ЦИФРАМ, как очки рейтинга: при
      // добавлении/удалении трека разряд не подменяется кадром, а мягко
      // перетекает. Знаменатель — константа, поэтому он статичен.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SmoothDigits(
            value: tracks.length,
            sample: '00',
            alignment: Alignment.centerRight,
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.primary,
              fontWeight: Weights.semibold,
            ),
          ),
          Text(
            '/${ProfileService.maxTracks}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Высота блока тянется ОДНИМ AnimatedSize: и появление первого
          // трека, и удаление последнего идут непрерывно. Пустая подсказка
          // живёт ВНУТРИ этого блока и сама схлопывается/раскрывается по
          // высоте — поэтому переход «последний трек → пусто» не дёргает
          // раскладку влево (раньше список и подсказка менялись двумя
          // разными механизмами, и текст прыгал).
          AnimatedSize(
            duration: dur,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _emptyMusicHint(theme, visible: tracks.isEmpty),
                for (final t in tracks) _trackRow(theme, t),
              ],
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PressScale(
                  pressedScale: 0.94,
                  child: FilledButton.tonalIcon(
                    onPressed: _service.canAddTrack ? _addMusic : null,
                    style: _roundButtonStyle(),
                    icon: const Icon(Icons.library_music_outlined),
                    label: Text(
                      _service.canAddTrack
                          ? Translations.t(
                              'profileMusicAdd',
                              context,
                              'Добавить',
                            )
                          : Translations.t(
                              'profileMusicFull',
                              context,
                              'Уже 499 треков',
                            ),
                    ),
                  ),
                ),
                PressScale(
                  pressedScale: 0.94,
                  child: FilledButton.tonal(
                    onPressed: _service.canAddTrack && !_isSearchingHardtekk
                        ? _searchAndAddHardtekkInline
                        : null,
                    style: _roundButtonStyle(),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeInOutCubic,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.94,
                              end: 1.0,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: _isSearchingHardtekk
                            ? Row(
                                key: const ValueKey('searching_mode'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        BrandColors.red,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    Translations.t(
                                      'searching',
                                      context,
                                      'Ищем…',
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                key: const ValueKey('search_idle'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.search_rounded, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    Translations.t(
                                      'searchIdle',
                                      context,
                                      'Поиск',
                                    ),
                                  ),
                                ],
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
    );
  }

  /// Подсказка «добавьте трек»: растёт из нуля и так же уходит. Живёт в
  /// общем блоке с треками, поэтому переход к пустому состоянию (и обратно)
  /// идёт одной плавной раскладкой, без рывка текста влево.
  Widget _emptyMusicHint(ThemeData theme, {required bool visible}) {
    final dur = MotionPrefs.shouldReduceMotion
        ? Duration.zero
        : _ProfileScreenState._trackCollapse;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: visible ? 1.0 : 0.0),
      duration: dur,
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: v.clamp(0.0, 1.0),
          child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
        ),
      ),
      child: Padding(
        key: const ValueKey('music_empty'),
        padding: const EdgeInsets.only(bottom: Spacing.xs),
        child: Text(
          Translations.t(
            'profileMusicEmpty',
            context,
            'Добавьте свой трек — он будет играть в профиле',
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// Одна строка трека: появление «врастает» из нуля, удаление схлопывается.
  /// Длительность и кривая те же, что у [AnimatedSize] над блоком, поэтому
  /// соседи подаются вверх ОДНОЙ анимацией, а не двумя спорящими.
  Widget _trackRow(ThemeData theme, MusicTrack track) {
    final playing = _music.playing && _music.path == track.path;
    final removing = _removingTrackIds.contains(track.id);
    final isNew = _newTrackIds.contains(track.id);
    final dur = MotionPrefs.shouldReduceMotion
        ? Duration.zero
        : _ProfileScreenState._trackCollapse;
    return TweenAnimationBuilder<double>(
      key: ValueKey('track_${track.id}'),
      tween: Tween(begin: 0.0, end: removing ? 0.0 : 1.0),
      duration: dur,
      curve: Curves.easeInOutCubic,
      builder: (context, v, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: v.clamp(0.0, 1.0),
          child: Opacity(
            opacity: Curves.easeOut.transform(v).clamp(0.0, 1.0),
            child: child,
          ),
        ),
      ),
      child: _TrackRow(
        track: track,
        playing: playing,
        growFromZero: isNew,
        mode: _music.mode,
        onToggle: () => _toggleTrack(track),
        onCycleMode: () {
          Haptics.select();
          unawaited(_music.cycleQueueMode());
        },
        onRemove: () => _removeTrack(track),
      ),
    );
  }

  /// Карточка «Твои очки»: итог копилки и разбор «за что начислено».
  ///
  /// Цифры значимые — каждая категория растёт от реального действия, и это
  /// видно прямо здесь: понятно, за что именно набежали очки, а не просто
  /// «какое-то число».
  Widget _scoreCard(ThemeData theme) {
    final breakdown = _service.scoreBreakdown();
    final total = _service.localScore();
    final maxPoints = breakdown.values.fold<int>(0, (a, b) => a > b ? a : b);
    return _Card(
      title: Translations.t('scoreTitle', context, 'Твои очки'),
      icon: Icons.workspace_premium_outlined,
      // Итог и его потолок: цифра — как раньше, под ней полупрозрачной
      // строкой предел копилки, чтобы «сколько ещё осталось» было видно
      // сразу, а не только когда счётчик упрётся.
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SmoothDigits(
            value: total,
            sample: '0000',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: Weights.bold,
            ),
          ),
          Text(
            '(${Translations.t('scoreLimitNote', context, 'лимит 10 000 000 000')})',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 9.5,
              height: 1.2,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final kind in ScoreKind.values)
            if (breakdown[kind]! > 0 || _showEmptyScore)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.xs),
                child: _scoreRow(
                  theme,
                  kind,
                  breakdown[kind]!,
                  maxPoints: maxPoints,
                ),
              ),
          const SizedBox(height: Spacing.xs),
          Text(
            Translations.t(
              'scoreHint',
              context,
              'Очки растут за реальные дела: привычки, задачи, общение с Адой, '
                  'еду и проверки. Их не отбирают — это твои достижения.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Всегда ли показывать нулевые категории. Пока очков нет вовсе — список
  /// пустых строк читался бы «сломанным», поэтому прячем их, но итог держим.
  bool get _showEmptyScore => false;

  Widget _scoreRow(
    ThemeData theme,
    ScoreKind kind,
    int points, {
    required int maxPoints,
  }) {
    final cs = theme.colorScheme;
    final frac = maxPoints <= 0 ? 0.0 : (points / maxPoints).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 118,
          child: Text(
            _scoreLabel(kind),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: Spacing.xs),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: frac),
              duration: MotionPrefs.shouldReduceMotion
                  ? Duration.zero
                  : Motion.slow,
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHighest.withValues(
                  alpha: 0.6,
                ),
                valueColor: AlwaysStoppedAnimation<Color>(
                  cs.primary.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: Spacing.xs),
        SizedBox(
          width: 52,
          child: SmoothDigits(
            value: points,
            sample: '000',
            alignment: Alignment.centerRight,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: Weights.semibold,
              color: cs.primary,
            ),
          ),
        ),
      ],
    );
  }

  String _scoreLabel(ScoreKind kind) => switch (kind) {
    ScoreKind.habit => Translations.t('scoreHabit', context, 'Привычки'),
    ScoreKind.task => Translations.t('scoreTask', context, 'Задачи'),
    ScoreKind.ai => Translations.t('scoreAi', context, 'Общение с Адой'),
    ScoreKind.meal => Translations.t('scoreMeal', context, 'Приёмы пищи'),
    ScoreKind.check => Translations.t(
      'scoreCheck',
      context,
      'Проверки реальности',
    ),
    ScoreKind.day => Translations.t('scoreDay', context, 'Активные дни'),
  };

  Widget _leaderboardCard(ThemeData theme) {
    final rows = _service.leaderboard(
      selfFallback: Translations.t('profileMe', context, 'Я'),
    );
    return _Card(
      title: Translations.t('profileLeaderboard', context, 'Рейтинг'),
      icon: Icons.emoji_events_outlined,
      // Кнопка «добавить друга» — БЕЗ цветной оправы: красный кант читался
      // случайным ободком вокруг системной иконки. Отдачу под пальцем держит
      // `PressScale`, а сама кнопка остаётся штатной `IconButton`.
      trailing: PressScale(
        pressedScale: 0.86,
        child: IconButton(
          // На пределе (50 друзей) кнопка гаснет: понятно, что дальше
          // добавлять некуда, и не приходится жать «в пустоту».
          onPressed: _service.canAddFriend ? _addFriend : null,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          tooltip: _service.canAddFriend
              ? Translations.t('profileAddFriend', context, 'Добавить друга')
              : Translations.t(
                  'profileFriendsFull',
                  context,
                  'В рейтинге уже 50 друзей',
                ),
        ),
      ),
      // Строки рейтинга ПЕРЕЕЗЖАЮТ плавно: каждая строка лежит в общем
      // «слое» на своей вертикальной позиции (`AnimatedPositioned` по ключу
      // друга), поэтому смена очков меняет места анимацией, а не мгновенной
      // перестановкой. AnimatedSize тянет высоту при добавлении/удалении.
      child: AnimatedSize(
        duration: MotionPrefs.shouldReduceMotion ? Duration.zero : Motion.slow,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: rows.length * _leaderRowHeight,
              child: Stack(
                children: [
                  for (var i = 0; i < rows.length; i++)
                    AnimatedPositioned(
                      // Ключ — id друга: при смене очков Flutter видит тот же
                      // виджет на новой позиции и анимирует переезд.
                      key: ValueKey(rows[i].id),
                      duration: MotionPrefs.shouldReduceMotion
                          ? Duration.zero
                          : Motion.glide,
                      curve: Curves.easeOutCubic,
                      left: 0,
                      right: 0,
                      top: i * _leaderRowHeight,
                      child: SizedBox(
                        height: _leaderRowHeight,
                        child: _leaderRow(
                          theme,
                          rows[i],
                          rank: i + 1,
                          isMe: rows[i].id == 'me',
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_service.friends.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Text(
                  Translations.t(
                    'profileNoFriends',
                    context,
                    'Добавьте друзей, чтобы сравнивать прогресс',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _leaderRow(
    ThemeData theme,
    ProfileFriend f, {
    required int rank,
    required bool isMe,
  }) {
    final cs = theme.colorScheme;
    return PressScale(
      // Строка друга мягко уменьшается под пальцем и так же плавно
      // возвращается: зажатие карточки читается как нажатие.
      pressedScale: 0.97,
      duration: const Duration(milliseconds: 180),
      releaseDuration: const Duration(milliseconds: 320),
      enabled: !isMe,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: isMe ? null : () => _editFriend(f),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '$rank',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: rank <= 3 ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: Weights.bold,
                  ),
                ),
              ),
              ProfileAvatar(
                index: f.colorIndex,
                size: 36,
                // Своя аватарка из галереи — и в строке «Я» рейтинга, и у
                // друзей: картинка приходит в самой строке (`f.imagePath`),
                // поэтому после выбора она сразу и плавно встаёт на место
                // сгенерированного варианта.
                imagePath: f.imagePath,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: isMe ? Weights.bold : Weights.regular,
                  ),
                ),
              ),
              // Очки меняются ПО БУКВАМ, тем же приёмом, что и поле «Очки
              // рейтинга» ([SmoothTyping]): изменившаяся цифра проявляется из
              // прозрачного, старая мягко гаснет. Раньше здесь «докатывался»
              // барабан `AnimatedCounter` — при правке счёта он читался грубым
              // подменом. `sample` держит ширину, чтобы при «99 → 100» строка
              // не дёргалась по горизонтали.
              SmoothDigits(
                value: f.score,
                sample: '0000',
                alignment: Alignment.centerRight,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: Weights.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eventsCard(ThemeData theme) {
    return _Card(
      title: Translations.t('profileEvents', context, 'События'),
      icon: Icons.event_outlined,
      child: Column(
        children: [
          for (final e in _events)
            // Отдача уменьшением + СКРУГЛЁННЫЙ фон зажатия: тап по пункту
            // события читается как нажатие, а подсветка повторяет форму
            // строки, а не заливает квадрат.
            PressScale(
              pressedScale: 0.96,
              duration: const Duration(milliseconds: 180),
              releaseDuration: const Duration(milliseconds: 320),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.md),
                onTap: () => e.banner ? _openEventBanner() : _openEvent(e.url),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.local_activity_outlined,
                          color: theme.colorScheme.onPrimaryContainer,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.title,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: Weights.semibold,
                              ),
                            ),
                            Text(
                              e.subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Icon(
                        e.banner
                            ? Icons.celebration_outlined
                            : Icons.open_in_new,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
