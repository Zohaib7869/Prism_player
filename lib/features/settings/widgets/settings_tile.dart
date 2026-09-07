import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class SettingsSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const SettingsSwitchTile({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return SwitchListTile(
      title: Text(title, style: TextStyle(color: palette.textPrimary)),
      subtitle: subtitle != null ? Text(subtitle!, style: TextStyle(color: palette.textMuted, fontSize: 12)) : null,
      value: value,
      activeColor: palette.accent,
      onChanged: onChanged,
    );
  }
}

class SettingsDropdownTile<T> extends StatelessWidget {
  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  const SettingsDropdownTile({super.key, required this.title, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return ListTile(
      title: Text(title, style: TextStyle(color: palette.textPrimary)),
      trailing: DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        dropdownColor: palette.surfaceElevated,
        items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class SettingsActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;
  const SettingsActionTile({super.key, required this.icon, required this.title, this.subtitle, required this.onTap, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final color = destructive ? palette.error : palette.textPrimary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: subtitle != null ? Text(subtitle!, style: TextStyle(color: palette.textMuted, fontSize: 12)) : null,
      onTap: onTap,
    );
  }
}

class SettingsSectionLabel extends StatelessWidget {
  final String text;
  const SettingsSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text.toUpperCase(), style: TextStyle(color: palette.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    );
  }
}
