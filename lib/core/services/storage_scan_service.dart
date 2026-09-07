import 'package:flutter/services.dart';

/// One update from an in-progress storage scan.
class StorageScanProgress {
  final bool isComplete;
  final int filesScanned;
  final int totalFiles;
  final int mediaFound;
  final int bytesScanned;
  final int totalStorageBytes;
  final double percentFiles;
  final double percentStorage;
  final String currentName;
  final List<Map<dynamic, dynamic>> videos;
  final List<Map<dynamic, dynamic>> audio;

  const StorageScanProgress({
    required this.isComplete,
    required this.filesScanned,
    required this.totalFiles,
    required this.mediaFound,
    required this.bytesScanned,
    required this.totalStorageBytes,
    required this.percentFiles,
    required this.percentStorage,
    required this.currentName,
    this.videos = const [],
    this.audio = const [],
  });

  factory StorageScanProgress.fromEvent(Map<dynamic, dynamic> e) {
    final isComplete = e['type'] == 'complete';
    return StorageScanProgress(
      isComplete: isComplete,
      filesScanned: (e['filesScanned'] as num?)?.toInt() ?? 0,
      totalFiles: (e['totalFiles'] as num?)?.toInt() ?? 1,
      mediaFound: (e['mediaFound'] as num?)?.toInt() ?? 0,
      bytesScanned: (e['bytesScanned'] as num?)?.toInt() ?? 0,
      totalStorageBytes: (e['totalStorageBytes'] as num?)?.toInt() ?? 0,
      percentFiles: isComplete ? 100.0 : ((e['percentFiles'] as num?)?.toDouble() ?? 0.0),
      percentStorage: (e['percentStorage'] as num?)?.toDouble() ?? 0.0,
      currentName: (e['currentName'] as String?) ?? '',
      videos: isComplete ? (e['videos'] as List).cast<Map<dynamic, dynamic>>() : const [],
      audio: isComplete ? (e['audio'] as List).cast<Map<dynamic, dynamic>>() : const [],
    );
  }
}

/// Thin wrapper around the native `com.prismplayer.app/storage_scan` EventChannel.
/// Streams real-time progress (files scanned, % of storage scanned) while the
/// native side walks MediaStore, then delivers the full result set as the last event.
class StorageScanService {
  static const _channel = EventChannel('com.prismplayer.app/storage_scan');

  Stream<StorageScanProgress> scan() {
    return _channel.receiveBroadcastStream().map(
          (event) => StorageScanProgress.fromEvent(event as Map<dynamic, dynamic>),
        );
  }
}
