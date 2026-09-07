import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/database/hive_boxes.dart';
import '../models/download_task.dart';

/// Thin persistence layer over the downloads box. Everything that decides
/// *when* a download runs lives in DownloadManager; this only stores rows.
class DownloadRepository {
  Box<DownloadTask> get _box => Hive.box<DownloadTask>(HiveBoxes.downloads);

  /// Newest first — the order both the "Downloading" list and the completed
  /// tabs are displayed in.
  List<DownloadTask> all() {
    final tasks = _box.values.toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return tasks;
  }

  DownloadTask? byId(String id) => _box.get(id);

  /// True when this exact video has already been downloaded at this quality,
  /// so the sheet can show "Downloaded" instead of queuing a duplicate.
  bool alreadyHas(String videoId, String qualityLabel, {required bool audioOnly}) {
    return _box.values.any((t) =>
        t.videoId == videoId &&
        t.qualityLabel == qualityLabel &&
        t.isAudioOnly == audioOnly &&
        t.status == DownloadStatus.completed);
  }

  Future<void> put(DownloadTask task) => _box.put(task.id, task);

  Future<void> delete(String id) => _box.delete(id);

  Stream<void> watch() => _box.watch().map((_) {});

  /// Hive's own listenable, for widgets that want to rebuild on any change
  /// without going through Riverpod.
  ValueListenable<Box<DownloadTask>> listenable() => _box.listenable();
}
