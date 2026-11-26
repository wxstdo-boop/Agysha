import 'dart:async';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import '../widgets/smooth_tooltip.dart' show SmoothTooltip, BackButtonTooltip;
import 'package:uuid/uuid.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/alarm.dart';
import '../models/wake_task.dart';
import '../services/alarm_service.dart';
import '../services/prefs.dart';
import '../l10n/translations.dart';
import '../utils/context_menu.dart';
import '../utils/snackbar.dart';
import '../utils/wide_dash_formatter.dart';
import '../utils/wide_dash_controller.dart';
import '../widgets/stagger_in.dart';
import '../widgets/sliding_picker.dart';
import '../widgets/manual_time_dialog.dart';
import '../widgets/volumetric_switch.dart';
import '../widgets/smooth_char_counter.dart';
import '../widgets/smooth_typing.dart';
import '../widgets/smooth_keyboard_body.dart';
import '../widgets/blood_speck.dart' show BloodSpeck, BloodSpeckPainter;
import '../widgets/press_scale.dart';
import '../widgets/auto_save_on_exit.dart';
import '../widgets/smooth_caret.dart';

class AddAlarmScreen extends StatefulWidget {
  final Alarm? existing;
  const AddAlarmScreen({super.key, this.existing});

  @override
  State<AddAlarmScreen> createState() => _AddAlarmScreenState();
}

class _AddAlarmScreenState extends State<AddAlarmScreen> {
  late TimeOfDay _time;

  /// Время на момент открытия формы: по нему видно, трогал ли человек что-то.
  late TimeOfDay _initialTime;
  late List<int> _repeatDays;
  late TextEditingController _labelCtrl;
  late WakeUpTask _taskType;
  late bool _vibrate;
  late String _soundName;
  String? _customSoundPath;
  bool _editing = false;
  AudioPlayer? _player;
  // Подписка на «звук доиграл». Плеер один на экран, поэтому и слушатель
  // должен быть один: без этой ссылки на каждый тап по звуку добавлялась
  // новая подписка, и на завершение приходило столько setState, сколько
  // было нажатий.
  StreamSubscription<void>? _completeSub;
  String? _playingSound;
  late List<String> _availableSounds;

