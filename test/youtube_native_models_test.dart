import 'package:flutter_test/flutter_test.dart';
import 'package:prism_player/models/youtube_native_download_event.dart';
import 'package:prism_player/models/youtube_native_format.dart';
import 'package:prism_player/models/youtube_native_info.dart';
import 'package:prism_player/models/youtube_native_stream_result.dart';

void main() {
  group('YoutubeNativeFormat.fromMap', () {
    test('parses a typical adaptive video format', () {
      final format = YoutubeNativeFormat.fromMap({
        'format_id': '137',
        'ext': 'mp4',
        'height': 1080,
        'width': 1920,
        'fps': 30.0,
        'vcodec': 'avc1.640028',
        'acodec': 'none',
        'tbr': 4500.5,
        'filesize': 52000000,
        'format_note': '1080p',
        'http_headers': {'User-Agent': 'test-ua'},
      });

      expect(format.formatId, '137');
      expect(format.height, 1080);
      expect(format.hasVideo, isTrue);
      expect(format.hasAudio, isFalse);
      expect(format.httpHeaders['User-Agent'], 'test-ua');
    });

    test('parses an audio-only format', () {
      final format = YoutubeNativeFormat.fromMap({
        'format_id': '140',
        'vcodec': 'none',
        'acodec': 'mp4a.40.2',
        'abr': 128.0,
      });

      expect(format.hasVideo, isFalse);
      expect(format.hasAudio, isTrue);
      expect(format.abr, 128.0);
    });

    test('handles missing/null fields gracefully', () {
      final format = YoutubeNativeFormat.fromMap({'format_id': '18'});
      expect(format.formatId, '18');
      expect(format.height, isNull);
      expect(format.hasVideo, isFalse);
      expect(format.hasAudio, isFalse);
      expect(format.httpHeaders, isEmpty);
    });
  });

  group('YoutubeNativeStreamResult.fromMap', () {
    test('parses an adaptive (non-combined) result', () {
      final result = YoutubeNativeStreamResult.fromMap({
        'videoUrl': 'https://example.com/video',
        'audioUrl': 'https://example.com/audio',
        'combined': false,
        'quality': '1080p',
        'formatId': '137',
        'headers': {'Cookie': 'abc'},
      });

      expect(result.videoUrl, 'https://example.com/video');
      expect(result.audioUrl, 'https://example.com/audio');
      expect(result.combined, isFalse);
      expect(result.headers['Cookie'], 'abc');
    });

    test('defaults combined to true and audioUrl to null when absent', () {
      final result = YoutubeNativeStreamResult.fromMap({
        'videoUrl': 'https://example.com/video',
        'quality': '360p',
        'formatId': '18',
      });

      expect(result.combined, isTrue);
      expect(result.audioUrl, isNull);
    });
  });

  group('YoutubeNativeInfo.fromMap', () {
    test('parses metadata and nested formats list', () {
      final info = YoutubeNativeInfo.fromMap({
        'id': 'jNQXAC9IVRw',
        'title': 'Me at the zoo',
        'duration': 19.0,
        'extractor': 'youtube',
        'formats': [
          {'format_id': '18', 'vcodec': 'avc1', 'acodec': 'mp4a.40.2', 'height': 360},
          {'format_id': '140', 'vcodec': 'none', 'acodec': 'mp4a.40.2'},
        ],
      });

      expect(info.id, 'jNQXAC9IVRw');
      expect(info.title, 'Me at the zoo');
      expect(info.durationSeconds, 19.0);
      expect(info.formats, hasLength(2));
      expect(info.formats.first.formatId, '18');
    });

    test('handles missing formats list', () {
      final info = YoutubeNativeInfo.fromMap({'id': 'x', 'title': 'y'});
      expect(info.formats, isEmpty);
    });
  });

  group('YoutubeNativeDownloadEvent.fromMap', () {
    test('parses a progress event', () {
      final event = YoutubeNativeDownloadEvent.fromMap({
        'downloadId': 'dl-1',
        'type': 'progress',
        'progress': 0.5,
        'etaSeconds': 30,
      });

      expect(event.type, YoutubeNativeDownloadEventType.progress);
      expect(event.progress, 0.5);
      expect(event.etaSeconds, 30);
    });

    test('parses a completed event', () {
      final event = YoutubeNativeDownloadEvent.fromMap({
        'downloadId': 'dl-1',
        'type': 'completed',
        'outputPath': '/storage/emulated/0/Movies/video.mp4',
      });

      expect(event.type, YoutubeNativeDownloadEventType.completed);
      expect(event.outputPath, isNotNull);
    });

    test('parses a failed event with normalized error code', () {
      final event = YoutubeNativeDownloadEvent.fromMap({
        'downloadId': 'dl-1',
        'type': 'failed',
        'errorCode': 'HTTP_403',
        'errorMessage': 'Forbidden',
      });

      expect(event.type, YoutubeNativeDownloadEventType.failed);
      expect(event.errorCode, 'HTTP_403');
    });

    test('unrecognized type string falls back to failed', () {
      final event = YoutubeNativeDownloadEvent.fromMap({
        'downloadId': 'dl-1',
        'type': 'something_unexpected',
      });
      expect(event.type, YoutubeNativeDownloadEventType.failed);
    });
  });
}
