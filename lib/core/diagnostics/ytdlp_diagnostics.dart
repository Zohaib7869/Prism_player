import '../services/youtube_native_service.dart';

/// Debug-only diagnostic snapshot for the yt-dlp native bridge (§15). Not a
/// UI widget — just the data a future debug panel would display. Holds the
/// last known state so the panel doesn't need to re-run checks on every
/// rebuild.
class YtDlpDiagnostics {
  final YoutubeNativeService _service;

  bool? available;
  String? version;
  DateTime? lastCheckedAt;
  String? lastError;

  YtDlpDiagnostics({YoutubeNativeService? service})
      : _service = service ?? YoutubeNativeService();

  /// Re-runs [YoutubeNativeService.isAvailable] and [YoutubeNativeService.getVersion],
  /// updating this snapshot in place.
  Future<void> refresh() async {
    lastCheckedAt = DateTime.now();
    try {
      available = await _service.isAvailable();
      version = available == true ? await _service.getVersion() : null;
      lastError = null;
    } on YoutubeNativeException catch (e) {
      available = false;
      version = null;
      lastError = e.toString();
    }
  }

  @override
  String toString() =>
      'YtDlpDiagnostics(available=$available, version=$version, lastError=$lastError)';
}