  // Удалённые звуки запоминаем, чтобы они не возвращались при создании новых
  // будильников. Дополнительно персистим в globalPrefs, иначе после
  // перезапуска приложения Set теряется и звуки возвращаются снова.
  static final Set<String> deletedSounds = {};

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _time = widget.existing!.time;
      _repeatDays = List.from(widget.existing!.repeatDays);
      _labelCtrl = WideDashController(text: widget.existing!.label);
      _taskType = widget.existing!.taskType;
      _vibrate = widget.existing!.vibrate;
      _soundName = widget.existing!.soundName;
      _customSoundPath = widget.existing!.customSoundPath;
      _editing = true;
    } else {
      _time = TimeOfDay(
        hour: DateTime.now().hour,
        minute: DateTime.now().minute,
      );
      _repeatDays = [];
      _labelCtrl = WideDashController();
      _taskType = WakeUpTask.none;
      _vibrate = true;
      _soundName = 'Default';
    }

    _initialTime = _time;

    // ВАЖНО: при редактировании существующего будильника НЕ перезагружаем
    // список из Alarm.sounds. Иначе удалённые звуки вернутся.
    //
    // Подтягиваем удалённые звуки из prefs — только если локальный кэш
    // пустой (это первый State в текущем процессе). Иначе могли бы
    // перезатереть более свежий список.
    if (deletedSounds.isEmpty) {
      final stored = globalPrefs.getStringList('deleted_alarm_sounds');
      if (stored != null && stored.isNotEmpty) {
        deletedSounds.addAll(stored);
      }
    }
    if (widget.existing != null) {
      _availableSounds = Alarm.sounds
          .where((s) => !deletedSounds.contains(s))
          .toList();
    } else {
      _availableSounds = Alarm.sounds
          .where((s) => !deletedSounds.contains(s))
          .toList();
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _completeSub?.cancel();
    _completeSub = null;
    _player?.dispose();
    super.dispose();
  }

  // Затухание — fire-and-forget, поэтому ему нужен номер поколения: без
  // него рампа из предыдущего прослушивания добирается до уже нового звука
  // и либо обрывает его своим stop(), либо оставляет играть на 0.1 громкости
  // (отсюда жалоба «нажимаю играть, а звук глухой / не играется»).
  int _playSeq = 0;

  // Один переиспользуемый плеер на весь экран: создание/уничтожение
  // AudioPlayer на каждый тап давало «щелчки»/шум на слабых устройствах.
  // Остановка — ТОЛЬКО через плавное затухание громкости (иначе stop()
  // режет звук резко, с «щелчком»/шумом).
  Future<void> _fadeOutStop(AudioPlayer? p, int seq) async {
    if (p == null) return;
    try {
      // Последний шаг — НОЛЬ: stop() на остаточной громкости режет волну
      // на полупериоде и даёт слышимый щелчок/шум в конце.
      for (var i = 10; i >= 0; i--) {
        // Появилось новое прослушивание — рампу сворачиваем, не трогаем звук.
        if (seq != _playSeq) return;
        await p.setVolume(i / 10);
        await Future.delayed(const Duration(milliseconds: 18));
      }
      if (seq != _playSeq) return;
      await p.stop();
      await p.setVolume(1.0);
    } catch (_) {}
  }

  Future<void> _previewSound(String name) async {
    // Остановка: иконка и состояние меняются МГНОВЕННО, звук плавно
    // затухает в фоне — чтобы кнопка не «лагала» на слабых устройствах.
    if (_playingSound == name) {
      _playingSound = null;
      if (mounted) setState(() {});
      _fadeOutStop(_player, ++_playSeq);
      return;
    }
    final seq = ++_playSeq;
    _playingSound = name;
    if (mounted) setState(() {});
    try {
      final player = _player ??= AudioPlayer();
      // Слушатель вешаем ОДИН раз за жизнь плеера; короткий звук в 1с
      // иначе можно не поймать при быстрой смене.
      _completeSub ??= player.onPlayerComplete.listen((_) {
        if (mounted && _playingSound != null) {
          setState(() => _playingSound = null);
        }
      });
      // Перед новым звуком — жёсткий сброс, а НЕ плавное затухание: рампа
      // на 180 мс успевала пересечься со следующим тапом.
      await player.stop();
      if (seq != _playSeq) return;
      await player.setVolume(1.0);
      if (name == 'Custom') {
        // Свой файл — только если он реально читается. Без проверки
        // DeviceFileSource кидал бы исключение и тест проигрывал тишину.
        final fallback =
            _builtinSource('Default') ?? AssetSource('sounds/default.wav');
        if (_customSoundPath != null) {
          try {
            final f = File(_customSoundPath!);
            if (f.existsSync() && f.lengthSync() > 0) {
              await player.play(DeviceFileSource(_customSoundPath!));
            } else {
              await player.play(fallback);
            }
          } catch (_) {
            await player.play(fallback);
          }
        } else {
          await player.play(fallback);
        }
      } else {
        final source = _builtinSource(name);
        if (source != null) {
          await player.play(source);
        }
      }
    } catch (_) {
      if (seq == _playSeq && mounted && _playingSound == name) {
        setState(() => _playingSound = null);
      }
    }
  }

  /// Удаление звука (зажатие пункта в карусели): свой файл — сбрасываем,
  /// встроенный — прячем навсегда (как кнопкой удаления).
  void _deleteSound(String name) {
    // Свой звук без файла — удалять нечего: зажатие не делает ничего.
    if (name == 'Custom' && _customSoundPath == null) return;
    // Сначала плавно останавливаем прослушивание удаляемого звука, чтобы
    // старый плеер не продолжал играть поверх уже обновлённого списка.
    if (_playingSound == name) {
      _playingSound = null;
      _fadeOutStop(_player, ++_playSeq);
    }
    if (name == 'Custom') {
      setState(() {
        _customSoundPath = null;
        // Оставляем карточку «Свой» выбранной даже после удаления файла:
        // следующий файл можно добавить в тот же слот без скачка на Default.
        _soundName = 'Custom';
        if (!_availableSounds.contains('Custom')) {
          _availableSounds.add('Custom');
        }
      });
      return;
    }
    final removed = name;
    // Будильники, у которых стоял этот звук, — запоминаем для отката.
    final affected = AlarmService().alarms
        .where((a) => a.soundName == removed)
        .toList();
    setState(() {
      _availableSounds.remove(removed);
      deletedSounds.add(removed);
      _soundName = _availableSounds.isNotEmpty
          ? _availableSounds.first
          : 'Default';
    });
    globalPrefs.setStringList('deleted_alarm_sounds', deletedSounds.toList());
    for (final a in affected) {
      AlarmService().update(
        a.copyWith(soundName: 'Default', customSoundPath: null),
      );
    }
    // Плавный снекбар с «Отменить» — случайно удалённый звук можно вернуть.
    showBeautifulSnackBar(
      context,
      message: Translations.t('soundDeleted', context, 'Sound deleted'),
      icon: Icons.music_off_outlined,
      iconColor: Colors.orange,
      duration: const Duration(seconds: 4),
      actionLabel: Translations.t('undo', context, 'Undo'),
      onAction: () => _restoreSound(removed, affected),
    );
  }

  /// Откат удаления звука (кнопка «Отменить»): звук снова в списке,
  /// будильники со старым звуком возвращены.
  void _restoreSound(String name, List<Alarm> affected) {
    setState(() {
      deletedSounds.remove(name);
      _availableSounds = Alarm.sounds
          .where((s) => !deletedSounds.contains(s))
          .toList();
      if (_availableSounds.contains(name)) _soundName = name;
    });
    globalPrefs.setStringList('deleted_alarm_sounds', deletedSounds.toList());
    for (final a in affected) {
      AlarmService().update(a);
    }
  }

  /// Имя файла без служебных символов, которыми нельзя назвать файл.
  /// Пробелы и юникод (в т.ч. кириллица) сохраняются: пользователь должен
  /// узнать свой трек по имени.
  static String _safeSoundFileName(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final name = cleaned.isEmpty ? 'sound' : cleaned;
    return name.length > 40 ? name.substring(0, 40).trim() : name;
  }

  /// Видимое имя своего звука — имя файла без расширения.
  static String _displaySoundName(String path) {
    final file = path.split('/').last;
    final dot = file.lastIndexOf('.');
    return dot > 0 ? file.substring(0, dot) : file;
  }

  Source? _builtinSource(String name) {
    switch (name) {
      case 'Default':
        return AssetSource('sounds/default.wav');
      case 'Gentle':
        return AssetSource('sounds/gentle.wav');
      case 'Classic':
        return AssetSource('sounds/classic.wav');
      case 'Digital':
        return AssetSource('sounds/digital.wav');
      case 'Nature':
        return AssetSource('sounds/nature.wav');
      default:
        return null;
    }
  }

  Future<void> _pickCustomSound() async {
    // Системный пикер на время открытия — отключаем PIN-блюр, иначе
    // экран «сереет» до появления выбора файлов.
    systemUiActive = true;
    // file_picker 13: статические методы вместо `platform`, одиночный выбор —
    // `pickFile` (отдаёт `PlatformFile?`, при отмене null).
    final picked = await FilePicker.pickFile(type: FileType.audio);
    systemUiActive = false;
    if (picked?.path == null) return;
    final srcPath = picked!.path!;
    // Звонок играет по сохранённому пути, который переживёт очистку кэша и
    // удаление источника. file_picker отдаёт либо путь общего хранилища
    // (на Android 13+ MediaPlayer/FileDataSource без READ_MEDIA_AUDIO не
    // читает), либо кэш, который система стирает. Поэтому всегда копируем в
    // приватную папку приложения и храним именно её путь. Если копия не
    // удалась — не оставляем нечитаемый путь: иначе будильник будет звонеть
    // системным файлом, а тест — тихой.
    try {
      final directory = await getApplicationDocumentsDirectory();
      final soundsDir = Directory('${directory.path}/sounds');
      await soundsDir.create(recursive: true);
      final ext = picked.extension?.isNotEmpty == true
          ? picked.extension!
          : 'wav';
      // Имя файла берём из имени выбранного файла, а не из служебного
      // `custom_<timestamp>`: в карусели звук показывается по имени файла,
      // и раньше там стояло что-то вроде «custom_1732…» — читалось как
      // случайное имя. Одинаковые имена не перетираем: добавляем _2, _3.
      final rawName = picked.name.replaceAll(RegExp(r'\.[^.]*$'), '').trim();
      final baseName = _safeSoundFileName(rawName);
      var newPath = '${soundsDir.path}/$baseName.$ext';
      var attempt = 2;
      while (File(newPath).existsSync()) {
        newPath = '${soundsDir.path}/${baseName}_$attempt.$ext';
        attempt++;
      }
      await File(srcPath).copy(newPath);
      if (mounted) {
        setState(() {
          _customSoundPath = newPath;
          _soundName = 'Custom';
        });
      }
      return;
    } catch (_) {
      // Копия не удалась — прерываем: путь, который оставим без копии,
      // нельзя прочитать на целевом устройстве (content-URI или
      // внешний файл), и иначе звук проигрывается не своим.
      if (mounted) {
        showBeautifulSnackBar(
          context,
          message: Translations.t(
            'pickCustomFailed',
            context,
            'Could not load the selected sound',
          ),
          icon: Icons.error_outline,
          iconColor: Colors.red,
        );
      }
    }
  }

  void _renameCustomSound() {
    if (_customSoundPath == null) return;
    final path = _customSoundPath!;
    // Показываем ТОЛЬКО базовое имя (без расширения); расширение берём из
    // исходного файла. Не добавляем постоянно ".wav", иначе вдвоём получалось
    // ".mp3.wav" / ".wav.wav" — имя менялось, а формат файла сломался.
    final fileName = path.split('/').last;
    final ext = fileName.contains('.')
        ? '.${fileName.split('.').last}'
        : '.wav';
    final baseName = fileName.contains('.')
        ? fileName.substring(0, fileName.length - ext.length)
        : fileName;
    final ctrl = WideDashController(text: baseName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Translations.t('renameSound', context, 'Rename sound')),
        content: SmoothTyping(
          controller: ctrl,
          builder: (style) => TextField(
            style: style,
            cursorOpacityAnimates: true,
            magnifierConfiguration: TextMagnifierConfiguration.disabled,
            controller: ctrl,
            contextMenuBuilder: minimalContextMenuBuilder,
            maxLength: 20,
            inputFormatters: [WideDashFormatter()],
            enableSuggestions: false,
            autocorrect: false,
            buildCounter: smoothCharCounterBuilder,
            decoration: InputDecoration(
              labelText: Translations.t('soundName', context),
            ),
          ),
        ),
        actions: [
          PressScale(
            pressedScale: 0.94,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Translations.cancelOf(context)),
            ),
          ),
          PressScale(
            pressedScale: 0.94,
            pressOverlay: pressGloss(
              BorderRadius.circular(999),
              strength: 0.12,
            ),
            maxTiltAngle: 0.22,
            child: TextButton(
              onPressed: () async {
                final raw = ctrl.text.trim();
                // Разрешаем вводить только имя: любое расширение, которое
                // пользователь напишет, отбрасываем, чтобы формат файла
                // оставался неизменным (исходный ext).
                final newName = raw.contains('.')
                    ? raw.substring(0, raw.lastIndexOf('.'))
                    : raw;
                if (newName.isEmpty || newName.length > 20) return;
                // Нельзя ввести имя каталога или любые разделители.
                if (newName.contains('/') || newName.contains('\\')) return;
                final directory = await getApplicationDocumentsDirectory();
                final soundsDir = Directory('${directory.path}/sounds');
                try {
                  // Папка может не существовать — без неё rename всегда падал
                  // в «фолбэк» (имя не менялось, английский снекбар).
                  await soundsDir.create(recursive: true);
                  final oldFile = File(path);
                  final newPath = '${soundsDir.path}/$newName$ext';
                  if (newPath == path) {
                    // Имя не изменилось — ничего копировать/переименовывать не
                    // нужно (избегаем копирования файла на себя).
                  } else if (oldFile.existsSync() &&
                      oldFile.parent.path == soundsDir.path) {
                    await oldFile.rename(newPath);
                  } else if (oldFile.existsSync()) {
                    // Файл лежит вне документов (Downloads и т.п.) — копируем
                    // в документы приложения, чтобы имя реально сохранилось.
                    await oldFile.copy(newPath);
                  }
                  if (!mounted || !ctx.mounted) return;
                  setState(() {
                    _customSoundPath = newPath;
                    _soundName = 'Custom';
                  });
                  Navigator.pop(ctx);
                  showBeautifulSnackBar(
                    context,
                    message: Translations.t(
                      'soundRenamed',
                      context,
                      'Sound renamed',
                    ),
                  );
                } catch (e) {
                  if (!mounted || !ctx.mounted) return;
                  Navigator.pop(ctx);
                  showBeautifulSnackBar(
                    context,
                    message: Translations.t(
                      'soundRenameFailed',
                      context,
                      'Could not rename sound',
                    ),
                  );
                }
              },
              child: Text(Translations.saveOf(context)),
            ),
          ),
        ],
      ),
    );
  }

  void _pickTime() async {
    // Свой диалог ручного времени: у штатного showTimePicker в режиме
    // клавиатуры лупа/магнифай не отключается, поэтому время вводим
    // через собственные TextField'ы без выделения.
    final picked = await showManualTimePicker(context, initial: _time);
    // Экран могли закрыть, пока открыт системный пикер: без проверки
    // setState падал бы на размонтированном State.
    if (!mounted || picked == null) return;
    setState(() => _time = picked);
  }

  void _toggleDay(int day) {
    setState(() {
      if (_repeatDays.contains(day)) {
        _repeatDays.remove(day);
      } else {
        _repeatDays.add(day);
        _repeatDays.sort();
      }
    });
  }

  /// Выход с формы при включённом автосохранении: сохраняем только то, что
  /// человек реально менял. Просто открыть «новый будильник» и уйти назад
  /// по-прежнему ничего не создаёт.
  void _exitWithAutoSave() {
    final touched =
        _editing ||
        _time != _initialTime ||
        _repeatDays.isNotEmpty ||
        _labelCtrl.text.trim().isNotEmpty ||
        _taskType != WakeUpTask.none ||
        _vibrate != true ||
        _soundName != 'Default' ||
        _customSoundPath != null;
    if (!touched) {
      Navigator.of(context).pop();
      return;
    }
    _save();
  }

  void _save() {
    final alarm = Alarm(
      id: widget.existing?.id ?? const Uuid().v4(),
      time: _time,
      repeatDays: _repeatDays,
      // Редактирование НЕ включает будильник само: раньше конструктор
      // по умолчанию ставил `enabled: true`, и любой выключенный будильник
      // после правки времени начинал звонить. Сохраняем прошлое состояние.
      enabled: widget.existing?.enabled ?? true,
      pinned: widget.existing?.pinned ?? false,
      notes: widget.existing?.notes ?? '',
      label: _labelCtrl.text.trim(),
      taskType: _taskType,
      vibrate: _vibrate,
      soundName: _soundName,
      customSoundPath: _customSoundPath,
    );
    Navigator.of(context).pop(alarm);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayNames = Translations.dayNames(context);

    return AutoSaveOnExit(
      onExit: _exitWithAutoSave,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _editing
                ? Translations.editAlarmOf(context)
                : Translations.newAlarmOf(context),
          ),
          leading: const BackButtonTooltip(),
          centerTitle: true,
          actions: [
            // Верхняя кнопка «Сохранить» — та же плавная отдача-«вдавливание»,
            // что у «Назад» и у остальных кнопок окна (PressScale).
            PressScale(
              pressedScale: 0.92,
              duration: const Duration(milliseconds: 180),
              releaseDuration: const Duration(milliseconds: 240),
              pressOverlay: pressGloss(
                BorderRadius.circular(999),
                strength: 0.12,
              ),
              maxTiltAngle: 0.22,
              child: TextButton(
                onPressed: _save,
                child: Text(Translations.saveOf(context)),
              ),
            ),
          ],
        ),
        resizeToAvoidBottomInset: false,
        body: SmoothKeyboardBody(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              StaggerIn(
                index: 0,
                child: PressScale(
                  // Плитка времени — плавная отдача-«вдавливание» всей карточки целиком.
                  pressedScale: 0.94,
                  // Фон отдачи набирается ПЛАВНО, а не вспышкой: при
                  // easeOut и 140 мс тинт выходил на полную за первые 30 мс и
                  // читался мгновенным. Симметричная кривая и 280 мс дают
                  // мягкое «набухание» под пальцем.
                  curve: Curves.easeInOutCubic,
                  releaseCurve: Curves.easeInOutCubic,
                  duration: const Duration(milliseconds: 280),
                  releaseDuration: const Duration(milliseconds: 340),
                  // Ровно та же отдача фона, что у строки «Вибрация»: слой
                  // ПОВЕРХ карточки, сквозь который видно её собственную
                  // поверхность. Без него нажатие читалось только сжатием, а
                  // владелец ждал «такой же фон, как у вибрации» — и чтобы
                  // фон под ним не глотался (0.07, не плотная заливка).
                  pressOverlay: pressTintOverlay(
                    BorderRadius.circular(20),
                    strength: 0.07,
                  ),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.access_time),
                        title: ClipRect(
                          // Выбранное время в окне правки плавно «проезжает»
                          // при смене (как ролик в пикере), а не щёлкает.
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                SlideTransition(
                                  position: Tween(
                                    begin: const Offset(0, 0.4),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                ),
                            child: Text(
                              _time.format(context),
                              key: ValueKey(
                                'alarmedit_${_time.format(context)}',
                              ),
                              style: theme.textTheme.headlineMedium,
                            ),
                          ),
                        ),
                        subtitle: Text(Translations.tapToChangeOf(context)),
                        onTap: _pickTime,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              StaggerIn(
                index: 1,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Translations.repeatOf(context),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(7, (i) {
                            final day = i + 1;
                            final selected = _repeatDays.contains(day);
                            return _AlarmDayChip(
                              day: day,
                              label: dayNames[i],
                              selected: selected,
                              onTap: () => _toggleDay(day),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              StaggerIn(
                index: 2,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Translations.wakeUpTaskOf(context),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...WakeUpTask.values.map((task) {
                          final selected = _taskType == task;
                          IconData icon;
                          switch (task) {
                            case WakeUpTask.none:
                              icon = Icons.notifications_off_outlined;
                            case WakeUpTask.math:
                              icon = Icons.calculate_outlined;
                            case WakeUpTask.pattern:
                              icon = Icons.touch_app_outlined;
                            case WakeUpTask.memory:
                              icon = Icons.psychology_outlined;
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: PressScale(
                              // Плавная отдача-«вдавливание» выбора типа задачи.
                              pressedScale: 0.97,
                              duration: const Duration(milliseconds: 160),
                              releaseDuration: const Duration(
                                milliseconds: 220,
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => setState(() => _taskType = task),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 260),
                                  curve: Curves.easeOutCubic,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: selected
                                        ? theme.colorScheme.primaryContainer
                                              .withValues(alpha: 0.45)
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: selected
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.outlineVariant
                                                .withValues(alpha: 0.5),
                                      width: selected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(icon, size: 20),
                                      const SizedBox(width: 12),
                                      Text(Translations.t(task.key, context)),
                                      const Spacer(),
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        transitionBuilder: (child, animation) =>
                                            ScaleTransition(
                                              scale: animation,
                                              child: FadeTransition(
                                                opacity: animation,
                                                child: child,
                                              ),
                                            ),
                                        child: selected
                                            ? Icon(
                                                Icons.check_circle,
                                                key: ValueKey(
                                                  'wake_selected_${task.key}',
                                                ),
                                                size: 20,
                                                color:
                                                    theme.colorScheme.primary,
                                              )
                                            : const SizedBox(
                                                key: ValueKey(
                                                  'wake_unselected',
                                                ),
                                                width: 20,
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              StaggerIn(
                index: 3,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: SmoothTyping(
                      controller: _labelCtrl,
                      builder: (style) => SmoothCaret(
                        builder: (context, caret) => TextField(
                          scrollController: caret,
                          style: style,
                          cursorOpacityAnimates: true,
                          magnifierConfiguration:
                              TextMagnifierConfiguration.disabled,
                          controller: _labelCtrl,
                          contextMenuBuilder: minimalContextMenuBuilder,
                          maxLength: 100,
                          inputFormatters: [WideDashFormatter()],
                          enableSuggestions: false,
                          autocorrect: false,
                          maxLines: 2,
                          buildCounter: smoothCharCounterBuilder,
                          decoration: InputDecoration(
                            labelText: Translations.labelOf(context),
                            prefixIcon: const Icon(Icons.label_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              StaggerIn(
                index: 4,
                child: PressScale(
                  // Строка «Вибрация» — плавная отдача-«вдавливание» всей карточки целиком.
                  pressedScale: 0.94,
                  // Фон отдачи набирается ПЛАВНО, а не вспышкой: при
                  // easeOut и 140 мс тинт выходил на полную за первые 30 мс и
                  // читался мгновенным. Симметричная кривая и 280 мс дают
                  // мягкое «набухание» под пальцем.
                  curve: Curves.easeInOutCubic,
                  releaseCurve: Curves.easeInOutCubic,
                  duration: const Duration(milliseconds: 280),
                  releaseDuration: const Duration(milliseconds: 340),
                  // Card ниже залит непрозрачной поверхностью, поэтому
                  // pressTint под содержимым не виден. Отдача фона — слоем
                  // ПОВЕРХ карточки: под пальцем она темнеет красноватым,
                  // а не только сжимается.
                  pressOverlay: pressTintOverlay(
                    BorderRadius.circular(20),
                    strength: 0.07,
                  ),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                      ),
                      child: ListTile(
                        title: Text(Translations.vibrateOf(context)),
                        leading: const Icon(Icons.vibration),
                        onTap: () => setState(() => _vibrate = !_vibrate),
                        trailing: VolumetricSwitch(
                          value: _vibrate,
                          onChanged: (v) => setState(() => _vibrate = v),
                          activeColor: Theme.of(context).colorScheme.primary,
                          semanticLabel: Translations.vibrateOf(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              StaggerIn(
                index: 5,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Translations.soundOf(context),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 520),
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                                alignment: Alignment.center,
                                children: <Widget>[
                                  ...previousChildren,
                                  ?currentChild,
                                ],
                              ),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                    begin: 0.96,
                                    end: 1.0,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: SlidingPicker<String>(
                            key: ValueKey(_availableSounds.join('|')),
                            items: _availableSounds,
                            selected: _soundName,
                            height: 84,
                            // Карточки звуков были заметно уже карточки
                            // настроек и выглядели «скукоженными»: при 0.6
                            // в ячейку помещалось меньше половины полосы.
                            // 0.72 всё ещё читалось как сжатая карточка,
                            // поэтому 0.86: таблетка почти во всю ширину
                            // карточки звуков, а соседи выглядывают ровной
                            // узкой кромкой.
                            viewportFraction: 0.86,
                            onChanged: (s) => setState(() => _soundName = s),
                            itemBuilder: (context, s, selected) {
                              final isCustom = s == 'Custom';
                              final displayName =
                                  isCustom && _customSoundPath != null
                                  ? _displaySoundName(_customSoundPath!)
                                  : (isCustom
                                        ? Translations.t('customSound', context)
                                        : s);
                              // Красивая «таблетка» звука: форма ПОСТОЯННА
                              // (одна толщина обводки, один padding, одна
                              // весовка шрифта), а выбор проявляется лерпом
                              // цвета. Выбранная — плоская монотонная заливка
                              // (без градиента и без свечения-«отсвета»).
                              final cs = theme.colorScheme;
                              final selBorder = selected
                                  ? cs.primary.withValues(alpha: 0.85)
                                  : cs.outlineVariant.withValues(alpha: 0.45);
                              final selFg = selected
                                  ? cs.onPrimaryContainer
                                  : cs.onSurface;
                              final selIcon = selected
                                  ? cs.primary
                                  : cs.onSurfaceVariant;
                              // Заливка МОНОТОННАЯ: одна спокойная поверхность
                              // вместо градиента и без свечения-«отсвета» за
                              // таблеткой (жалоба «жёсткий отсвет фона»).
                              // Выбранность читается кромкой и цветом.
                              final fill = selected
                                  ? cs.primaryContainer
                                  : cs.surfaceContainerHigh;
                              return PressScale(
                                // Таблетка звука: не только вдавливание, но и
                                // наклон под палец с отсветом — раньше она
                                // только сжималась, и отдача читалась слабо.
                                pressedScale: 0.93,
                                maxTiltAngle: 0.22,
                                pressTint: cs.primary,
                                pressTintStrength: 0.08,
                                pressTintRadius: BorderRadius.circular(18),
                                pressOverlay: pressGloss(
                                  BorderRadius.circular(18),
                                  strength: 0.14,
                                ),
                                duration: const Duration(milliseconds: 160),
                                releaseDuration: const Duration(
                                  milliseconds: 240,
                                ),
                                child: GestureDetector(
                                  onTap: () => setState(() => _soundName = s),
                                  // Зажатие звука — удаление (свой файл или
                                  // встроенный).
                                  onLongPress: () => _deleteSound(s),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 240),
                                    // Симметричная кривая: заливка выбранной
                                    // таблетки перетекает без «толчка» на
                                    // старте и без рывка на финише.
                                    curve: Curves.easeInOutCubic,
                                    // Карточка заполняет ячейку карусели. Без
                                    // этого AnimatedContainer сжимался по
                                    // тексту (118 px из 248) и Align внутри
                                    // ItemReveal прижимал его влево — владелец
                                    // видел «скукоженные квадратики слева, не
                                    // по центру».
                                    width: double.infinity,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                      vertical: 4,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      // Почти прямоугольник: владелец просил,
                                      // чтобы карточка звука читалась
                                      // «прямоугольничком», а не пилюлей-
                                      // капсулой. Радиус только смягчает углы.
                                      borderRadius: BorderRadius.circular(9),
                                      // Плоская монотонная заливка: без
                                      // градиента и без свечения, никакого
                                      // «отсвета» за таблеткой.
                                      color: fill,
                                      border: Border.all(
                                        color: selBorder,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          isCustom
                                              ? Icons.folder_open
                                              : Icons.music_note_outlined,
                                          size: 20,
                                          color: selIcon,
                                        ),
                                        const SizedBox(height: 4),
                                        // Вес ПОСТОЯННЫЙ (w600): метрики текста
                                        // не меняются — кнопка не «дёргается»
                                        // при выборе. Выбранность читается по
                                        // заливке и обводке.
                                        Text(
                                          displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: selFg,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Управление текущим звуком: прослушать / загрузить /
                        // переименовать. Кнопки переключаются плавно, значок
                        // проигрывания тает/появляется мягко.
                        AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.center,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: Tween<double>(
                                      begin: 0.9,
                                      end: 1.0,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: Row(
                              key: ValueKey(
                                // Состояние «играет» больше не входит в ключ:
                                // раньше каждый тап play/stop пересоздавал
                                // весь ряд и он мигал. Теперь меняется только
                                // значок внутри капсулы.
                                '$_soundName|${_customSoundPath != null}',
                              ),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Красные кнопки-капсулы действий звука:
                                // прослушать / загрузить свой / переименовать.
                                // Были «голые» IconButton — stray-tap не ловился,
                                // поверхность не было, выглядели случано.
                                _SoundActionChip(
                                  tooltip: Translations.soundOf(context),
                                  glowing: _playingSound == _soundName,
                                  onPressed: () => _previewSound(_soundName),
                                  // Смена значка play ⇄ stop — медленнее и
                                  // без «прыжка»: кросс-фейд 340 мс с
                                  // минимальным масштабом вместо резкой
                                  // подмены 250 мс с 0.75.
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 340),
                                    switchInCurve: Curves.easeInOutCubic,
                                    switchOutCurve: Curves.easeInOutCubic,
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(
                                          opacity: animation,
                                          child: ScaleTransition(
                                            scale: Tween<double>(
                                              begin: 0.92,
                                              end: 1.0,
                                            ).animate(animation),
                                            child: child,
                                          ),
                                        ),
                                    child: Icon(
                                      _playingSound == _soundName
                                          ? Icons.stop_rounded
                                          : Icons.play_arrow_rounded,
                                      key: ValueKey(
                                        _playingSound == _soundName,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_soundName == 'Custom')
                                  _SoundActionChip(
                                    tooltip: Translations.t(
                                      'customSound',
                                      context,
                                    ),
                                    onPressed: _pickCustomSound,
                                    child: const Icon(
                                      Icons.upload_file_rounded,
                                    ),
                                  ),
                                if (_soundName == 'Custom' &&
                                    _customSoundPath != null)
                                  _SoundActionChip(
                                    tooltip: Translations.t(
                                      'renameSound',
                                      context,
                                      'Rename',
                                    ),
                                    onPressed: _renameCustomSound,
                                    child: const Icon(
                                      Icons.drive_file_rename_outline,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плавный чип дня недели будильника — ровно как в повторении привычки:
/// цвет/граница/галочка анимируются (240 мс) вместо резкого FilterChip.
class _AlarmDayChip extends StatelessWidget {
  final int day;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AlarmDayChip({
    required this.day,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PressScale(
      // Плавная отдача-«вдавливание» у чипа дня — как у остальных кнопок окна.
      pressedScale: 0.90,
      duration: const Duration(milliseconds: 160),
      releaseDuration: const Duration(milliseconds: 220),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? cs.primary
              : cs.surfaceContainerHigh.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: 1.2,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.6,
                        end: 1,
                      ).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: selected
                        ? Icon(
                            Icons.check,
                            key: ValueKey('alarm_day_on_$day'),
                            size: 14,
                            color: cs.onPrimary,
                          )
                        : const SizedBox(
                            key: ValueKey('alarm_day_off'),
                            width: 14,
                          ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Красная капсула-действие в секции звука будильника.
///
/// Была штатная IconButton: без поверхности, с резким сплэшем и без
/// отдачи. Теперь — фирменная капсула с Blutod-красной кромкой приложения
/// (как у CTA поддержки): мягкое зажатие (220 мс, easeOutCubic), лёгкий
/// тап-хаптик и подсветка-свечение, пока звук проигрывается.
class _SoundActionChip extends StatefulWidget {
  final String tooltip;
  final Widget child;
  final VoidCallback onPressed;

  /// Звук сейчас играет — кромка и подложка подсвечиваются ярче.
  final bool glowing;

  const _SoundActionChip({
    required this.tooltip,
    required this.child,
    required this.onPressed,
    this.glowing = false,
  });

  @override
  State<_SoundActionChip> createState() => _SoundActionChipState();
}

class _SoundActionChipState extends State<_SoundActionChip> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final glowing = widget.glowing;
    // Три кнопки звука приведены к тому же виду, что бейдж «Сегодня очищено»
    // в привычках (см. HabitsScreen._erasedBadge): на тёмной теме — тихая
    // однотонная капсула с винным подтоном, на светлой — винная таблетка
    // BloodSpeck. Поверхность капсулы ПОСТОЯННА: при проигрывании меняется
    // только сам значок (плавно, 260 мс), а не подложка под ним — раньше
    // фон кнопки вспыхивал и гас, и это читалось как мигание.
    final BoxDecoration decoration;
    final bool bloodFill;
    if (dark) {
      bloodFill = false;
      // Та же спокойная капсула, что и у бейджа «Сегодня очищено»:
      // однотонная поверхность с винным подтоном, без красного ореола.
      decoration = BloodSpeck.quiet(theme);
    } else {
      bloodFill = true;
      decoration = BloodSpeck.decoration(theme, opacity: 0.55).copyWith(
        // Круглая, а не скруглённая (жалоба «округлее»).
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFE0525C).withValues(alpha: 0.45),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            spreadRadius: -1,
            offset: const Offset(0, 2),
          ),
        ],
      );
    }
    // Значок НЕ меняет цвет при проигрывании: раньше он вспыхивал ярче и
    // вместе с ним «подсвечивался квадрат» капсулы. Теперь единственное,
    // что меняется, — сам значок play ⇄ stop (плавный кросс-фейд).
    final iconColor = dark
        ? const Color(0xFFFF9AA0).withValues(alpha: 0.96)
        : const Color(0xFFF5DBDD);
    final iconIdle = iconColor;
    final iconHot = iconColor;
    return SmoothTooltip(
      message: widget.tooltip,
      preferredAbove: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        // Визуал — 30 px, но зона нажатия — 44 px: три кнопки остаются
        // мелкими, но в них всё ещё легко попасть.
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: PressScale(
              // Быстрая отдача «вдавливания» (150 мс), не «лаг 300 мс».
              pressedScale: 0.90,
              duration: const Duration(milliseconds: 150),
              releaseDuration: const Duration(milliseconds: 220),
              child: SizedBox(
                width: 30,
                height: 30,
                child: DecoratedBox(
                  decoration: decoration,
                  // На светлой теме под винной таблеткой — те же размашистые
                  // пятна, что у бейджа привычки; на тёмной подложка чистая.
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: glowing ? 1.0 : 0.0),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, child) => IconTheme(
                      data: IconThemeData(
                        color: Color.lerp(iconIdle, iconHot, v),
                        size: 16,
                      ),
                      child: child!,
                    ),
                    child: bloodFill
                        ? CustomPaint(
                            painter: const BloodSpeckPainter(opacity: 0.65),
                            child: Center(child: widget.child),
                          )
                        : Center(child: widget.child),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
