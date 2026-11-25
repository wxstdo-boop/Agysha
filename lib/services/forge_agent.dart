import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'forge_service.dart';

/// Вызов инструмента, который вернула модель.
class ForgeToolCall {
  const ForgeToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.argumentsBroken = false,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  /// Аргументы пришли обрезанным/битым JSON. Молча считать, что их нет,
  /// нельзя: модель видела «write_file без content» и бросала правку,
  /// хотя на самом деле не разобрались её же аргументы.
  final bool argumentsBroken;
}

/// Ответ модели: либо текст, либо список вызовов инструментов.
class ForgeChatReply {
  const ForgeChatReply({this.text, this.toolCalls = const []});

  final String? text;
  final List<ForgeToolCall> toolCalls;
}

/// Диалог с моделью. Вынесен за интерфейс, чтобы цикл агента можно было
/// прогнать детерминированно: настоящая модель — внешний нестабильный
/// сервис, и проверять на ней логику цикла нельзя.
abstract class ForgeChat {
  Future<ForgeChatReply> complete(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  );

  /// Реальная модель, ответившая последней (шлюзы отдают её в поле
  /// `model`). null — провайдер не сказал, тогда подпись не показываем.
  String? get lastModel => null;
}

/// Шаг работы агента — для живого лога в экране.
class ForgeStep {
  const ForgeStep({required this.tool, required this.detail, this.ok = true});

  final String tool;
  final String detail;
  final bool ok;
}

class ForgeRunResult {
  const ForgeRunResult({
    required this.branch,
    required this.summary,
    this.pullRequestUrl,
    this.filesChanged = 0,
  });

  final String branch;
  final String summary;
  final String? pullRequestUrl;
  final int filesChanged;
}

/// Реплика в чате «Кузницы». Хранит не только текст, но и шаги агента с
/// ссылкой на PR — по ним видно, что именно он сделал в проекте.
class ForgeChatMessage {
  const ForgeChatMessage({
    required this.isUser,
    required this.text,
    this.steps = const [],
    this.pullRequestUrl,
    this.branch,
    this.ts,
    this.model,
  });

  final bool isUser;
  final String text;
  final List<ForgeStep> steps;
  final String? pullRequestUrl;
  final String? branch;
  final int? ts;

  /// Модель, которая ответила этой репликой: «Poolside · laguna-s-2.1».
  /// Подписывается под ответом, чтобы было видно, кто именно отвечал.
  final String? model;

  Map<String, dynamic> toJson() => {
    'isUser': isUser,
    'text': text,
    'ts': ts,
    'branch': branch,
    'pullRequestUrl': pullRequestUrl,
    'model': model,
    'steps': [
      for (final step in steps)
        {'tool': step.tool, 'detail': step.detail, 'ok': step.ok},
    ],
  };

  factory ForgeChatMessage.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'];
    return ForgeChatMessage(
      isUser: json['isUser'] == true,
      text: json['text'] as String? ?? '',
      ts: (json['ts'] as num?)?.toInt(),
      branch: json['branch'] as String?,
      pullRequestUrl: json['pullRequestUrl'] as String?,
      model: json['model'] as String?,
      steps: rawSteps is List
          ? [
              for (final item in rawSteps)
                if (item is Map)
                  ForgeStep(
                    tool: item['tool'] as String? ?? '',
                    detail: item['detail'] as String? ?? '',
                    ok: item['ok'] != false,
                  ),
            ]
          : const [],
    );
  }
}

/// Итог одного хода диалога: ответ модели плюс след в проекте.
class ForgeTurnResult {
  const ForgeTurnResult({
    required this.text,
    this.branch,
    this.pullRequestUrl,
    this.filesChanged = 0,
    this.steps = const [],
  });

  final String text;
  final String? branch;
  final String? pullRequestUrl;
  final int filesChanged;
  final List<ForgeStep> steps;

  bool get madeChanges => filesChanged > 0;
}

/// ИИ-агент «Кузницы»: правит репозиторий настоящими коммитами.
///
/// Работает в отдельной ветке от базовой и открывает pull request — прямая
/// запись в `main` с телефона слишком легко ломает рабочее приложение, а PR
/// даёт возможность посмотреть diff и откатить.
class ForgeAgent {
  ForgeAgent({
    required this.service,
    required this.chat,
    required this.owner,
    required this.repo,
    this.baseBranch = 'main',
  });

  final ForgeService service;
  final ForgeChat chat;
  final String owner;
  final String repo;

  /// Ветка, от которой агент отвечает. Обычно основная.
  final String baseBranch;

  /// Рабочая ветка текущего диалога. Создаётся ЛЕНИВО — при первой правке,
  /// а не при первом вопросе: на вопрос «как устроен этот файл» ветка и PR
  /// не нужны, и создавать их было бы мусором в репозитории.
  String? _branch;

  /// Кнопка «Стоп» в «Кузнице»: ход обрывается не ожиданием сети, а сразу —
  /// незавершённый запрос к модели просто перестаёт нас интересовать, а уже
  /// сделанные правки всё равно доводятся до PR в [_conclude].
  bool _cancelled = false;
  Completer<void>? _cancelSignal;

  /// Просьба остановиться. Можно звать из UI в любой момент.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final signal = _cancelSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  /// Потолок шагов: каждая итерация — это сетевой запрос к модели и к
  /// GitHub. Три тысячи — по-настоящему большой запас: агент может читать
  /// десятки файлов, смотреть прогоны Actions и править проект, пока не
  /// закончит. Упор в потолок всё равно НЕ роняет ход: накопленное
  /// отдаётся как результат, иначе человек видел «агент не уложился в
  /// N шагов» вместо уже сделанных правок.
  static const maxSteps = 3000;

  /// Сколько символов истории диалога уходит в запрос — около 50 тысяч
  /// токенов. Всё, что не влезло, сжимается до короткого конспекта (см.
  /// [_historyForPrompt]), а не пропадает молча.
  static const historyBudget = 200000;

  /// Сколько строк файла отдаём за одно чтение: больше — модель тонет.
  static const maxReadLines = 700;

  /// Сколько файлов агент может изменить за один прогон. Ограничение ловит
  /// разбушевавшуюся модель до того, как она перепишет весь проект. Упор
  /// возвращается модели как ошибка инструмента — чтобы она успела вызвать
  /// finish, а не падала всей сессией. Шестьдесят — под стать трём тысячам
  /// шагов: большой рефакторинг больше не упирается в потолок на середине.
  static const maxWrites = 60;

  /// Пути, которые агенту закрыты: секреты подписи и локальные настройки.
  /// Токен GitHub лежит в защищённом хранилище, но подписной ключ и пароли
  /// в репозитории — прямая утечка, а `.env`/`key.properties` в истории
  /// и так уже были проблемой.
  static bool isBlockedPath(String path) {
    final p = path.toLowerCase().replaceAll('\\', '/');
    if (p.contains('..')) return true;
    if (p.startsWith('/')) return true;
    const blocked = [
      'key.properties',
      '.jks',
      '.keystore',
      '.env',
      'id_rsa',
      '.p12',
      '.pem',
    ];
    return blocked.any(p.contains);
  }

