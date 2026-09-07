enum FolderMediaType { video, audio, mixed }

/// A folder as shown in the Folders tab — computed on the fly by aggregating
/// VideoModel/AudioModel rows that share a folderPath, never persisted itself.
class FolderSummary {
  final String path;
  final String name;
  final int videoCount;
  final int audioCount;
  final int totalSizeBytes;
  final String? previewThumbnailPath;
  final bool isHidden;

  const FolderSummary({
    required this.path,
    required this.name,
    required this.videoCount,
    required this.audioCount,
    required this.totalSizeBytes,
    this.previewThumbnailPath,
    this.isHidden = false,
  });

  FolderMediaType get type {
    if (videoCount > 0 && audioCount > 0) return FolderMediaType.mixed;
    return videoCount > 0 ? FolderMediaType.video : FolderMediaType.audio;
  }

  int get totalCount => videoCount + audioCount;
}
