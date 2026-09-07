import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/media_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  late bool _enabled;
  late int _presetIndex;
  late List<int> _bands;
  late bool _bassEnabled;
  late int _bassStrength;
  late bool _virtualizerEnabled;
  late int _virtualizerStrength;

  static const _presetNames = ['Normal', 'Flat', 'Classical', 'Dance', 'Folk', 'HeavyMetal', 'HipHop', 'Jazz', 'Pop', 'Rock', 'Custom'];

  @override
  void initState() {
    super.initState();
    final saved = ref.read(eqSettingsRepositoryProvider).current;
    _enabled = saved.equalizerEnabled;
    _presetIndex = saved.presetIndex;
    _bands = saved.bandLevelsMb.isEmpty
        ? List<int>.filled(EqPresets.centerFrequenciesHz.length, 0)
        : [...saved.bandLevelsMb];
    _bassEnabled = saved.bassBoostEnabled;
    // Self-heal a saved-but-audibly-silent 0 strength (from before this was
    // fixed) so the slider actually reflects what's being applied, not a
    // stale zero left over from when the switch was first turned on.
    _bassStrength = (saved.bassBoostEnabled && saved.bassBoostStrength <= 0) ? 700 : saved.bassBoostStrength;
    _virtualizerEnabled = saved.virtualizerEnabled;
    _virtualizerStrength =
        (saved.virtualizerEnabled && saved.virtualizerStrength <= 0) ? 700 : saved.virtualizerStrength;
  }

  void _applyPreset(int index) {
    final name = _presetNames[index];
    final curve = EqPresets.curves[name] ?? List<int>.filled(_bands.length, 0);
    setState(() {
      _presetIndex = index;
      _bands = [...curve];
    });
    ref.read(globalPlayerControllerProvider.notifier).setEqualizerPreset(index, curve);
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final controller = ref.read(globalPlayerControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer'),
        actions: [
          Switch(
            value: _enabled,
            activeColor: palette.accent,
            onChanged: (v) {
              setState(() => _enabled = v);
              controller.setEqualizerEnabled(v);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Text(
            'Equalizer effects apply to Music playback and any video played via "Play as Audio" — '
            'native video playback doesn\'t expose an Android audio session for these effects to attach to.',
            style: TextStyle(color: palette.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          // Only the band-EQ section below is gated by the master switch —
          // Bass Boost and Virtualizer are independent native effects and
          // must stay usable even when the master Equalizer switch is off.
          AbsorbPointer(
            absorbing: !_enabled,
            child: Opacity(
              opacity: _enabled ? 1 : 0.4,
              child: Column(
                children: [
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _presetNames.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => ChoiceChip(
                        label: Text(_presetNames[i]),
                        selected: _presetIndex == i,
                        onSelected: (_) => _applyPreset(i),
                        backgroundColor: palette.surface,
                        selectedColor: palette.accent.withOpacity(0.25),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(18)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(_bands.length, (i) => Expanded(
                        child: _BandSlider(
                          label: _freqLabel(EqPresets.centerFrequenciesHz[i]),
                          valueMb: _bands[i],
                          palette: palette,
                          onChanged: (v) {
                            setState(() {
                              _bands[i] = v;
                              _presetIndex = -1;
                            });
                            controller.setEqualizerBand(i, v);
                          },
                        ),
                      )),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _EffectTile(
            title: 'Bass Boost',
            enabled: _bassEnabled,
            strength: _bassStrength,
            palette: palette,
            onEnabledChanged: (v) {
              setState(() {
                _bassEnabled = v;
                // Strength defaults to 0, so flipping the switch on alone
                // used to enable the native effect at zero strength — which
                // is audibly silent and looked like Bass Boost "didn't
                // work". Give it a sensible starting strength the first
                // time it's turned on; the slider still overrides freely.
                if (v && _bassStrength == 0) _bassStrength = 700;
              });
              controller.setBassBoost(v, _bassStrength);
            },
            onStrengthChanged: (v) {
              setState(() => _bassStrength = v);
              controller.setBassBoost(_bassEnabled, v);
            },
          ),
          const SizedBox(height: 12),
          _EffectTile(
            title: 'Virtualizer',
            enabled: _virtualizerEnabled,
            strength: _virtualizerStrength,
            palette: palette,
            onEnabledChanged: (v) {
              setState(() {
                _virtualizerEnabled = v;
                // Same zero-strength-on-enable issue as Bass Boost above.
                if (v && _virtualizerStrength == 0) _virtualizerStrength = 700;
              });
              controller.setVirtualizer(v, _virtualizerStrength);
            },
            onStrengthChanged: (v) {
              setState(() => _virtualizerStrength = v);
              controller.setVirtualizer(_virtualizerEnabled, v);
            },
          ),
        ],
      ),
    );
  }

  String _freqLabel(int hz) => hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k' : '$hz';
}

class _BandSlider extends StatelessWidget {
  final String label;
  final int valueMb;
  final PrismPalette palette;
  final ValueChanged<int> onChanged;
  const _BandSlider({required this.label, required this.valueMb, required this.palette, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 140,
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: valueMb.clamp(-1500, 1500).toDouble(),
              min: -1500,
              max: 1500,
              activeColor: palette.accent,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: palette.textMuted, fontSize: 11)),
      ],
    );
  }
}

class _EffectTile extends StatelessWidget {
  final String title;
  final bool enabled;
  final int strength;
  final PrismPalette palette;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onStrengthChanged;

  const _EffectTile({
    required this.title,
    required this.enabled,
    required this.strength,
    required this.palette,
    required this.onEnabledChanged,
    required this.onStrengthChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600))),
              Switch(value: enabled, activeColor: palette.accent, onChanged: onEnabledChanged),
            ],
          ),
          Slider(
            value: strength.toDouble(),
            min: 0,
            max: 1000,
            activeColor: palette.accent,
            onChanged: enabled ? (v) => onStrengthChanged(v.round()) : null,
          ),
        ],
      ),
    );
  }
}
