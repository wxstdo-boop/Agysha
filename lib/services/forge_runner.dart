import 'dart:async';

import 'package:flutter/foundation.dart';

import 'forge_agent.dart';
import 'forge_chat_store.dart';
import 'forge_service.dart';

/// Ход агента, который переживает закрытие экрана «Кузницы».
///
/// Раньше прогон жил в состоянии экрана: уход из «Кузницы» обрывал его на
/// полуслове, а вернувшись, человек видел только «агент не уложился». Теперь
/// прогон держит отдельный объект: экран лишь подписывается на его шаги и
/// результат. Экран закрыли — прогон идёт дальше, а готовый ответ ложится в
/// историю чата и появится при следующем открытии.
class ForgeRunner extends ChangeNotifier {
  ForgeRunner();

  /// Общий прогон приложения. Экран по умолчанию берёт его.
  static final ForgeRunner instance = ForgeRunner();

  ForgeAgent? _agent;
  bool _running = false;
  String? _provider;
  String? _error;
  final List<ForgeStep> _steps = <ForgeStep>[];
  int _resultSeq = 0;
  ForgeChatMessage? _finished;

  bool get running => _running;
  List<ForgeStep> get steps => List<ForgeStep>.unmodifiable(_steps);
  String? get provider => _provider;
  String? get error => _error;

  /// Растёт с каждым завершённым ходом: экран по нему понимает, что новый
  /// ответ уже можно показать, и не показывает один и тот же дважды.
  int get resultSeq => _resultSeq;

  /// Готовый ответ, который экран ещё не забрал. Живёт здесь, чтобы ответ
  /// не пропал, если экран был закрыт в момент завершения.
  ForgeChatMessage? get finished => _finished;

  void acknowledgeResult() {
    _finished = null;
    _error = null;
  }

  /// Сброс сессии: чистим ветку и шаги. Прогон при этом не обрываем — если
  /// агент работает, пусть закончит, иначе человек потеряет правки.
  void reset() {
    _agent = null;
    _error = null;
    _provider = null;
    _finished = null;
    _steps.clear();
    notifyListeners();
  }

  /// Запуск хода. Повторный вызов во время работы игнорируется: два агента
  /// в одной ветке затрут друг друга.
  Future<void> start({
    required ForgeService service,
    required ForgeChat chat,
    required String owner,
    required String repo,
    required String baseBranch,
    required List<ForgeChatMessage> history,
    required String task,
    required String languageCode,
    String providerNote = '',
  }) async {
    if (_running) return;
    _running = true;
    _error = null;
    _provider = null;
    _finished = null;
    _steps.clear();
    notifyListeners();

    final agent =
        _agent ??= ForgeAgent(
          service: service,
          chat: chat,
          owner: owner,
          repo: repo,
          baseBranch: baseBranch,
        );

    try {
      var providerLogged = false;
      final turn = await agent.respond(
        history: history,
        task: task,
        baseBranch: baseBranch,
        languageCode: languageCode,
        onProvider: (name) {
          if (providerLogged) return;
          providerLogged = true;
          _provider = name;
          if (providerNote.isNotEmpty) {
            _steps.add(ForgeStep(tool: name, detail: providerNote));
          }
          notifyListeners();
        },
        onStep: (step) {
          _steps.add(step);
          notifyListeners();
        },
      );
      final message = ForgeChatMessage(
        isUser: false,
        text: turn.text.trim().isEmpty ? 'Готово' : turn.text,
        steps: turn.steps,
        pullRequestUrl: turn.pullRequestUrl,
        branch: turn.branch,
        ts: DateTime.now().millisecondsSinceEpoch,
      );
      // В хранилище пишем, не задерживая ход: экран всё равно покажет ответ,
      // а если хранилище недоступно, ждать его незачем.
      unawaited(_persist(message));
      _finished = message;
      _resultSeq++;
    } on ForgeException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  /// Ответ дописывается в хранилище сразу: если приложение убьют до
  /// следующего открытия экрана, разговор всё равно не потеряется.
  Future<void> _persist(ForgeChatMessage message) async {
    try {
      final saved = await ForgeChatStore.load();
      final all = <ForgeChatMessage>[...saved, message];
      final overflow = all.length - ForgeChatStore.maxMessages;
      if (overflow > 0) all.removeRange(0, overflow);
      await ForgeChatStore.save(all);
    } catch (_) {
      // Хранилище недоступно — ответ всё равно покажем на экране.
    }
  }
}
