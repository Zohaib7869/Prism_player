import 'package:flutter_test/flutter_test.dart';
import 'package:prism_player/core/services/youtube_format_selector.dart';
import 'package:prism_player/models/youtube_native_format.dart';

YoutubeNativeFormat _video(String id, int height, {String vcodec = 'avc1', String acodec = 'none'}) {
  return YoutubeNativeFormat(formatId: id, height: height, vcodec: vcodec, acodec: acodec);
}

YoutubeNativeFormat _audioOnly(String id) {
  return YoutubeNativeFormat(formatId: id, vcodec: 'none', acodec: 'mp4a.40.2');
}

void main() {
  group('YoutubeFormatSelector.availableQualityLabels', () {
    test('returns empty list for no formats', () {
      expect(YoutubeFormatSelector.availableQualityLabels([]), isEmpty);
    });

    test('returns standard-height labels highest first', () {
      final formats = [_video('137', 1080), _video('136', 720), _video('135', 480)];
      expect(
        YoutubeFormatSelector.availableQualityLabels(formats),
        ['1080p', '720p', '480p'],
      );
    });

    test('deduplicates repeated heights (e.g. multiple codecs at the same resolution)', () {
      final formats = [
        _video('137', 1080),
        _video('399', 1080, vcodec: 'av01'),
        _video('136', 720),
      ];
      expect(
        YoutubeFormatSelector.availableQualityLabels(formats),
        ['1080p', '720p'],
      );
    });

    test('appends "Audio only" when an audio-only format exists', () {
      final formats = [_video('137', 1080), _audioOnly('140')];
      expect(
        YoutubeFormatSelector.availableQualityLabels(formats),
        ['1080p', YoutubeFormatSelector.audioOnlyLabel],
      );
    });

    test('non-standard heights are included, sorted after standard ones', () {
      final formats = [_video('137', 1080), _video('999', 900)];
      expect(
        YoutubeFormatSelector.availableQualityLabels(formats),
        ['1080p', '900p'],
      );
    });

    test('ignores audio-only formats when computing video heights', () {
      final formats = [_audioOnly('140')];
      expect(YoutubeFormatSelector.availableQualityLabels(formats), [YoutubeFormatSelector.audioOnlyLabel]);
    });
  });

  group('YoutubeFormatSelector.selectorForLabel', () {
    test('builds a height-capped selector for a standard label', () {
      expect(
        YoutubeFormatSelector.selectorForLabel('1080p'),
        'bestvideo[height<=1080]+bestaudio/best[height<=1080]',
      );
    });

    test('audio-only label maps to bestaudio', () {
      expect(YoutubeFormatSelector.selectorForLabel(YoutubeFormatSelector.audioOnlyLabel), 'bestaudio/best');
    });

    test('auto label maps to best video+audio', () {
      expect(
        YoutubeFormatSelector.selectorForLabel(YoutubeFormatSelector.autoLabel),
        'bestvideo+bestaudio/best',
      );
    });

    test('unrecognized label falls back to best available, never a hardcoded format id', () {
      final selector = YoutubeFormatSelector.selectorForLabel('not a real label');
      expect(selector, 'bestvideo+bestaudio/best');
      expect(selector, isNot(contains(RegExp(r'^\d+$'))));
    });

    test('never contains a literal format id across all standard labels', () {
      for (final label in ['2160p', '1440p', '1080p', '720p', '480p', '360p', '240p', '144p']) {
        final selector = YoutubeFormatSelector.selectorForLabel(label);
        expect(selector, contains('height<='));
        expect(selector, isNot(matches(RegExp(r'\bformat_id\b'))));
      }
    });
  });
}
