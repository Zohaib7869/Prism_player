import 'package:hive_flutter/hive_flutter.dart';

import '../core/database/hive_boxes.dart';
import '../models/eq_settings_model.dart';

/// Persists the single current EqSettingsModel (equalizer bands, bass boost,
/// virtualizer, volume boost) and is the source of truth GlobalPlayerController
/// re-applies to the native AudioEffectsPlugin every time it attaches to a
/// fresh Android audio session (sessions don't survive across playback starts).
class EqSettingsRepository {
  static const _key = 'current';

  Box<EqSettingsModel> get _box => Hive.box<EqSettingsModel>(HiveBoxes.eqSettings);

  EqSettingsModel get current => _box.get(_key) ?? EqSettingsModel();

  Future<void> save(EqSettingsModel model) => _box.put(_key, model);
}