  List<Map<String, dynamic>> _tools() => [
    // write_file идёт ПЕРВЫМ: правка файла — основная работа агента, и
    // когда он последний в списке, модель чаще отвечала прозой вместо
    // вызова инструмента.
    {
      'type': 'function',
      'function': {
        'name': 'write_file',
        'description':
            'Записать файл в рабочую ветку. В content передай содержимое '
            'так, как тебе удобнее: полный файл или участок с правкой.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'Путь файла.'},
            'content': {
              'type': 'string',
              'description': 'Содержимое файла или правка к нему.',
            },
            'message': {
              'type': 'string',
              'description': 'Короткое сообщение коммита.',
            },
          },
          'required': ['path', 'content'],
        },
      },
    },
    // Правка участка файла — второй способ записи и первый, которым модель
    // реально пользуется: целый файл она часто не осиливает (обрывает
    // content, путает отступы, присылает дифф), а «замени этот кусок на
    // этот» даётся ей легко. Именно из-за этого «агент не может
    // редактировать файл».
    {
      'type': 'function',
      'function': {
        'name': 'edit_file',
        'description':
            'Заменить участок файла в рабочей ветке. old_string — точный '
            'кусок из read_file (вместе с отступами), new_string — чем его '
            'заменить. Кусок должен встречаться в файле ровно один раз.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'Путь файла.'},
            'old_string': {
              'type': 'string',
              'description': 'Точный существующий фрагмент файла.',
            },
            'new_string': {
              'type': 'string',
              'description': 'Чем заменить фрагмент. Пусто — удалить его.',
            },
            'message': {
              'type': 'string',
              'description': 'Короткое сообщение коммита.',
            },
          },
          'required': ['path', 'old_string', 'new_string'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'list_dir',
        'description': 'Показать файлы и папки каталога в репозитории.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description':
                  'Путь каталога, например lib/screens. Пусто — корень.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'search_code',
        'description':
            'Найти файлы по тексту или имени. Быстрее, чем обходить каталоги.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Что искать, например class ForgeAgent.',
            },
          },
          'required': ['query'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_file',
        'description':
            'Прочитать файл из репозитория. Для больших файлов читай '
            'по частям: start/end — номера строк (с 1).',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'Путь файла.'},
            'start': {
              'type': 'integer',
              'description': 'Первая строка диапазона, с 1. Пусто — с начала.',
            },
            'end': {
              'type': 'integer',
              'description': 'Последняя строка диапазона включительно.',
            },
          },
          'required': ['path'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'delete_file',
        'description': 'Удалить файл в рабочей ветке.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'Путь файла.'},
            'message': {
              'type': 'string',
              'description': 'Короткое сообщение коммита.',
            },
          },
          'required': ['path'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'workflow_runs',
        'description':
            'Последние прогоны GitHub Actions: статус, ветка, ссылка. '
            'Смотри их, если сборка или релиз красные.',
        'parameters': {
          'type': 'object',
          'properties': {
            'branch': {
              'type': 'string',
              'description': 'Только прогоны этой ветки. Пусто — все.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'run_jobs',
        'description':
            'Задания и упавшие шаги конкретного прогона Actions (id из workflow_runs).',
        'parameters': {
          'type': 'object',
          'properties': {
            'run_id': {
              'type': 'integer',
              'description': 'id прогона, например 45356405768.',
            },
          },
          'required': ['run_id'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'check_annotations',
        'description':
            'Проверки коммита и текст их ошибок: почему красный CI/линтер.',
        'parameters': {
          'type': 'object',
          'properties': {
            'ref': {
              'type': 'string',
              'description': 'SHA, ветка или тег. Пусто — рабочая ветка.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'pull_requests',
        'description': 'Открытые pull request\'ы репозитория.',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'recent_commits',
        'description': 'Последние коммиты ветки — что уже влито и собрано.',
        'parameters': {
          'type': 'object',
          'properties': {
            'ref': {
              'type': 'string',
              'description': 'Ветка. Пусто — рабочая ветка.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'finish',
        'description':
            'Закончить работу и открыть pull request. Вызывай, когда правки готовы.',
        'parameters': {
          'type': 'object',
          'properties': {
            'summary': {
              'type': 'string',
              'description': 'Что сделано — 1-3 предложения для описания PR.',
            },
            'title': {
              'type': 'string',
              'description': 'Заголовок pull request.',
            },
          },
          'required': ['summary'],
        },
      },
    },
  ];

  /// Один ход диалога: ответ на реплику и, если попросили, правки проекта.
  ///
  /// Работает как настоящий чат: `history` — предыдущие реплики, `task` —
  /// новая. Модель может просто ответить текстом (тогда ветка и PR не
  /// создаются), а может править файлы — тогда агент заводит рабочую ветку,
  /// коммитит и открывает pull request.
  Future<ForgeTurnResult> respond({
    required List<ForgeChatMessage> history,
    required String task,
    String baseBranch = 'main',
    String languageCode = 'ru',
    void Function(ForgeStep step)? onStep,
    void Function(String provider)? onProvider,
  }) async {
    _cancelled = false;
    final signal = _cancelSignal = Completer<void>();
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt(languageCode)},
      ..._historyForPrompt(history),
      {'role': 'user', 'content': task},
    ];
    final tools = _tools();
    final steps = <ForgeStep>[];
    var writes = 0;
    // Правки хода: записанные и удалённые файлы. Удаление — такая же правка,
    // как запись: без него PR не открывался бы на чистом удалении.
    final written = <String>{};
    final deleted = <String>{};
    String? lastText;
    // Один «толчок» за ход: модель иногда отвечает планом вместо правки.
    // Без него задача «сделай» заканчивалась красивым текстом и без коммита.
    var nudged = false;

    try {
      for (var step = 0; step < maxSteps; step++) {
        if (_cancelled) {
          return await _stopped(
            branch: _branch,
            base: baseBranch,
            task: task,
            text: lastText,
            files: _netChanged(written, deleted),
            steps: steps,
          );
        }
        final reply = await _race(chat.complete(messages, tools), signal);
        if (reply.text != null && reply.text!.trim().isNotEmpty) {
          lastText = reply.text;
        }

        if (reply.toolCalls.isEmpty) {
          // Модель ответила планом на задачу «сделай» и не тронула ни одного
          // файла. Один раз просим довести дело до конца, а не обещать.
          if (!nudged &&
              steps.isEmpty &&
              written.isEmpty &&
              deleted.isEmpty &&
              wantsAction(task)) {
            nudged = true;
            messages.add({'role': 'assistant', 'content': reply.text ?? ''});
            messages.add({
              'role': 'user',
              'content':
                  'Ты ответил словами, но ничего не изменил, а задача — '
                  'сделать. Продолжай: найди файлы, правь их через '
                  'edit_file/write_file и закончи вызовом finish. Если это '
                  'и правда только вопрос — ответь коротко, без планов.',
            });
            continue;
          }
          // Модель ответила текстом. Без правок это обычный ответ в чате —
          // никаких веток и PR. С правками — доводим работу до PR.
          return await _conclude(
            branch: _branch,
            base: baseBranch,
            task: task,
            text: reply.text ?? lastText ?? '',
            files: _netChanged(written, deleted),
            steps: steps,
          );
        }

        messages.add({
          'role': 'assistant',
          'content': reply.text,
          'tool_calls': [
            for (final call in reply.toolCalls)
              {
                'id': call.id,
                'type': 'function',
                'function': {
                  'name': call.name,
                  'arguments': jsonEncode(call.arguments),
                },
              },
          ],
        });

        for (final call in reply.toolCalls) {
          if (_cancelled) {
            return await _stopped(
              branch: _branch,
              base: baseBranch,
              task: task,
              text: lastText,
              files: _netChanged(written, deleted),
              steps: steps,
            );
          }
          if (call.name == 'finish') {
            final summary = _str(call.arguments['summary']) ?? lastText ?? '';
            return await _conclude(
              branch: _branch,
              base: baseBranch,
              task: task,
              text: summary.isEmpty ? (lastText ?? 'Готово') : summary,
              title: _str(call.arguments['title']),
              files: _netChanged(written, deleted),
              steps: steps,
            );
          }

          String result;
          var ok = true;
          // Предохранитель, а не подсказка модели: если она упорно пишет
          // сверх лимита, прогон останавливаем — иначе один запуск может
          // переписать весь проект.
          if (_isWrite(call.name) && writes >= maxWrites) {
            ok = false;
            result =
                'Ошибка: предел правок ($maxWrites файлов) за один ход. '
                'Дальше только читай или вызывай finish.';
            steps.add(
              ForgeStep(
                tool: call.name,
                detail: _str(call.arguments['path']) ?? result,
                ok: false,
              ),
            );
            onStep?.call(steps.last);
            messages.add({
              'role': 'tool',
              'tool_call_id': call.id,
              'content': result,
            });
            continue;
          }
          try {
            if (call.argumentsBroken) {
              throw ForgeException(
                400,
                'аргументы ${call.name} не разобрались (JSON обрезан или '
                'невалиден). Повтори вызов короткими аргументами: для '
                'write_file — ПОЛНЫЙ файл, один файл за шаг.',
              );
            }
            // Ветку заводим ТОЛЬКО под правку. Вопрос по коду читает базовую
            // ветку и не оставляет после себя ни ветки, ни PR.
            final branch = _isWrite(call.name)
                ? await _ensureBranch(task, baseBranch)
                : (_branch ?? baseBranch);
            result = await _execute(call, branch);
            // Перезапись тем же содержимым — не правка: иначе шаг и коммит
            // тратятся впустую, а ветка не меняется.
            if (_isWrite(call.name) && !result.startsWith('Без изменений:')) {
              writes++;
              final p = _str(call.arguments['path']);
              if (p != null) {
                if (call.name == 'delete_file') {
                  deleted.add(p);
                } else {
                  written.add(p);
                }
              }
            }
          } on ForgeException catch (e) {
            ok = false;
            result = 'Ошибка: ${e.message}';
          } catch (e) {
            // Любой неожиданный сбой (сеть, формат, лимит) раньше вылетал из
            // цикла и обрывал весь прогон — снаружи это выглядело как «ИИ не
            // может писать файлы». Теперь сбой одного инструмента остаётся
            // шагом с ошибкой, и модель продолжает работу.
            ok = false;
            result =
                'Ошибка инструмента ${call.name}: '
                '${e.toString().replaceFirst('Exception: ', '')}. '
                'Исправь аргументы и повтори.';
          }
          final step_ = ForgeStep(
            tool: call.name,
            detail: _str(call.arguments['path']) ?? result,
            ok: ok,
          );
          steps.add(step_);
          onStep?.call(step_);
          messages.add({
            'role': 'tool',
            'tool_call_id': call.id,
            'content': result,
          });
        }
      }
    } on _ForgeCancelled {
      return await _stopped(
        branch: _branch,
        base: baseBranch,
        task: task,
        text: lastText,
        files: _netChanged(written, deleted),
        steps: steps,
      );
    } finally {
      if (identical(_cancelSignal, signal)) _cancelSignal = null;
      _cancelled = false;
    }
    // Шаги кончились. Не роняем ход: правки уже в ветке, и человеку нужен
    // PR с тем, что успели сделать, а не сообщение про «N шагов».
    final note = (lastText ?? '').trim();
    return _conclude(
      branch: _branch,
      base: baseBranch,
      task: task,
      text: note.isEmpty
          ? 'Остановился на пределе шагов: правки ниже уже в ветке.'
          : '$note\n\n(Остановился на пределе шагов: правки ниже уже в ветке.)',
      files: _netChanged(written, deleted),
      steps: steps,
    );
  }

  /// Ждём ответ модели, но не дольше, чем длится ход: нажатие «Стоп»
  /// обрывает ожидание сразу, не дожидаясь таймаута сети.
  static Future<T> _race<T>(Future<T> work, Completer<void> signal) {
    if (signal.isCompleted) return Future<T>.error(const _ForgeCancelled());
    final stop = signal.future.then<T>((_) => throw const _ForgeCancelled());
    return Future.any<T>(<Future<T>>[work, stop]);
  }

  /// Остановленный ход. Правки, которые уже успели лечь в ветку, всё равно
  /// доводим до PR — иначе «Стоп» стирал бы сделанное.
  Future<ForgeTurnResult> _stopped({
    required String? branch,
    required String base,
    required String task,
    required String? text,
    required Set<String> files,
    required List<ForgeStep> steps,
  }) {
    final note = (text ?? '').trim();
    final text2 = note.isEmpty
        ? 'Остановлено по твоей команде.'
        : '$note\n\n(Остановлено по твоей команде.)';
    return _conclude(
      branch: branch,
      base: base,
      task: task,
      text: text2,
      files: files,
      steps: steps,
    );
  }

  /// Прогон одиночной задачи (совместимость и «сделай и открой PR»).
  /// Без правок — ошибка: этот вход просили именно изменить проект.
  Future<ForgeRunResult> run({
    required String task,
    required String baseBranch,
    String languageCode = 'ru',
    void Function(ForgeStep step)? onStep,
    void Function(String provider)? onProvider,
  }) async {
    final turn = await respond(
      history: const [],
      task: task,
      baseBranch: baseBranch,
      languageCode: languageCode,
      onStep: onStep,
      onProvider: onProvider,
    );
    if (!turn.madeChanges) {
      throw ForgeException(
        500,
        turn.text.isEmpty ? 'Агент ничего не изменил' : turn.text,
      );
    }
    return ForgeRunResult(
      branch: turn.branch ?? '',
      summary: turn.text,
      pullRequestUrl: turn.pullRequestUrl,
      filesChanged: turn.filesChanged,
    );
  }

  static bool _isWrite(String tool) =>
      tool == 'write_file' || tool == 'edit_file' || tool == 'delete_file';

  /// Итоговый набор изменённых файлов. Файл, записанный и затем удалённый в
  /// одном ходе, к результату не относится — его из набора убираем.
  static Set<String> _netChanged(Set<String> written, Set<String> deleted) => {
    ...written.difference(deleted),
    ...deleted.difference(written),
  };

  /// Рабочая ветка диалога: создаётся при первой правке и дальше живёт до
  /// конца сессии — так правки одного диалога ложатся в один PR.
  Future<String> _ensureBranch(String task, String base) async {
    final existing = _branch;
    if (existing != null) return existing;
    final name =
        'forge/${_slug(task)}-${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    await service.createBranch(owner, repo, name: name, from: base);
    _branch = name;
    return name;
  }

  /// Завершение хода: с правками — PR, без правок — просто ответ в чате.
  Future<ForgeTurnResult> _conclude({
    required String? branch,
    required String base,
    required String task,
    required String text,
    required Set<String> files,
    required List<ForgeStep> steps,
    String? title,
  }) async {
    if (files.isEmpty || branch == null) {
      return ForgeTurnResult(text: text, steps: steps);
    }
    final url = await service.openPullRequest(
      owner,
      repo,
      title: title ?? _prTitle(task),
      body:
          '$text\n\n'
          '---\n'
          'Задача: $task\n\n'
          'Изменённые файлы: ${files.join(', ')}\n\n'
          '_Изменения внесены ИИ-агентом «Кузница» из приложения Agysha._',
      head: branch,
      base: base,
    );
    return ForgeTurnResult(
      text: text,
      branch: branch,
      pullRequestUrl: url.isEmpty ? null : url,
      filesChanged: files.length,
      steps: steps,
    );
  }

  Future<String> _execute(ForgeToolCall call, String branch) async {
    switch (call.name) {
      case 'list_dir':
        final path = _str(call.arguments['path']) ?? '';
        final entries = await service.listDirectory(
          owner,
          repo,
          path,
          ref: branch,
        );
        if (entries.isEmpty) return 'Каталог пуст или не найден';
        return entries.map((e) => e.isDir ? '${e.path}/' : e.path).join('\n');
      case 'search_code':
        final query = _str(call.arguments['query'])?.trim() ?? '';
        if (query.isEmpty) {
          throw ForgeException(400, 'search_code без query');
        }
        final hits = await service.searchCode(owner, repo, query);
        if (hits.isEmpty) return 'Ничего не найдено по запросу: $query';
        return hits.join('\n');
      case 'read_file':
        final path = _requirePath(call);
        final file = await service.readFile(owner, repo, path, ref: branch);
        if (file == null) return 'Файл не найден: $path';
        final lines = file.content.split('\n');
        final requestedStart = (_int(call.arguments['start']) ?? 1).clamp(
          1,
          lines.isEmpty ? 1 : lines.length,
        );
        final requestedEnd = (_int(call.arguments['end']) ?? lines.length)
            .clamp(requestedStart, lines.length);
        var end = requestedEnd;
        final capped = end - requestedStart + 1 > maxReadLines;
        if (capped) end = requestedStart + maxReadLines - 1;
        final slice = lines.sublist(requestedStart - 1, end);
        final header = 'Строки $requestedStart-$end из ${lines.length}\n';
        final tail = capped
            ? '\n\n[Обрезано на $maxReadLines строках. Продолжи с '
                  'start=$end + 1.]'
            : '';
        return '$header${slice.join('\n')}$tail';
      case 'edit_file':
        final path = _requirePath(call);
        final from = _textOf(call.arguments['old_string']);
        final to = _textOf(call.arguments['new_string']);
        if (from == null || from.isEmpty) {
          throw ForgeException(
            400,
            'edit_file без old_string (передай точный кусок файла из '
            'read_file, вместе с отступами).',
          );
        }
        if (to == null) {
          throw ForgeException(
            400,
            'edit_file без new_string (пустая строка — значит удалить кусок).',
          );
        }
        final current = await service.readFile(owner, repo, path, ref: branch);
        if (current == null) {
          throw ForgeException(
            404,
            'edit_file: файла $path нет в ветке. Сначала list_dir/read_file.',
          );
        }
        final hits = from.allMatches(current.content).length;
        if (hits == 0) {
          throw ForgeException(
            400,
            'edit_file: old_string не найден в $path. Скопируй фрагмент '
            'дословно из read_file — с отступами и без «...».',
          );
        }
        if (hits > 1) {
          throw ForgeException(
            400,
            'edit_file: old_string встречается $hits раз. Добавь соседние '
            'строки, чтобы фрагмент стал уникальным.',
          );
        }
        final patched = current.content.replaceFirst(from, to);
        if (patched.trim().isEmpty) {
          throw ForgeException(
            400,
            'edit_file сделал бы файл пустым — так нельзя. Для удаления '
            'файла есть delete_file.',
          );
        }
        await service.writeFile(
          owner,
          repo,
          path,
          content: patched,
          message: _str(call.arguments['message']) ?? 'Кузница: правка $path',
          branch: branch,
          sha: current.sha,
        );
        return 'Записано: $path (заменён фрагмент)';
      case 'write_file':
        final path = _requirePath(call);
        final raw =
            _textOf(call.arguments['content']) ??
            _textOf(call.arguments['file_content']) ??
            _textOf(call.arguments['new_content']) ??
            _textOf(call.arguments['contents']) ??
            _textOf(call.arguments['body']) ??
            _textOf(call.arguments['data']) ??
            _textOf(call.arguments['code']) ??
            _textOf(call.arguments['text']);
        if (raw == null) {
          throw ForgeException(
            400,
            'write_file без content (передай полное содержимое файла в поле '
            'content). Пришли ключи: ${call.arguments.keys.join(', ')}',
          );
        }
        final content = _normalizeFileContent(raw);
        if (content.trim().isEmpty) {
          throw ForgeException(400, 'write_file с пустым content');
        }
        // Модель иногда присылает не файл целиком, а кусок диффа: запись
        // такого содержимого молча ломала файл в ветке. Отправляем ошибку
        // обратно в диалог — модель переписывает файл целиком.
        if (_looksLikePatch(content)) {
          throw ForgeException(
            400,
            'content не полный файл, а фрагмент/дифф. Пришли ПОЛНОЕ новое '
            'содержимое файла целиком.',
          );
        }
        final existing = await service.readFile(owner, repo, path, ref: branch);
        if (existing != null && existing.content.trim() == content.trim()) {
          // Модель иногда переписывает файл «тем же» содержимым: коммит
          // пустой, шаг съедает бюджет, а ветка не меняется.
          return 'Без изменений: $path уже содержит это. Не переписывай его.';
        }
        // Обрезанная запись — главная причина «агент сломал проект»: модель
        // присылала только отредактированный хвост, и файл терял тело.
        // Такую запись не пускаем, а возвращаем модель в русло edit_file.
        if (existing != null &&
            call.arguments['allow_shrink'] != true &&
            existing.content.length > 400 &&
            content.length * 3 < existing.content.length) {
          throw ForgeException(
            400,
            'content короче файла $path более чем втрое '
            '(${content.length} против ${existing.content.length} символов) — '
            'похоже, пришла только часть файла. Правь точечно через '
            'edit_file, а для полной замены пришли весь файл целиком '
            '(allow_shrink: true — только если файл правда так сократился).',
          );
        }
        await service.writeFile(
          owner,
          repo,
          path,
          content: content,
          message: _str(call.arguments['message']) ?? 'Кузница: правка $path',
          branch: branch,
          sha: existing?.sha,
        );
        return 'Записано: $path';
      case 'workflow_runs':
        final branch = _str(call.arguments['branch']);
        final runs = await service.workflowRuns(owner, repo, branch: branch);
        if (runs.isEmpty) return 'Прогонов Actions не найдено';
        return runs.join('\n');
      case 'run_jobs':
        final id = _int(call.arguments['run_id']);
        if (id == null) throw ForgeException(400, 'run_jobs без run_id');
        final jobs = await service.runJobs(owner, repo, id);
        if (jobs.isEmpty) return 'Заданий у прогона $id нет';
        return jobs.join('\n');
      case 'check_annotations':
        final ref = _str(call.arguments['ref'])?.trim().isNotEmpty == true
            ? _str(call.arguments['ref'])!.trim()
            : (branch);
        final checks = await service.checkAnnotations(owner, repo, ref);
        if (checks.isEmpty) {
          return 'Проверок с ошибками нет (или у токена нет доступа к checks)';
        }
        return checks.join('\n');
      case 'pull_requests':
        final prs = await service.pullRequests(owner, repo);
        if (prs.isEmpty) return 'Открытых pull request нет';
        return prs.join('\n');
      case 'recent_commits':
        final ref = _str(call.arguments['ref'])?.trim().isNotEmpty == true
            ? _str(call.arguments['ref'])!.trim()
            : branch;
        final commits = await service.recentCommits(owner, repo, ref: ref);
        if (commits.isEmpty) return 'Коммитов не видно';
        return commits.join('\n');
      case 'delete_file':
        final path = _requirePath(call);
        await service.deleteFile(
          owner,
          repo,
          path,
          message: _str(call.arguments['message']) ?? 'Кузница: удаление $path',
          branch: branch,
        );
        return 'Удалено: $path';
      default:
        return 'Неизвестный инструмент: ${call.name}';
    }
  }

  /// Признаки того, что `content` — не файл, а кусок патча или обрезок
  /// (модели любят присылать `diff --git`, маркеры конфликта или заголовок
  /// ханка). Такой текст в репозиторий писать нельзя.
  static bool _looksLikePatch(String content) {
    final head = content.trimLeft();
    if (head.startsWith('diff --git') ||
        head.startsWith('--- a/') ||
        head.startsWith('+++ b/') ||
        head.startsWith('@@')) {
      return true;
    }
    return content.contains('<<<<<<< ') || content.contains('>>>>>>> ');
  }

  /// История для запроса: последние реплики в пределах [historyBudget] плюс
  /// первая просьба человека — она задаёт рамку всей работы.
  ///
  /// Середина, которая уже не влезает, не пропадает молча: она СЖИМАЕТСЯ в
  /// короткий конспект (кто что просил и чем это закончилось). Так модель
  /// помнит ход работы даже на длинном диалоге, а окно не переполняется.
  List<Map<String, dynamic>> _historyForPrompt(List<ForgeChatMessage> history) {
    final usable = history
        .where((m) => m.text.trim().isNotEmpty)
        .toList(growable: false);
    if (usable.isEmpty) return const [];
    final tail = <ForgeChatMessage>[];
    var used = 0;
    for (var i = usable.length - 1; i >= 0; i--) {
      final len = usable[i].text.length;
      if (tail.isNotEmpty && used + len > historyBudget) break;
      tail.add(usable[i]);
      used += len;
    }
    final start = usable.length - tail.length;
    final result = <Map<String, dynamic>>[];
    if (start > 1) {
      result.add({'role': 'user', 'content': usable.first.text});
      result.add({
        'role': 'system',
        'content': _compact(usable.sublist(1, start)),
      });
    }
    for (final m in tail.reversed) {
      result.add({'role': m.isUser ? 'user' : 'assistant', 'content': m.text});
    }
    return result;
  }

  /// Конспект выпавшей середины диалога: по строке на реплику, просьбы
  /// людей — подробнее, ответы агента — одной фразой. Ограничен по длине,
  /// чтобы сам конспект не съел контекст.
  static String _compact(List<ForgeChatMessage> dropped) {
    const maxLine = 120;
    const maxChars = 3000;
    const maxLines = 40;
    final lines = <String>[];
    var chars = 0;
    // Берём реплики с конца: свежая часть важнее самых старых просьб.
    for (var i = dropped.length - 1; i >= 0 && lines.length < maxLines; i--) {
      final m = dropped[i];
      final flat = m.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (flat.isEmpty) continue;
      final cut = flat.length <= maxLine
          ? flat
          : '${flat.substring(0, maxLine)}…';
      final line = m.isUser ? '— просьба: $cut' : '— ответ: $cut';
      if (chars + line.length > maxChars) break;
      lines.add(line);
      chars += line.length;
    }
    final digest = lines.reversed.join('\n');
    return 'Середина диалога (${dropped.length} реплик) сжата в конспект, '
        'чтобы уложиться в контекст. Ниже — суть, в обратном порядке '
        'свежести:\n$digest\n'
        'Не выдумывай детали, которых нет в конспекте, в первой просьбе и '
        'в последних репликах; факты о коде бери из файлов ветки.';
  }

  static int? _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  String _requirePath(ForgeToolCall call) {
    final path =
        _str(call.arguments['path']) ??
        _str(call.arguments['file_path']) ??
        _str(call.arguments['filepath']) ??
        _str(call.arguments['filename']) ??
        _str(call.arguments['file']);
    if (path == null || path.trim().isEmpty) {
      throw ForgeException(400, 'Не указан path');
    }
    final clean = _cleanRepoPath(path);
    if (isBlockedPath(clean)) {
      throw ForgeException(403, 'Путь закрыт для агента: $clean');
    }
    return clean;
  }

  /// Путь из ответа модели приводят к виду, который понимает GitHub API:
  /// без `./`, ведущего слеша, без префиксов `a/`/`b/` из диффа и без
  /// «owner/repo/» — иначе write_file всегда отвечал 404.
  String _cleanRepoPath(String path) {
    var p = path.trim().replaceAll('\\', '/');
    while (p.startsWith('./')) {
      p = p.substring(2);
    }
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    if (p.startsWith('a/') || p.startsWith('b/')) p = p.substring(2);
    final prefix = '$owner/$repo/';
    if (p.startsWith(prefix)) p = p.substring(prefix.length);
    return p;
  }

  String _systemPrompt(String languageCode) =>
      'Ты — «Кузница», ИИ-агент-программист внутри приложения Agysha '
      '(Flutter/Dart, репозиторий $owner/$repo). Ты ведёшь ЖИВОЙ ДИАЛОГ с '
      'разработчиком и по его просьбе правишь код настоящими коммитами в '
      'отдельной ветке, затем открываешь pull request.\n'
      'Порядок работы над любой задачей:\n'
      '0) Если человек просит СДЕЛАТЬ (поправить, добавить, исправить, '
      'починить) — делай сразу: читай файлы, правь, finish. Не отвечай '
      'планом, не спрашивай «продолжить?», не проси подтверждения и не '
      'пересказывай, что собираешься сделать. Уточняющий вопрос — только '
      'когда без него правка станет угадыванием.\n'
      '1) Пойми, что просят, с учётом всего диалога и уже сделанного. Если '
      'просьба допускает разные трактовки — задай ОДИН короткий уточняющий '
      'вопрос текстом, не правя файлы наугад.\n'
      '2) Различай вопрос и задачу. Вопрос («как устроено», «почему '
      'падает», «где лежит», «что думаешь») — это ответ ТЕКСТОМ: найди '
      'нужное и объясни, ничего не правя и не вызывая finish. Задача '
      '(«сделай», «поправь», «добавь», «убери») — это правки. Если просьба '
      'звучит как вопрос, но по смыслу требует изменений, сперва ответь '
      'коротко и спроси, править ли, — и только по подтверждению правь.\n'
      '3) Найди нужное: search_code и list_dir, затем read_file. Большой '
      'файл читай диапазонами start/end, а не целиком.\n'
      '4) Правь минимально и по делу: одна правка — одна причина. Не '
      'переписывай файл ради стиля и не удаляй чужую работу.\n'
      '5) После правок мысленно пройди по изменённому коду: не сломал ли ты '
      'существующее поведение, имена, тесты и импорты. Если сломал — '
      'исправь тем же ходом.\n'
      '6) Заканчивай вызовом finish с честным summary: что изменено и что '
      'осталось непроверенным.\n'
      'Правила:\n'
      '— На вопрос о коде отвечай текстом, опираясь на реальные файлы: '
      'сначала list_dir/read_file, потом ответ. Для ответа НЕ вызывай '
      'finish и не правь файлы — ветка и PR на вопросы не создаются.\n'
      '— Помни предыдущие реплики диалога и продолжай начатую работу, не '
      'начиная всё заново. Ссылки вроде «этот экран», «эту кнопку», «как в '
      'привычках» разрешай по истории и по коду, а не догадками.\n'
      '— Пути бери ТОЛЬКО из list_dir/read_file. Если файла нет в выдаче — '
      'сначала найди его через search_code, не угадывай путь.\n'
      '— Правишь существующий файл — сначала read_file, потом edit_file с '
      'точным old_string из прочитанного. Один шаг — один файл.\n'
      '— write_file — для НОВЫХ файлов и для полной перезаписи, когда правок '
      'больше половины. content — ПОЛНОЕ содержимое, без «...».\n'
      '— Не присылай диффы, фрагменты и «...» вместо кода. Если файл '
      'большой — правь его по частям отдельными шагами.\n'
      '— Если инструмент вернул ошибку, исправь аргументы и повтори; не '
      'делай вид, что записал.\n'
      '— GitHub Actions, проверки и PR — часть работы, а не «чёрный ящик»: '
      'workflow_runs показывает прогоны, run_jobs — упавшие шаги, '
      'check_annotations — текст ошибок CI, pull_requests и recent_commits — '
      'что уже отправлено и влито. Файлы workflow лежат в .github/workflows '
      'и правятся обычным read_file/write_file, как любой другой код. Если '
      'CI красный — сначала посмотри причину, потом правь.\n'
      '— Предел правок за ход — $maxWrites файлов, шагов — $maxSteps. '
      'Если задача явно больше, сделай главное и вызови finish с честным '
      'summary о том, что осталось: правки уже попадут в PR.\n'
      'Не выдумывай код, которого не видел. Не трогай секреты и файлы '
      'подписи. Держись стиля проекта: комментарии по-русски, без лишних '
      'слов. Пиши по делу и коротко.\n'
      'Отвечай на языке: ${languageCode == 'ru' ? 'русском' : languageCode}.';

  /// Просьба «сделай»: такие задачи нельзя заканчивать планом в прозе.
  /// Список намеренно короткий — «почему», «где», «что думаешь» сюда не
  /// попадают, иначе на обычный вопрос агент начинал бы править файлы.
  static bool wantsAction(String task) {
    final t = task.toLowerCase();
    const verbs = [
      'сделай',
      'сделать',
      'поправь',
      'исправь',
      'почини',
      'добавь',
      'убери',
      'удали',
      'создай',
      'реализуй',
      'переделай',
      'доработай',
      'обнови',
      'замени',
      'внедри',
      'настрой',
      'fix ',
      'add ',
      'implement',
      'refactor',
    ];
    return verbs.any(t.contains);
  }

  String _prTitle(String task) {
    final oneLine = task.replaceAll(RegExp(r'\s+'), ' ').trim();
    final short = oneLine.length <= 60
        ? oneLine
        : '${oneLine.substring(0, 60)}…';
    return 'Кузница: $short';
  }

  static String _slug(String task) {
    final lower = task.toLowerCase();
    final ascii = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
        ascii.write(ch);
      } else if (ascii.isNotEmpty && !ascii.toString().endsWith('-')) {
        ascii.write('-');
      }
      if (ascii.length >= 24) break;
    }
    final slug = ascii.toString().replaceAll(RegExp(r'-+$'), '');
    return slug.isEmpty ? 'task' : slug;
  }

  static String? _str(dynamic value) => value is String ? value : null;

  /// Текст из любого «строкоподобного» значения: модели иногда кладут в
  /// `content` готовый объект/массив (например, JSON конфига) — раньше это
  /// превращалось в «write_file без content».
  static String? _textOf(dynamic value) {
    if (value is String) return value;
    if (value is Map || value is List) return jsonEncode(value);
    if (value is num || value is bool) return value.toString();
    return null;
  }
}

/// Модель, которую можно выбрать в «Кузнице», — ровно из того пула, что
/// реально пробуется. [power] задаёт порядок в таблетке выбора: сверху
/// самые сильные, снизу самые скромные.
class ForgeModelOption {
  const ForgeModelOption({
    required this.id,
    required this.name,
    required this.vendor,
    required this.power,
    this.needsKey = false,
  });

  /// Стабильный ключ для сохранения выбора между запусками.
  final String id;

  /// Короткое имя модели для таблетки.
  final String name;

  /// Площадка, которая её отдаёт.
  final String vendor;

  /// Условная сила: больше — сильнее. По ней таблетка и сортируется.
  final int power;

  /// Нужен свой ключ провайдера: без него модель не показываем.
  final bool needsKey;

  /// Подпись для таблетки. Бесплатные варианты читаются как «Kilo Free»,
  /// а не «Kilo · Free» — так их и просили называть.
  String get label => name == 'Free' ? '$vendor Free' : '$vendor · $name';
}

/// Пул бесплатных OpenAI-совместимых провайдеров — тот же набор, на котором
/// работает Ада в приложении. Ключ не нужен, поэтому «Кузница» работает
/// «из коробки».
///
/// Вызов инструментов проверен вживую на всех трёх: модель возвращает
/// `tool_calls`, понимает результат инструмента и продолжает цикл.
/// Провайдеры перебираются по очереди: бесплатные площадки часто отдают 429,
/// и один упавший не должен останавливать прогон.
class FreePoolForgeChat implements ForgeChat {
  FreePoolForgeChat({
    http.Client? client,
    this.apiKey = '',
    this.onProvider,
    this.onlyModel,
  }) : _client = client ?? http.Client();

  /// Выбранная в таблетке модель: если задана, пул пробует только её, и
  /// лишь при её недоступности откатывается на весь список. Без выбора
  /// работает прежний перебор всего пула.
  final String? onlyModel;

  /// Модели, доступные с таким ключом (или без него), по убыванию силы.
  static List<ForgeModelOption> catalogFor(String apiKey) {
    final key = apiKey.trim();
    return catalogForKeyKind(
      key.isEmpty ? '' : (key.startsWith('sk-or-') ? 'openrouter' : 'other'),
    );
  }

  /// То же, но по виду ключа (`''`, `other`, `openrouter`): вид хранится
  /// в обычных настройках, поэтому таблетка знает про Agnes и Poolside до
  /// того, как прочитан зашифрованный файл с самим ключом.
  static List<ForgeModelOption> catalogForKeyKind(String kind) {
    final hasKey = kind.isNotEmpty;
    final openRouter = kind == 'openrouter';
    final all = <ForgeModelOption>[
      // Свой ключ может быть ключом Agnes — в настройках это одно поле
      // «Ключ провайдера». Сначала Agnes: раньше такой ключ уходил на
      // Poolside, получал отказ, и отвечал бесплатный Kilo — владелец
      // видел «Kilo», хотя платит за Agnes.
      if (hasKey && !openRouter)
        const ForgeModelOption(
          id: 'agnes-3.0-flash',
          name: 'Agnes 3.0 Flash',
          vendor: 'Agnes AI',
          power: 104,
          needsKey: true,
        ),
      if (hasKey && !openRouter)
        const ForgeModelOption(
          id: 'poolside-laguna',
          name: 'Laguna S 2.1',
          vendor: 'Poolside',
          power: 100,
          needsKey: true,
        ),
      if (hasKey && openRouter)
        const ForgeModelOption(
          id: 'openrouter-laguna',
          name: 'Laguna S 2.1 free',
          vendor: 'OpenRouter',
          power: 98,
          needsKey: true,
        ),
      // Kilo в таблетке РОВНО один: «kilo-auto» и «kilo-free» — тот же
      // шлюз и та же бесплатная модель, и две подписи «Kilo» путали выбор.
      const ForgeModelOption(
        id: 'kilo-free',
        name: 'Free',
        vendor: 'Kilo',
        power: 84,
      ),
      const ForgeModelOption(
        id: 'murakumo-free',
        name: 'Free',
        vendor: 'Murakumo',
        power: 62,
      ),
      const ForgeModelOption(
        id: 'ovh-mistral',
        name: 'Mistral Nemo',
        vendor: 'OVHcloud',
        power: 56,
      ),
    ];
    all.sort((a, b) => b.power.compareTo(a.power));
    return List<ForgeModelOption>.unmodifiable(all);
  }

  /// Лучшая модель, доступная с этим ключом, — выбор по умолчанию.
  static String? defaultModelFor(String apiKey) {
    final list = catalogFor(apiKey);
    return list.isEmpty ? null : list.first.id;
  }

  /// Необязательный свой ключ ИИ (Poolside/Laguna или OpenRouter). Если он
  /// задан, пробуется первым; при отказе пул всё равно продолжит работу.
  final String apiKey;

  /// Имя сработавшего провайдера — для журнала агента.
  final void Function(String name)? onProvider;

  final http.Client _client;

  /// Подпись модели последнего ответа: шлюз может вернуть конкретную
  /// подмодель, а не ту, что просили, — показываем то, что реально ответило.
  String? _lastModel;

  @override
  String? get lastModel => _lastModel;

  /// Дольше ждать бессмысленно: прогон агента делает много шагов, и один
  /// зависший провайдер съел бы весь бюджет времени. Упавший — пропускаем.
  static const _timeout = Duration(seconds: 45);

  static const _poolsideUrl =
      'https://inference.poolside.ai/v1/chat/completions';
  static const _agnesUrl = 'https://apihub.agnes-ai.com/v1/chat/completions';
  static const _agnesModel = 'agnes-3.0-flash';
  static const _openrouterUrl = 'https://openrouter.ai/api/v1/chat/completions';
  static const _poolsideModel = 'poolside/laguna-s-2.1';
  static const _openrouterModel = 'poolside/laguna-s-2.1:free';

  static const _kiloUrl = 'https://api.kilo.ai/api/gateway/chat/completions';
  static const _murakumoUrl = 'https://api.murakumo.cloud/v1/chat/completions';
  static const _ovhUrl =
      'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1/chat/completions';

  @override
  Future<ForgeChatReply> complete(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) async {
    final failures = <String>[];
    // Общий бюджет перебора: пять площадок по 45 с — это почти четыре
    // минуты ожидания. Каждой даём лишь остаток, но НЕ выбрасываем её из
    // перебора: «все недоступны» раньше писались, даже не попробовав
    // последние каналы.
    final deadline = DateTime.now().add(const Duration(seconds: 80));

    for (final provider in _providers()) {
      final left = deadline.difference(DateTime.now());
      final limit = left <= Duration.zero ? const Duration(seconds: 6) : left;
      try {
        final reply = await _ask(provider, messages, tools, limit: limit);
        _lastGoodId = provider.id;
        onProvider?.call(provider.label);
        return reply;
      } on ForgeException catch (e) {
        // Отказ разобранного ответа (обрезка/пустой ответ) — не повод
        // бросать весь пул: следующий провайдер может ответить нормально.
        failures.add('${provider.label}: ${e.message}');
      } catch (e) {
        failures.add('${provider.label}: $e');
      }
    }

    throw ForgeException(
      502,
      'Бесплатные ИИ-провайдеры недоступны. Попробуй ещё раз позже.'
      '${failures.isEmpty ? '' : ' (${failures.join('; ')})'}',
    );
  }

  /// Провайдер, который ответил в прошлый раз. Повтор запроса почти всегда
  /// уходит к нему же, поэтому он идёт первым — вместо честного перебора
  /// «сверху вниз», где живой канал мог ждать очереди за двумя мёртвыми.
  static String? _lastGoodId;

  /// Разовый сбой шлюза (429/5xx/таймаут) — не приговор: пауза и один
  /// повтор чаще возвращают ответ, чем следующий провайдер с нуля.
  static bool _isTransient(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('429') ||
        text.contains('http 5') ||
        text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('socket');
  }

  List<_FreeProvider> _providers() {
    final all = <_FreeProvider>[
      if (apiKey.isNotEmpty)
        // Свой ключ — первым: он надёжнее бесплатных площадок. Если откажет,
        // пул молча продолжит на бесплатных.
        if (apiKey.startsWith('sk-or-'))
          _FreeProvider(
            id: 'openrouter-laguna',
            label: 'OpenRouter',
            url: _openrouterUrl,
            model: _openrouterModel,
            apiKey: apiKey,
          )
        else ...[
          // Ключ Agnes пробуем ДО Poolside: одно поле «Ключ провайдера» на
          // два сервиса, и ключ Agnes на Poolside получал отказ — разговор
          // продолжал бесплатный Kilo, хотя владелец вставил свой ключ.
          _FreeProvider(
            id: 'agnes-3.0-flash',
            label: 'Agnes AI',
            url: _agnesUrl,
            model: _agnesModel,
            apiKey: apiKey,
          ),
          _FreeProvider(
            id: 'poolside-laguna',
            label: 'Poolside',
            url: _poolsideUrl,
            model: _poolsideModel,
            apiKey: apiKey,
          ),
        ],
      // Основной: анонимно до 200 запросов/час на IP, отвечает сильной
      // бесплатной моделью и держит целые файлы (проверено: 300 строк без
      // обрезки при max_tokens 8000).
      const _FreeProvider(
        id: 'kilo-free',
        label: 'Kilo',
        url: _kiloUrl,
        model: 'openrouter/free',
        userAgent: 'AgyshaApp/1.6.0',
      ),
      const _FreeProvider(
        id: 'kilo-auto',
        label: 'Kilo',
        url: _kiloUrl,
        model: 'kilo-auto/free',
        userAgent: 'AgyshaApp/1.6.0',
      ),
      const _FreeProvider(
        id: 'murakumo-free',
        label: 'Murakumo',
        url: _murakumoUrl,
        model: 'murakumo/free',
      ),
      const _FreeProvider(
        id: 'ovh-mistral',
        label: 'OVHcloud',
        url: _ovhUrl,
        model: 'Mistral-Nemo-Instruct-2407',
        userAgent: 'AgyshaApp/1.6.0',
      ),
    ];
    final only = onlyModel;
    if (only != null) {
      final filtered = all.where((p) => p.id == only).toList(growable: false);
      // Сохранённый выбор мог устареть (пропал ключ, сменился пул) — тогда
      // лучше перебрать весь пул, чем остаться без ответа вовсе.
      if (filtered.isNotEmpty) return filtered;
    }
    // Живой канал прошлого ответа — первым: иначе он ждал очереди за
    // двумя мёртвыми, и пул писал «недоступны», не дойдя до рабочего.
    final last = _lastGoodId;
    final index = last == null ? -1 : all.indexWhere((p) => p.id == last);
    if (index <= 0) return all;
    return <_FreeProvider>[
      all[index],
      ...all.sublist(0, index),
      ...all.sublist(index + 1),
    ];
  }

  /// Один запрос с таймаутом [limit] и одним повтором на разовый сбой.
  Future<ForgeChatReply> _ask(
    _FreeProvider provider,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools, {
    required Duration limit,
  }) async {
    final timeout = limit > _timeout ? _timeout : limit;
    try {
      return await _sendOnce(provider, messages, tools, timeout);
    } catch (error) {
      if (!_isTransient(error) || timeout < const Duration(seconds: 3)) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 450));
      return _sendOnce(
        provider,
        messages,
        tools,
        timeout - const Duration(milliseconds: 450),
      );
    }
  }

  Future<ForgeChatReply> _sendOnce(
    _FreeProvider provider,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
    Duration timeout,
  ) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (provider.userAgent != null) {
      headers['User-Agent'] = provider.userAgent!;
    }
    if (provider.apiKey != null) {
      headers['Authorization'] = 'Bearer ${provider.apiKey}';
    }

    final resp = await _client
        .post(
          Uri.parse(provider.url),
          headers: headers,
          body: jsonEncode({
            'model': provider.model,
            'messages': messages,
            'tools': tools,
            'tool_choice': 'auto',
            // Код, а не проза: низкая температура держит модель на рельсах
            // инструментов и не даёт «пересочинять» файл.
            'temperature': 0.15,
            // Агенту нужно писать целые файлы, а не реплики чата.
            'max_tokens': 12000,
          }),
        )
        .timeout(timeout);

    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final raw = utf8.decode(resp.bodyBytes).trim();
    // Некоторые площадки отдают HTML-страницу вместо JSON.
    if (raw.isEmpty || raw.startsWith('<')) {
      throw Exception('не JSON');
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw Exception('не JSON-объект');
    final served = decoded['model'];
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) throw Exception('пустой ответ');
    final first = choices.first;
    // Обрезанный по лимиту токенов ответ с вызовами инструментов — это
    // половина файла: писать её в репозиторий нельзя. Отдаём провайдеру
    // отказ, и пул пробует следующего с более щедрым лимитом.
    if (first is Map &&
        first['finish_reason'] == 'length' &&
        first['message'] is Map &&
        (first['message'] as Map)['tool_calls'] is List) {
      throw Exception('ответ обрезан по лимиту токенов');
    }
    final message = first is Map ? first['message'] : null;
    if (message is! Map) throw Exception('пустой ответ');

    final calls = <ForgeToolCall>[];
    final rawCalls = message['tool_calls'];
    if (rawCalls is List) {
      for (var i = 0; i < rawCalls.length; i++) {
        final item = rawCalls[i];
        if (item is! Map) continue;
        final fn = item['function'];
        if (fn is! Map) continue;
        final name = fn['name'];
        if (name is! String) continue;
        final decoded = _decodeArgs(fn['arguments']);
        calls.add(
          ForgeToolCall(
            id: (item['id'] as String?) ?? 'call_$i',
            name: name,
            arguments: decoded.args,
            argumentsBroken: decoded.broken,
          ),
        );
      }
    }

    _lastModel = served is String && served.trim().isNotEmpty
        ? '${provider.label} · ${served.trim()}'
        : '${provider.label} · ${provider.model}';
    final text = message['content'];
    return ForgeChatReply(
      text: text is String && text.trim().isNotEmpty ? text : null,
      toolCalls: calls,
    );
  }
}

/// Содержимое, которое модель завернула в ```-забор или экранировала
/// дважды (`\\n` вместо перевода строки), писалось в файл буквально.
String _normalizeFileContent(String raw) {
  var s = raw;
  // Модель экранировала содержимое дважды: переводы строк пришли литералами
  // `\n`. Раскрываем их, когда литералов заметно больше настоящих переводов
  // (в нормальном коде бывает наоборот: строк много, а `\n` — раз-два), и
  // никогда не трогаем файл, где настоящих переводов уже достаточно.
  final realNl = '\n'.allMatches(s).length;
  final literalNl = r'\n'.allMatches(s).length;
  final doubleEscaped =
      literalNl > 0 &&
      (realNl == 0 || (literalNl >= 3 && realNl * 2 <= literalNl));
  if (doubleEscaped) {
    s = s
        .replaceAll(r'\\n', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\\t', '\t')
        .replaceAll(r'\t', '\t');
  }
  final trimmed = s.trim();
  if (trimmed.startsWith('```')) {
    final firstNl = trimmed.indexOf('\n');
    if (firstNl >= 0) {
      var body = trimmed.substring(firstNl + 1);
      final end = body.trimRight();
      if (end.endsWith('```')) {
        body = end.substring(0, end.length - 3);
      }
      s = body;
    }
  }
  return s;
}

class _FreeProvider {
  const _FreeProvider({
    required this.id,
    required this.label,
    required this.url,
    required this.model,
    this.userAgent,
    this.apiKey,
  });

  final String id;
  final String label;
  final String url;
  final String model;
  final String? userAgent;
  final String? apiKey;
}

/// Аргументы инструмента приходят строкой JSON (иногда невалидной).
/// [broken] — строка была, но не разобралась (обрезана по лимиту токенов).
({Map<String, dynamic> args, bool broken}) _decodeArgs(dynamic value) {
  if (value is Map<String, dynamic>) return (args: value, broken: false);
  if (value == null) return (args: const {}, broken: false);
  if (value is String) {
    final raw = value.trim();
    if (raw.isEmpty) return (args: const {}, broken: false);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return (args: decoded, broken: false);
      }
      return (args: const {}, broken: true);
    } catch (_) {
      // Локальные модели часто шлют почти-JSON: настоящие переводы строк
      // внутри строки, одинарные кавычки, висящая запятая. Раньше такой
      // вызов сразу считался битым — и `write_file` «не работал» вовсе.
      final repaired = _repairJson(raw);
      if (repaired != null) return (args: repaired, broken: false);
      return (args: const {}, broken: true);
    }
  }
  return (args: const {}, broken: false);
}

