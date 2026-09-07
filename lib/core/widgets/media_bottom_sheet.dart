import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SheetAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  const SheetAction({required this.icon, required this.label, required this.onTap, this.destructive = false});
}

/// The single shared "long-press" / "more" action sheet used by videos, songs
/// and folders (Play, Add to playlist, Rename, Delete, Share, Info, Open
/// folder, Hide/Unhide, Favorite) — callers just supply which actions apply.
Future<void> showMediaBottomSheet({
  required BuildContext context,
  required String title,
  required String subtitle,
  required List<SheetAction> actions,
}) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  return showModalBottomSheet(
    context: context,
    backgroundColor: palette.surfaceElevated,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
                        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: palette.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: actions.length,
                itemBuilder: (context, i) {
                  final action = actions[i];
                  return ListTile(
                    leading: Icon(action.icon, color: action.destructive ? palette.error : palette.textPrimary),
                    title: Text(action.label,
                        style: TextStyle(color: action.destructive ? palette.error : palette.textPrimary)),
                    onTap: () {
                      Navigator.of(context).pop();
                      action.onTap();
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<bool?> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel, style: TextStyle(color: destructive ? palette.error : palette.accent)),
        ),
      ],
    ),
  );
}

Future<String?> showTextInputDialog({
  required BuildContext context,
  required String title,
  required String initialValue,
  String hint = '',
}) {
  final controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}
