/// A single subtitle cue with its display window.
class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;
  const SubtitleCue({required this.start, required this.end, required this.text});
}

/// Pure-Dart parser for SRT and WebVTT files, plus a best-effort plain-text
/// extraction for ASS/SSA (full ASS styling/animation is not implemented —
/// only the literal dialogue text and timing are read, with override tags like
/// {\an8} stripped). This covers the vast majority of user subtitle files
/// without needing a native subtitle-rendering engine.
class SubtitleParser {
  SubtitleParser._();

  static List<SubtitleCue> parse(String content, String extension) {
    switch (extension.toLowerCase()) {
      case 'vtt':
        return _parseVtt(content);
      case 'ass':
      case 'ssa':
        return _parseAss(content);
      case 'srt':
      default:
        return _parseSrt(content);
    }
  }

  static List<SubtitleCue> _parseSrt(String content) {
    final cues = <SubtitleCue>[];
    final blocks = content.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));
    final timeRe = RegExp(
      r'(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,.](\d{3})',
    );
    for (final block in blocks) {
      final match = timeRe.firstMatch(block);
      if (match == null) continue;
      final start = _toDuration(match, 1);
      final end = _toDuration(match, 5);
      final lines = block.split('\n');
      final textStartIndex = lines.indexWhere((l) => timeRe.hasMatch(l)) + 1;
      if (textStartIndex <= 0 || textStartIndex > lines.length) continue;
      final text = lines
          .sublist(textStartIndex)
          .join('\n')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim();
      if (text.isNotEmpty) cues.add(SubtitleCue(start: start, end: end, text: text));
    }
    return cues;
  }

  static List<SubtitleCue> _parseVtt(String content) {
    final cues = <SubtitleCue>[];
    final blocks = content.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));
    final timeRe = RegExp(
      r'(\d{2}):(\d{2}):(\d{2})[.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[.](\d{3})',
    );
    for (final block in blocks) {
      final match = timeRe.firstMatch(block);
      if (match == null) continue;
      final start = _toDuration(match, 1);
      final end = _toDuration(match, 5);
      final lines = block.split('\n');
      final textStartIndex = lines.indexWhere((l) => timeRe.hasMatch(l)) + 1;
      if (textStartIndex <= 0 || textStartIndex > lines.length) continue;
      final text = lines
          .sublist(textStartIndex)
          .join('\n')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim();
      if (text.isNotEmpty) cues.add(SubtitleCue(start: start, end: end, text: text));
    }
    return cues;
  }

  static List<SubtitleCue> _parseAss(String content) {
    final cues = <SubtitleCue>[];
    final lines = content.split(RegExp(r'\r?\n'));
    final timeRe = RegExp(r'(\d):(\d{2}):(\d{2})[.](\d{2})');
    int textFieldIndex = 9; // default ASS "Dialogue:" field order

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.startsWith('Format:') && line.contains('Text')) {
        final fields = line.substring(7).split(',').map((f) => f.trim()).toList();
        final idx = fields.indexOf('Text');
        if (idx != -1) textFieldIndex = idx;
        continue;
      }
      if (!line.startsWith('Dialogue:')) continue;
      final parts = line.substring(9).split(',');
      if (parts.length <= textFieldIndex) continue;
      final startMatch = timeRe.firstMatch(parts[1].trim());
      final endMatch = timeRe.firstMatch(parts[2].trim());
      if (startMatch == null || endMatch == null) continue;
      final start = _toAssDuration(startMatch);
      final end = _toAssDuration(endMatch);
      final text = parts
          .sublist(textFieldIndex)
          .join(',')
          .replaceAll(RegExp(r'\{[^}]*\}'), '') // strip {\an8} style override tags
          .replaceAll(r'\N', '\n')
          .trim();
      if (text.isNotEmpty) cues.add(SubtitleCue(start: start, end: end, text: text));
    }
    return cues;
  }

  static Duration _toDuration(RegExpMatch m, int startGroup) {
    final h = int.parse(m.group(startGroup)!);
    final min = int.parse(m.group(startGroup + 1)!);
    final s = int.parse(m.group(startGroup + 2)!);
    final ms = int.parse(m.group(startGroup + 3)!);
    return Duration(hours: h, minutes: min, seconds: s, milliseconds: ms);
  }

  static Duration _toAssDuration(RegExpMatch m) {
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    final s = int.parse(m.group(3)!);
    final cs = int.parse(m.group(4)!); // centiseconds
    return Duration(hours: h, minutes: min, seconds: s, milliseconds: cs * 10);
  }
}
