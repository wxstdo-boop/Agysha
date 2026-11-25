import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ai_guide_service.dart';
import 'json_file.dart';
import '../widgets/ada_avatars.dart';

/// Общая история чата Ады для главного окна, плавающего пузыря и оверлея.
///
/// Два Flutter-движка не делят память, поэтому запись всегда идёт через
/// [JsonFile.writeWithSnapshot], а после слияния вызывающий обязан принять
/// вернувшийся список — иначе локальная копия расходится с диском.
class AiChatStore {
  AiChatStore._();

  static const key = 'ai_chat_history';

  /// Растёт в этом движке после каждой удачной записи. Второй движок
  /// видит то же число в `ada_sync_state.historyRev`.
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static List<AiMessage> parse(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .map((item) => AiMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<({List<AiMessage> messages, String? snapshot})> load() async {
    final raw = await JsonFile.read(key);
    return (messages: parse(raw), snapshot: raw);
  }

  static Future<({List<AiMessage> messages, String snapshot})> save(
    List<AiMessage> messages,
    String? snapshot,
  ) async {
    var toSave = messages;
    if (toSave.length > 1000) {
      toSave = toSave.sublist(toSave.length - 1000);
    }
    final value = jsonEncode(toSave.map((message) => message.toJson()).toList());
    final resolved = await JsonFile.writeWithSnapshot(key, value, snapshot);
    final next = DateTime.now().millisecondsSinceEpoch;
    tick.value = next;
    await writeAdaSyncState(historyRev: next);
    return (messages: parse(resolved), snapshot: resolved);
  }

  /// Дописывает сообщения, которые уже есть в памяти, но ещё не попали
  /// в слитый снимок (например, только что набранный вопрос, пока шёл merge).
  static List<AiMessage> adopt(
    List<AiMessage> local,
    List<AiMessage> incoming,
  ) {
    if (incoming.isEmpty && local.isEmpty) return local;
    final seen = {for (final message in incoming) identity(message)};
    final extra = local.where((message) => seen.add(identity(message)));
    return [...incoming, ...extra];
  }

  /// Запись истории с ОБЯЗАТЕЛЬНЫМ принятием результата.
  ///
  /// [JsonFile] при одновременной записи из второго движка сливает списки и
  /// возвращает слияние. Если вызывающий оставляет в памяти свою старую
  /// копию, следующая запись считает «лишние» сообщения удалёнными и стирает
  /// их с диска — именно так история чата и пропадала после перезахода.
  /// Поэтому отдаём наружу разобранный ответ, а не только снимок.
  static Future<({List<AiMessage> messages, String? snapshot})> persist(
    List<AiMessage> messages,
    String? snapshot,
  ) async {
    final toSave = messages.length > 1000
        ? messages.sublist(messages.length - 1000)
        : messages;
    try {
      // Историю пишут два движка. Перед записью забираем то, что уже лежит
      // на диске: список, который пришёл из устаревшей копии, не должен
      // считаться удалением чужих сообщений (механика слияния в
      // [JsonFile] трактует отсутствие элемента как delete).
      final raw = await JsonFile.read(key);
      final clearedAt = AiGuideService.chatClearedAt();
      final toSaveVisible = toSave
          .where((m) => AiGuideService.visibleInChat(m, clearedAt))
          .toList();
      final merged = union(
        parse(raw).where((m) => AiGuideService.visibleInChat(m, clearedAt)).toList(),
        toSaveVisible,
      );
      final mergedValue = jsonEncode(
        merged.map((message) => message.toJson()).toList(),
      );
      final resolved = await JsonFile.writeWithSnapshotRetrying(
        key,
        mergedValue,
        raw,
      );
      return (messages: parse(resolved), snapshot: resolved);
    } on JsonFileConflictException {
      return _persistUnion(toSave);
    }
  }

  /// Стирает историю целиком (кнопка «Очистить чат»). Идёт мимо союза в
  /// [persist]: там пустой локальный список объединился бы с диском и
  /// вернул удалённое.
  static Future<void> clear() async {
    // Именно поверх, без слияния: иначе второй движок (пузырь, оверлей),
    // писавший историю параллельно, возвращал стёртые сообщения.
    await JsonFile.writeReplacing(key, '[]');
    final next = DateTime.now().millisecondsSinceEpoch;
    tick.value = next;
    await writeAdaSyncState(historyRev: next);
  }

  /// Перечитать и объединить ещё раз — на случай, когда файл переписали
  /// прямо между чтением и записью.
  static Future<({List<AiMessage> messages, String? snapshot})> _persistUnion(
    List<AiMessage> local,
  ) async {
    final raw = await JsonFile.read(key);
    final clearedAt = AiGuideService.chatClearedAt();
    final merged = union(
      parse(
        raw,
      ).where((m) => AiGuideService.visibleInChat(m, clearedAt)).toList(),
      local.where((m) => AiGuideService.visibleInChat(m, clearedAt)).toList(),
    );
    final resolved = await JsonFile.writeWithSnapshot(
      key,
      jsonEncode(merged.map((message) => message.toJson()).toList()),
      raw,
    );
    return (messages: parse(resolved), snapshot: resolved);
  }

  /// Союз двух копий истории: порядок с диска сохраняется, сообщения,
  /// которых на диске ещё нет, дописываются в конце.
  static List<AiMessage> union(List<AiMessage> onDisk, List<AiMessage> local) {
    final seen = <String>{};
    final out = <AiMessage>[];
    for (final message in [...onDisk, ...local]) {
      if (seen.add(identity(message))) out.add(message);
    }
    // Тот же предел, что и в UI: иначе объединение с более длинным файлом
    // отменяло бы обрезку и история росла бесконечно.
    return out.length > 1000 ? out.sublist(out.length - 1000) : out;
  }

  static String identity(AiMessage message) =>
      '${message.ts}:${message.isUser}:${message.text}';
}
