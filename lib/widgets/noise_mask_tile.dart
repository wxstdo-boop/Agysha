import 'package:material_ui/material_ui.dart';

import '../l10n/locale_provider.dart';
import '../services/noise_mask_service.dart';
import 'volumetric_switch.dart';

/// «Шумоподавление»: тихий дождь в наушниках.
///
/// Смысл — спать в шумном общежитии: тумблер один раз, а дальше дождь
/// сам появляется, когда вставлены наушники, и сам гаснет, когда их
/// вынули. Поэтому в подписи всегда видно, чего сервис ждёт сейчас.
///
/// Плитка отвечает на каждое действие: значок меняется на наушники, пока
/// дождь ждёт гарнитуру, и подсвечивается, пока играет; строка состояния
/// перетекает, а не перещёлкивается; пока рендерится петля — виден
/// маленький круг ожидания.
class NoiseMaskTile extends StatelessWidget {
  static const Color _accent = Color(0xFF64B5F6);

  const NoiseMaskTile({super.key});

  static String _text(String code, String ru, String fr, String en) =>
      switch (code) {
        'ru' => ru,
        'fr' => fr,
        _ => en,
      };

  @override
  Widget build(BuildContext context) {
    final code = LocaleProvider.of(context).languageCode;
    final service = NoiseMaskService.instance;
    final title = _text(
      code,
      'Шумоподавление',
      'Masquage du bruit',
      'Noise mask',
    );
    final hint = _text(
      code,
      'Дождь в наушниках, чтобы уснуть в шумной комнате',
      'Pluie dans le casque pour dormir dans une pièce bruyante',
      'Rain in headphones to sleep in a noisy room',
    );
    return ValueListenableBuilder<bool>(
      valueListenable: service.playing,
      builder: (context, playing, _) => ValueListenableBuilder<bool>(
        valueListenable: service.headphonesConnected,
        builder: (context, headphones, _) => ValueListenableBuilder<bool>(
          valueListenable: service.enabled,
          builder: (context, enabled, _) {
            final waiting = enabled && !headphones;
            final preparing = enabled && headphones && !playing;
            final state = switch ((enabled, headphones, playing)) {
              (false, _, _) => _text(code, 'Выключено', 'Désactivé', 'Off'),
              (true, false, _) => _text(
                code,
                'Включено · ждёт наушников',
                'Activé · en attente du casque',
                'On · waiting for headphones',
              ),
              (true, true, false) => _text(
                code,
                'Включено · готовится дождь',
                'Activé · préparation de la pluie',
                'On · preparing rain',
              ),
              _ => _text(
                code,
                'Включено · дождь играет',
                'Activé · pluie en cours',
                'On · rain is playing',
              ),
            };
            // Значок говорит то же, что и строка: наушники, пока ждём
            // гарнитуру, капля — когда дождь идёт.
            final icon = waiting
                ? Icons.headphones_outlined
                : Icons.water_drop_outlined;
            return ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              leading: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent.withValues(
                    alpha: playing ? 0.22 : (enabled ? 0.12 : 0.06),
                  ),
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.82,
                        end: 1,
                      ).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Icon(
                      icon,
                      key: ValueKey(icon),
                      size: 21,
                      color: enabled ? _accent : _accent.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
              title: Text(title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  // Строка состояния перетекает: «ждёт наушников» →
                  // «готовится» → «играет» раньше щёлкала текстом.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.22),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Row(
                      key: ValueKey(state),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (preparing) ...[
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              color: _accent.withValues(alpha: 0.9),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            state,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: RepaintBoundary(
                child: VolumetricSwitch(
                  value: enabled,
                  onChanged: service.setEnabled,
                  activeColor: _accent,
                  semanticLabel: title,
                  scale: 1.28,
                ),
              ),
              onTap: () => service.setEnabled(!enabled),
            );
          },
        ),
      ),
    );
  }
}
