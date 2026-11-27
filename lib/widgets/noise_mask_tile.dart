import 'package:material_ui/material_ui.dart';

import '../l10n/locale_provider.dart';
import '../services/noise_mask_service.dart';
import 'volumetric_switch.dart';

/// «Шумоподавление»: тихий дождь в наушниках.
///
/// Смысл — спать в шумном общежитии: тумблер один раз, а дальше дождь
/// сам появляется, когда вставлены наушники, и сам гаснет, когда их
/// вынули. Поэтому в подписи всегда видно, чего сервис ждёт сейчас.
class NoiseMaskTile extends StatelessWidget {
  static const Color _accent = Color(0xFF64B5F6);

  const NoiseMaskTile({super.key});

  @override
  Widget build(BuildContext context) {
    final code = LocaleProvider.of(context).languageCode;
    final service = NoiseMaskService.instance;
    final title = switch (code) {
      'ru' => 'Шумоподавление',
      'fr' => 'Masquage du bruit',
      _ => 'Noise mask',
    };
    final hint = switch (code) {
      'ru' => 'Дождь в наушниках, чтобы уснуть в шумной комнате',
      'fr' => 'Pluie dans le casque pour dormir dans une pièce bruyante',
      _ => 'Rain in headphones to sleep in a noisy room',
    };
    return ValueListenableBuilder<bool>(
      valueListenable: service.playing,
      builder: (context, playing, _) => ValueListenableBuilder<bool>(
        valueListenable: service.headphonesConnected,
        builder: (context, headphones, _) => ValueListenableBuilder<bool>(
          valueListenable: service.enabled,
          builder: (context, enabled, _) {
            final state = switch ((enabled, headphones, playing)) {
              (false, _, _) => switch (code) {
                'ru' => 'Выключено',
                'fr' => 'Désactivé',
                _ => 'Off',
              },
              (true, false, _) => switch (code) {
                'ru' => 'Включено · ждёт наушников',
                'fr' => 'Activé · en attente du casque',
                _ => 'On · waiting for headphones',
              },
              (true, true, false) => switch (code) {
                'ru' => 'Включено · готовится дождь',
                'fr' => 'Activé · préparation de la pluie',
                _ => 'On · preparing rain',
              },
              _ => switch (code) {
                'ru' => 'Включено · дождь играет',
                'fr' => 'Activé · pluie en cours',
                _ => 'On · rain is playing',
              },
            };
            return ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              leading: const Icon(Icons.water_drop_outlined, color: _accent),
              title: Text(title),
              subtitle: Text(
                '$hint\n$state',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
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
