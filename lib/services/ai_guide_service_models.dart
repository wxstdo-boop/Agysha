// Модели чата Ады: сообщение и действие для отмены.

part of 'ai_guide_service.dart';

/// Одно сообщение в переписке с проводником.
class AiMessage {
  final bool isUser;
  final String text;

  /// Метка времени (мс с эпохи) — для «Прочитано в HH:MM» под моим
  /// сообщением (время ответа Ады). null у старых сообщений — время
  /// тогда не показываем, только галочку.
  final int? ts;
  const AiMessage({required this.isUser, required this.text, this.ts});

  Map<String, dynamic> toJson() => {'isUser': isUser, 'text': text, 'ts': ts};
  factory AiMessage.fromJson(Map<String, dynamic> json) => AiMessage(
    isUser: json['isUser'] is bool
        ? (json['isUser'] as bool)
        : json['isUser'] is num
        ? (json['isUser'] as num) != 0
        : false,
    text: json['text'] as String? ?? '',
    ts: (json['ts'] as num?)?.toInt(),
  );
}

/// Последнее выполненное Адой действие — для кнопки «Отменить» в чате.
class AiUndoAction {
  /// 'habit' | 'task' | 'alarm' | 'reality_check' | 'meal'
  final String type;

  /// true — элемент был СОЗДАН (отмена = удалить), false — был УДАЛЁН
  /// (отмена = восстановить).
  final bool wasCreate;

  /// id созданного элемента (для удаления при отмене).
  final String id;

  /// Полный объект удалённого элемента (для восстановления при отмене).
  final Object? item;

  /// Человекочитаемое описание: «Привычка “Пить воду”».
  final String label;
  const AiUndoAction({
    required this.type,
    required this.wasCreate,
    required this.label,
    this.id = '',
    this.item,
  });
}

/// «Ада» — искусственный проводник.
///
/// Провайдеры: настроенные пользователем Poolside/Agnes/Zen, затем
/// анонимные Kilo, OVHcloud, Murakumo и AI Horde как резервные варианты.
///
/// Любая ошибка/таймаут пробрасывается наверх — UI показывает плавную
/// плашку «ИИ на курорте, подожди немного».