/// Разбирает «почти JSON» аргументов инструмента, не додумывая содержимое:
/// чинятся только структура и экранирование, обрезанная строка остаётся
/// битой (иначе в файл попал бы обрубок).
Map<String, dynamic>? _repairJson(String raw) {
  var s = raw.trim();
  if (s.startsWith('```')) {
    final nl = s.indexOf('\n');
    if (nl < 0) return null;
    s = s.substring(nl + 1);
    final fence = s.lastIndexOf('```');
    if (fence >= 0) s = s.substring(0, fence);
    s = s.trim();
  }
  final open = s.indexOf('{');
  if (open < 0) return null;
  s = s.substring(open);
  final escaped = _escapeRawControlChars(s);
  // Висящая запятая перед закрывающей скобкой — частая правка руками.
  final noTrailing = escaped.replaceAllMapped(
    RegExp(r',\s*([}\]])'),
    (m) => m.group(1)!,
  );
  for (final candidate in <String>[noTrailing]) {
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      continue;
    }
  }
  return null;
}

/// Экранирует настоящие управляющие символы ВНУТРИ строковых литералов.
/// Вне строк ничего не меняется, поэтому переводы строк форматирования
/// остаются как есть.
String _escapeRawControlChars(String input) {
  final out = StringBuffer();
  var inString = false;
  var escaped = false;
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    if (inString) {
      if (escaped) {
        escaped = false;
        out.write(ch);
        continue;
      }
      if (ch == '\\') {
        escaped = true;
        out.write(ch);
        continue;
      }
      if (ch == '"') {
        inString = false;
        out.write(ch);
        continue;
      }
      if (ch == '\n') {
        out.write(r'\n');
      } else if (ch == '\r') {
        out.write(r'\r');
      } else if (ch == '\t') {
        out.write(r'\t');
      } else {
        out.write(ch);
      }
      continue;
    }
    if (ch == '"') inString = true;
    out.write(ch);
  }
  return out.toString();
}

/// Сигнал остановки, который пролетел сквозь ожидание ответа модели.
class _ForgeCancelled implements Exception {
  const _ForgeCancelled();
}
