import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../utils/jank_probe.dart';
import '../utils/perf_prefs.dart';
import '../widgets/press_scale.dart';

/// Панель «Плавность»: открывается долгим нажатием на «Оптимизацию».
///
/// Зачем: «иногда норм, иногда лагает» нельзя починить на глаз — нужны числа с
/// того самого телефона. Счётчик кадров ([JankProbe]) считает всегда, а эта
/// панель просто показывает его сводку и даёт скопировать её в буфер, чтобы
/// прислать без adb.
class PerfPanelScreen extends StatefulWidget {
  const PerfPanelScreen({super.key});

  @override
  State<PerfPanelScreen> createState() => _PerfPanelScreenState();
}

class _PerfPanelScreenState extends State<PerfPanelScreen> {
  Timer? _timer;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    // Раз в секунду, а не каждый кадр: панель не должна сама себе мешать.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: JankProbe.report));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = JankProbe.summary;
    final hz = s.refreshRate > 1 ? s.refreshRate : 60.0;
    final budget = 1000 / hz;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Плавность'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _Big(
              title: 'Кадры сверх бюджета',
              value: s.isEmpty
                  ? '—'
                  : '${s.jankPercent.toStringAsFixed(1)} %',
              hint: s.isEmpty
                  ? 'счётчик ещё не получал кадры'
                  : '${s.janky} из ${s.frames} дольше '
                      '${budget.toStringAsFixed(1)} мс (${hz.toStringAsFixed(0)} Гц)',
              accent: s.jankPercent == 0
                  ? cs.primary
                  : (s.jankPercent > 12 ? cs.error : cs.tertiary),
            ),
            const SizedBox(height: 14),
            _Row(
              label: 'Сборка (Dart)',
              values: s.buildAvg,
              p90: s.buildP90,
              max: s.buildMax,
              budget: budget,
              cs: cs,
            ),
            const SizedBox(height: 10),
            _Row(
              label: 'Растровка (GPU)',
              values: s.rasterAvg,
              p90: s.rasterP90,
              max: s.rasterMax,
              budget: budget,
              cs: cs,
            ),
            const SizedBox(height: 16),
            _Line(
              'Вердикт',
              s.isEmpty
                  ? '—'
                  : (s.rasterBound
                      ? 'GPU: пиксели (blur, тени, слои)'
                      : 'Dart: пересборка виджетов'),
              cs: cs,
            ),
            if (s.worstLabel.isNotEmpty)
              _Line(
                'Худший кадр',
                '${s.worstLabel} · ${s.worstRaster.toStringAsFixed(1)} мс',
                cs: cs,
              ),
            if (s.byLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final e in (s.byLabel.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value))))
                _Line('· ${e.key}', '${e.value}', cs: cs),
            ],
            const SizedBox(height: 18),
            _Line(
              'Бюджет кадра',
              '${JankProbe.budgetMs.toStringAsFixed(1)} мс · '
                  'нагрузка ${(JankProbe.pressure * 100).round()} %',
              cs: cs,
            ),
            _Line(
              'Режим',
              PerfPrefs.active
                  ? 'Оптимизация включена: декор заморожен, наклона нет'
                  : 'обычный',
              cs: cs,
            ),
            _Line(
              'Декор',
              'ровный шаг ~60 fps',
              cs: cs,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: PressScale(
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        JankProbe.reset();
                        setState(() {});
                      },
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: const Text('Сброс'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PressScale(
                    child: FilledButton.icon(
                      onPressed: _copy,
                      icon: Icon(
                        _copied
                            ? Icons.check_rounded
                            : Icons.copy_rounded,
                        size: 18,
                      ),
                      label: Text(_copied ? 'Скопировано' : 'Скопировать'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Счётчик считает всё время, пока приложение открыто, и по '
              'кадрам подписывает экран, на котором кадр не успел. Пока эта '
              'панель открыта, её собственные обновления тоже попадают в '
              'цифры — смотрите их до открытия панели, а «Сброс» очищает окно.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({
    required this.title,
    required this.value,
    required this.hint,
    required this.accent,
  });

  final String title;
  final String value;
  final String hint;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.displaySmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.values,
    required this.p90,
    required this.max,
    required this.budget,
    required this.cs,
  });

  final String label;
  final double values;
  final double p90;
  final double max;
  final double budget;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = (values / budget).clamp(0.0, 1.0);
    final color = values < budget * 0.7
        ? cs.primary
        : (values < budget ? cs.tertiary : cs.error);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            Text(
              '${values.toStringAsFixed(1)} · p90 '
              '${p90.toStringAsFixed(1)} · макс ${max.toStringAsFixed(1)} мс',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fill,
            minHeight: 6,
            backgroundColor: cs.onSurface.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {required this.cs});

  final String label;
  final String value;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
