import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'aesthetic_themes.dart';

/// The set of built-in theme identities. [custom] lets the user pick their own
/// accent color while keeping either a dark or light base.
/// NOTE: values are persisted by index, so new themes must only ever be
/// appended to the end of this enum — never inserted or reordered.
enum AppThemeType {
  midnight,
  amoled,
  ocean,
  purple,
  light,
  custom,
  aurora,
  sunset,
  emerald,
  crimson,
  roseQuartz,
  // --- Image-backed themes (wallpaper backgrounds) ---
  nebula,
  neonCity,
  forestMist,
  desertMoon,
  glacier,
  ember,
  blueRidge,
  obsidian,
  auroraLake,
  abyss,
  sakuraNight,
  retrowave,
  // --- Dark automotive themes ---
  nightDrive,
  carbonApex,
  chromeDrift,
  redlineGt,
  // --- Anime themes ---
  animeSkyline,
  animeAlley,
  animeMecha,
  animeSpirit,
  // --- Aesthetic wallpaper packs (Cars / Anime / Girls / Boys) ---
  // Palettes + labels for these live in aesthetic_themes.dart.
  carMidnightSupercar,
  carNeonRacing,
  carLuxurySedan,
  carRedSports,
  carBlueJdm,
  carCyberpunk,
  carDesertDrive,
  carRainyCity,
  carBlackGold,
  carElectric,
  animeNeonCity,
  animeSamuraiNight,
  animeCyberpunk,
  animeSunset,
  animeRainyStreet,
  animeRooftop,
  animeMoonlight,
  animeFantasyForest,
  animeSakuraNight,
  animeNeonTokyo,
  girlPinkNeon,
  girlSoftPink,
  girlLuxury,
  girlDarkFeminine,
  girlPurpleDream,
  girlSunsetSilhouette,
  girlButterfly,
  girlFloralNight,
  girlPinkCityLights,
  girlBlackRose,
  boyDarkAlpha,
  boyBlackRed,
  boyMidnightMan,
  boyUrbanNight,
  boyStreetwear,
  boyLoneWolf,
  boyDarkLuxury,
  boyBlueNeon,
  boyMountainWarrior,
  boyBlackGoldExec,
}

extension AppThemeTypeX on AppThemeType {
  String get label {
    switch (this) {
      case AppThemeType.midnight:
        return 'Midnight';
      case AppThemeType.amoled:
        return 'AMOLED';
      case AppThemeType.ocean:
        return 'Ocean';
      case AppThemeType.purple:
        return 'Purple';
      case AppThemeType.light:
        return 'Light';
      case AppThemeType.custom:
        return 'Custom';
      case AppThemeType.aurora:
        return 'Aurora';
      case AppThemeType.sunset:
        return 'Sunset';
      case AppThemeType.emerald:
        return 'Emerald';
      case AppThemeType.crimson:
        return 'Crimson';
      case AppThemeType.roseQuartz:
        return 'Rose Quartz';
      case AppThemeType.nebula:
        return 'Nebula';
      case AppThemeType.neonCity:
        return 'Neon City';
      case AppThemeType.forestMist:
        return 'Forest Mist';
      case AppThemeType.desertMoon:
        return 'Desert Moon';
      case AppThemeType.glacier:
        return 'Glacier';
      case AppThemeType.ember:
        return 'Ember';
      case AppThemeType.blueRidge:
        return 'Blue Ridge';
      case AppThemeType.obsidian:
        return 'Obsidian';
      case AppThemeType.auroraLake:
        return 'Aurora Lake';
      case AppThemeType.abyss:
        return 'Abyss';
      case AppThemeType.sakuraNight:
        return 'Sakura Night';
      case AppThemeType.retrowave:
        return 'Retrowave';
      case AppThemeType.nightDrive:
        return 'Night Drive';
      case AppThemeType.carbonApex:
        return 'Carbon Apex';
      case AppThemeType.chromeDrift:
        return 'Chrome Drift';
      case AppThemeType.redlineGt:
        return 'Redline GT';
      case AppThemeType.animeSkyline:
        return 'Anime Skyline';
      case AppThemeType.animeAlley:
        return 'Neon Alley';
      case AppThemeType.animeMecha:
        return 'Mecha Core';
      case AppThemeType.animeSpirit:
        return 'Spirit Shrine';
      default:
        return AestheticThemes.labels[this] ?? name;
    }
  }

  /// True when this theme paints a photographic wallpaper behind the UI.
  bool get hasImage => PrismThemes.paletteFor(this).backgroundImage != null;

  /// Scenery wallpaper themes (the original image set).
  static const List<AppThemeType> sceneryThemes = [
    AppThemeType.nebula,
    AppThemeType.neonCity,
    AppThemeType.forestMist,
    AppThemeType.desertMoon,
    AppThemeType.glacier,
    AppThemeType.ember,
    AppThemeType.blueRidge,
    AppThemeType.obsidian,
    AppThemeType.auroraLake,
    AppThemeType.abyss,
    AppThemeType.sakuraNight,
    AppThemeType.retrowave,
  ];

  /// Every image-backed "wallpaper" theme, grouped scenery -> cars -> anime.
  static const List<AppThemeType> imageThemes = [
    ...sceneryThemes,
    ...carThemes,
    ...animeThemes,
    ...AestheticThemes.all,
  ];

  /// Dark automotive wallpaper themes.
  static const List<AppThemeType> carThemes = [
    AppThemeType.nightDrive,
    AppThemeType.carbonApex,
    AppThemeType.chromeDrift,
    AppThemeType.redlineGt,
  ];

  /// Anime wallpaper themes.
  static const List<AppThemeType> animeThemes = [
    AppThemeType.animeSkyline,
    AppThemeType.animeAlley,
    AppThemeType.animeMecha,
    AppThemeType.animeSpirit,
  ];

  /// Aesthetic wallpaper packs.
  static const List<AppThemeType> carsAesthetic = AestheticThemes.cars;
  static const List<AppThemeType> animeAesthetic = AestheticThemes.anime;
  static const List<AppThemeType> feminineAesthetic = AestheticThemes.feminine;
  static const List<AppThemeType> masculineAesthetic = AestheticThemes.masculine;

  /// Every wallpaper theme grouped by category, ready for the settings UI.
  static const List<(String, List<AppThemeType>)> wallpaperCategories = [
    ('Classic wallpapers', sceneryThemes),
    ('Cars', AestheticThemes.cars),
    ('Anime', AestheticThemes.anime),
    ('Feminine', AestheticThemes.feminine),
    ('Masculine', AestheticThemes.masculine),
    ('Originals', [...carThemes, ...animeThemes]),
  ];

  /// Themes offered in Appearance settings (everything except [custom],
  /// which is driven by the accent-color picker).
  static const List<AppThemeType> selectable = [
    AppThemeType.midnight,
    AppThemeType.aurora,
    AppThemeType.amoled,
    AppThemeType.ocean,
    AppThemeType.purple,
    AppThemeType.sunset,
    AppThemeType.emerald,
    AppThemeType.crimson,
    AppThemeType.roseQuartz,
    AppThemeType.light,
  ];
}

/// A fully-resolved palette for one theme. Every screen pulls its colors from
/// `Theme.of(context).extension<PrismPalette>()` (or the standard ColorScheme
/// fields it feeds) — nothing in feature code should hard-code a Color.
@immutable
class PrismPalette extends ThemeExtension<PrismPalette> {
  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color accent;
  final Color accentSecondary;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color error;
  final Color divider;
  final bool isDark;

  /// Three-stop vertical gradient painted behind every screen by
  /// [PrismBackground]. Empty means "flat [background]".
  final List<Color> gradient;

  /// Two soft radial glows layered over the gradient for depth.
  final Color? glowPrimary;
  final Color? glowSecondary;

  /// Optional full-screen wallpaper asset painted behind the UI by
  /// [PrismBackground]. Null means "gradient + glows only".
  final String? backgroundImage;

  /// 0..1 scrim strength applied over [backgroundImage] so text stays legible.
  final double imageDim;

  const PrismPalette({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.accent,
    required this.accentSecondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.error,
    required this.divider,
    required this.isDark,
    this.gradient = const [],
    this.glowPrimary,
    this.glowSecondary,
    this.backgroundImage,
    this.imageDim = 0.55,
  });

  /// Gradient stops guaranteed to have at least two entries.
  List<Color> get backgroundStops =>
      gradient.length >= 2 ? gradient : [background, background];

  Color get glowA => glowPrimary ?? accent.withOpacity(isDark ? 0.22 : 0.12);
  Color get glowB => glowSecondary ?? accentSecondary.withOpacity(isDark ? 0.18 : 0.10);

  /// Frosted card fill used by the premium "glass" surfaces.
  Color get glass => surface.withOpacity(isDark ? 0.62 : 0.86);
  Color get glassBorder => (isDark ? Colors.white : Colors.black).withOpacity(isDark ? 0.07 : 0.05);

  @override
  PrismPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? accent,
    Color? accentSecondary,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? success,
    Color? warning,
    Color? error,
    Color? divider,
    bool? isDark,
    List<Color>? gradient,
    Color? glowPrimary,
    Color? glowSecondary,
    String? backgroundImage,
    double? imageDim,
  }) {
    return PrismPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      accent: accent ?? this.accent,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      divider: divider ?? this.divider,
      isDark: isDark ?? this.isDark,
      gradient: gradient ?? this.gradient,
      glowPrimary: glowPrimary ?? this.glowPrimary,
      glowSecondary: glowSecondary ?? this.glowSecondary,
      backgroundImage: backgroundImage ?? this.backgroundImage,
      imageDim: imageDim ?? this.imageDim,
    );
  }

  @override
  PrismPalette lerp(ThemeExtension<PrismPalette>? other, double t) {
    if (other is! PrismPalette) return this;
    return PrismPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
      gradient: t < 0.5 ? gradient : other.gradient,
      glowPrimary: Color.lerp(glowA, other.glowA, t),
      glowSecondary: Color.lerp(glowB, other.glowB, t),
      backgroundImage: t < 0.5 ? backgroundImage : other.backgroundImage,
      imageDim: (imageDim + (other.imageDim - imageDim) * t),
    );
  }
}

class PrismThemes {
  PrismThemes._();

  static const PrismPalette midnight = PrismPalette(
    background: Color(0xFF0E1016),
    surface: Color(0xFF161923),
    surfaceElevated: Color(0xFF1E2230),
    accent: Color(0xFF6C8CFF),
    accentSecondary: Color(0xFF9D7BFF),
    textPrimary: Color(0xFFF2F3F7),
    textSecondary: Color(0xFFAEB3C2),
    textMuted: Color(0xFF6B7080),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF262B3A),
    isDark: true,
    gradient: [Color(0xFF11141F), Color(0xFF0E1016), Color(0xFF090B12)],
    glowPrimary: Color(0x336C8CFF),
    glowSecondary: Color(0x2A9D7BFF),
  );

  static const PrismPalette amoled = PrismPalette(
    background: Color(0xFF000000),
    surface: Color(0xFF0A0A0A),
    surfaceElevated: Color(0xFF141414),
    accent: Color(0xFF00E5A0),
    accentSecondary: Color(0xFF5CE1FF),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB0B0B0),
    textMuted: Color(0xFF636363),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF1E1E1E),
    isDark: true,
    gradient: [Color(0xFF060606), Color(0xFF000000), Color(0xFF000000)],
    glowPrimary: Color(0x2600E5A0),
    glowSecondary: Color(0x1F5CE1FF),
  );

  static const PrismPalette ocean = PrismPalette(
    background: Color(0xFF071B26),
    surface: Color(0xFF0E2836),
    surfaceElevated: Color(0xFF163847),
    accent: Color(0xFF32C9D8),
    accentSecondary: Color(0xFF3E8FE0),
    textPrimary: Color(0xFFEAF6F8),
    textSecondary: Color(0xFFA6C4CC),
    textMuted: Color(0xFF5F808A),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFC15E),
    error: Color(0xFFFF6B6B),
    divider: Color(0xFF1B3948),
    isDark: true,
    gradient: [Color(0xFF07222F), Color(0xFF061923), Color(0xFF03111A)],
    glowPrimary: Color(0x3332C9D8),
    glowSecondary: Color(0x2A3E8FE0),
  );

  static const PrismPalette purple = PrismPalette(
    background: Color(0xFF140B26),
    surface: Color(0xFF1E1236),
    surfaceElevated: Color(0xFF2A1A47),
    accent: Color(0xFFB388FF),
    accentSecondary: Color(0xFFFF7BD5),
    textPrimary: Color(0xFFF4EEFF),
    textSecondary: Color(0xFFC2AEE0),
    textMuted: Color(0xFF7C6899),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF6B9E),
    divider: Color(0xFF32204F),
    isDark: true,
    gradient: [Color(0xFF1B0E31), Color(0xFF140B26), Color(0xFF0C0619)],
    glowPrimary: Color(0x38B388FF),
    glowSecondary: Color(0x2EFF7BD5),
  );

  static const PrismPalette light = PrismPalette(
    background: Color(0xFFF7F8FB),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    accent: Color(0xFF4A63E7),
    accentSecondary: Color(0xFF7C4DE0),
    textPrimary: Color(0xFF14161F),
    textSecondary: Color(0xFF565B6B),
    textMuted: Color(0xFF8B90A0),
    success: Color(0xFF2AA85C),
    warning: Color(0xFFE08A1E),
    error: Color(0xFFE0364A),
    divider: Color(0xFFE6E8F0),
    isDark: false,
    gradient: [Color(0xFFFFFFFF), Color(0xFFF5F7FC), Color(0xFFEDF1F9)],
    glowPrimary: Color(0x1A4A63E7),
    glowSecondary: Color(0x147C4DE0),
  );

  /// Deep teal-to-indigo night sky with a shimmering green aurora accent.
  static const PrismPalette aurora = PrismPalette(
    background: Color(0xFF08131C),
    surface: Color(0xFF102030),
    surfaceElevated: Color(0xFF17293C),
    accent: Color(0xFF43F5C0),
    accentSecondary: Color(0xFF7C9BFF),
    textPrimary: Color(0xFFEFFBF8),
    textSecondary: Color(0xFFA9C2C8),
    textMuted: Color(0xFF64808C),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFC15E),
    error: Color(0xFFFF6B7A),
    divider: Color(0xFF1B3346),
    isDark: true,
    gradient: [Color(0xFF0B2233), Color(0xFF08131C), Color(0xFF050C13)],
    glowPrimary: Color(0x3C43F5C0),
    glowSecondary: Color(0x387C9BFF),
  );

  /// Warm dusk: burnt amber over deep plum. Cinematic and premium.
  static const PrismPalette sunset = PrismPalette(
    background: Color(0xFF17101A),
    surface: Color(0xFF221726),
    surfaceElevated: Color(0xFF2E1F33),
    accent: Color(0xFFFF9448),
    accentSecondary: Color(0xFFFF5F87),
    textPrimary: Color(0xFFFDF1EA),
    textSecondary: Color(0xFFD3B6B4),
    textMuted: Color(0xFF8C6E77),
    success: Color(0xFF5AD98F),
    warning: Color(0xFFFFC15E),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF3A2740),
    isDark: true,
    gradient: [Color(0xFF2A1524), Color(0xFF17101A), Color(0xFF0D080F)],
    glowPrimary: Color(0x40FF9448),
    glowSecondary: Color(0x33FF5F87),
  );

  /// Forest emerald with brushed-gold highlights — the "luxury" theme.
  static const PrismPalette emerald = PrismPalette(
    background: Color(0xFF07160F),
    surface: Color(0xFF0E241A),
    surfaceElevated: Color(0xFF143223),
    accent: Color(0xFF2FD98C),
    accentSecondary: Color(0xFFD9B45C),
    textPrimary: Color(0xFFEDF9F1),
    textSecondary: Color(0xFFA8C6B4),
    textMuted: Color(0xFF5F8271),
    success: Color(0xFF3FE08F),
    warning: Color(0xFFE8BA5A),
    error: Color(0xFFFF6B6B),
    divider: Color(0xFF1A3A28),
    isDark: true,
    gradient: [Color(0xFF0A2317), Color(0xFF07160F), Color(0xFF040D09)],
    glowPrimary: Color(0x382FD98C),
    glowSecondary: Color(0x2ED9B45C),
  );

  /// Near-black graphite with a bold crimson accent.
  static const PrismPalette crimson = PrismPalette(
    background: Color(0xFF130B0D),
    surface: Color(0xFF1D1215),
    surfaceElevated: Color(0xFF2A181D),
    accent: Color(0xFFFF4D6D),
    accentSecondary: Color(0xFFFFA24D),
    textPrimary: Color(0xFFFBEFF1),
    textSecondary: Color(0xFFCFB2B8),
    textMuted: Color(0xFF8A6A72),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF3A2129),
    isDark: true,
    gradient: [Color(0xFF251016), Color(0xFF130B0D), Color(0xFF0A0507)],
    glowPrimary: Color(0x40FF4D6D),
    glowSecondary: Color(0x2EFFA24D),
  );

  /// Soft light theme with blush-pink and lavender wash.
  static const PrismPalette roseQuartz = PrismPalette(
    background: Color(0xFFFDF7F9),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    accent: Color(0xFFE0577F),
    accentSecondary: Color(0xFF9B72CF),
    textPrimary: Color(0xFF221822),
    textSecondary: Color(0xFF60505C),
    textMuted: Color(0xFF988A94),
    success: Color(0xFF2AA85C),
    warning: Color(0xFFD98A24),
    error: Color(0xFFD93A54),
    divider: Color(0xFFF0E3EA),
    isDark: false,
    gradient: [Color(0xFFFFFFFF), Color(0xFFFDF3F7), Color(0xFFF4EAF6)],
    glowPrimary: Color(0x1FE0577F),
    glowSecondary: Color(0x1A9B72CF),
  );


  /// Deep-space nebula wallpaper: violet gas clouds over near-black sky.
  static const PrismPalette nebula = PrismPalette(
    background: Color(0xFF0A0714),
    surface: Color(0xFF150F26),
    surfaceElevated: Color(0xFF1E1636),
    accent: Color(0xFFB98CFF),
    accentSecondary: Color(0xFF6FA8FF),
    textPrimary: Color(0xFFF3EEFF),
    textSecondary: Color(0xFFBBAFD4),
    textMuted: Color(0xFF7A6E96),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF2A2044),
    isDark: true,
    gradient: [Color(0xCC0B0818), Color(0xB3080512), Color(0xE605030B)],
    glowPrimary: Color(0x38B98CFF),
    glowSecondary: Color(0x2A6FA8FF),
    backgroundImage: 'assets/themes/nebula.jpg',
    imageDim: 0.5,
  );

  /// Rain-soaked neon street at night: magenta and cyan reflections.
  static const PrismPalette neonCity = PrismPalette(
    background: Color(0xFF0B0710),
    surface: Color(0xFF16101C),
    surfaceElevated: Color(0xFF211729),
    accent: Color(0xFFFF3D9A),
    accentSecondary: Color(0xFF35E0FF),
    textPrimary: Color(0xFFFDEFF8),
    textSecondary: Color(0xFFCBAEC2),
    textMuted: Color(0xFF897290),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF33203C),
    isDark: true,
    gradient: [Color(0xCC120A18), Color(0xA30C0712), Color(0xE6070409)],
    glowPrimary: Color(0x40FF3D9A),
    glowSecondary: Color(0x3335E0FF),
    backgroundImage: 'assets/themes/night_city.jpg',
    imageDim: 0.58,
  );

  /// Foggy night pine forest in deep teal-green.
  static const PrismPalette forestMist = PrismPalette(
    background: Color(0xFF05100E),
    surface: Color(0xFF0C1B18),
    surfaceElevated: Color(0xFF122622),
    accent: Color(0xFF57D9B0),
    accentSecondary: Color(0xFF8FBF7A),
    textPrimary: Color(0xFFE9F6F2),
    textSecondary: Color(0xFFA6C2BB),
    textMuted: Color(0xFF63817B),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF17322C),
    isDark: true,
    gradient: [Color(0xCC07130F), Color(0xB3050D0B), Color(0xE6030807)],
    glowPrimary: Color(0x3357D9B0),
    glowSecondary: Color(0x2A8FBF7A),
    backgroundImage: 'assets/themes/forest_mist.jpg',
    imageDim: 0.48,
  );

  /// Moonlit dunes: warm sand over a deep navy night sky.
  static const PrismPalette desertMoon = PrismPalette(
    background: Color(0xFF080D18),
    surface: Color(0xFF111827),
    surfaceElevated: Color(0xFF1A2334),
    accent: Color(0xFFF2B45C),
    accentSecondary: Color(0xFF6E9BD8),
    textPrimary: Color(0xFFFBF3E7),
    textSecondary: Color(0xFFC9BCA9),
    textMuted: Color(0xFF877C6C),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF24304A),
    isDark: true,
    gradient: [Color(0xCC0A1220), Color(0xA3070C16), Color(0xE604070E)],
    glowPrimary: Color(0x3AF2B45C),
    glowSecondary: Color(0x2E6E9BD8),
    backgroundImage: 'assets/themes/desert_night.jpg',
    imageDim: 0.45,
  );

  /// Moonlit arctic ice field in cold electric blue.
  static const PrismPalette glacier = PrismPalette(
    background: Color(0xFF04101C),
    surface: Color(0xFF0B1C2E),
    surfaceElevated: Color(0xFF12263C),
    accent: Color(0xFF52C7FF),
    accentSecondary: Color(0xFF9FE8FF),
    textPrimary: Color(0xFFEAF6FF),
    textSecondary: Color(0xFFA9C4D8),
    textMuted: Color(0xFF62809A),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF163350),
    isDark: true,
    gradient: [Color(0xCC061626), Color(0xB3040F1C), Color(0xE6020810)],
    glowPrimary: Color(0x3852C7FF),
    glowSecondary: Color(0x2A9FE8FF),
    backgroundImage: 'assets/themes/glacier.jpg',
    imageDim: 0.5,
  );

  /// Glowing lava cracks in black volcanic rock.
  static const PrismPalette ember = PrismPalette(
    background: Color(0xFF0C0605),
    surface: Color(0xFF170B09),
    surfaceElevated: Color(0xFF23110D),
    accent: Color(0xFFFF6A2C),
    accentSecondary: Color(0xFFFFC24D),
    textPrimary: Color(0xFFFCEDE6),
    textSecondary: Color(0xFFCFB0A4),
    textMuted: Color(0xFF8A6A5E),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF351A14),
    isDark: true,
    gradient: [Color(0xCC140806), Color(0xB30C0504), Color(0xE6070302)],
    glowPrimary: Color(0x40FF6A2C),
    glowSecondary: Color(0x2EFFC24D),
    backgroundImage: 'assets/themes/ember.jpg',
    imageDim: 0.55,
  );

  /// Layered mountain ridges at blue hour.
  static const PrismPalette blueRidge = PrismPalette(
    background: Color(0xFF050B14),
    surface: Color(0xFF0C1522),
    surfaceElevated: Color(0xFF131F30),
    accent: Color(0xFF5B9BFF),
    accentSecondary: Color(0xFF7ED8E6),
    textPrimary: Color(0xFFEAF1FA),
    textSecondary: Color(0xFFAAB9CC),
    textMuted: Color(0xFF64748C),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF1A2739),
    isDark: true,
    gradient: [Color(0xCC071021), Color(0xB3040A15), Color(0xE602060D)],
    glowPrimary: Color(0x385B9BFF),
    glowSecondary: Color(0x2A7ED8E6),
    backgroundImage: 'assets/themes/mountains.jpg',
    imageDim: 0.42,
  );

  /// Liquid-black chrome texture. Pure stealth.
  static const PrismPalette obsidian = PrismPalette(
    background: Color(0xFF050505),
    surface: Color(0xFF0E0E0F),
    surfaceElevated: Color(0xFF171718),
    accent: Color(0xFFDCDCE0),
    accentSecondary: Color(0xFF8E8E96),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB4B4BB),
    textMuted: Color(0xFF6E6E76),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF1F1F21),
    isDark: true,
    gradient: [Color(0xCC0A0A0B), Color(0xB3060606), Color(0xE6020202)],
    glowPrimary: Color(0x26DCDCE0),
    glowSecondary: Color(0x1F8E8E96),
    backgroundImage: 'assets/themes/chrome_wave.jpg',
    imageDim: 0.52,
  );

  /// Northern lights mirrored on a frozen lake.
  static const PrismPalette auroraLake = PrismPalette(
    background: Color(0xFF04120F),
    surface: Color(0xFF0A1F1B),
    surfaceElevated: Color(0xFF102B26),
    accent: Color(0xFF2FEFA8),
    accentSecondary: Color(0xFF56C8FF),
    textPrimary: Color(0xFFE9FFF7),
    textSecondary: Color(0xFFA5C9BE),
    textMuted: Color(0xFF5F847A),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF14342C),
    isDark: true,
    gradient: [Color(0xCC061A15), Color(0xB304120F), Color(0xE6020A08)],
    glowPrimary: Color(0x3C2FEFA8),
    glowSecondary: Color(0x2E56C8FF),
    backgroundImage: 'assets/themes/aurora_lake.jpg',
    imageDim: 0.5,
  );

  /// Deep-sea light shafts fading into black water.
  static const PrismPalette abyss = PrismPalette(
    background: Color(0xFF030B0F),
    surface: Color(0xFF08161C),
    surfaceElevated: Color(0xFF0D2028),
    accent: Color(0xFF2FD6D0),
    accentSecondary: Color(0xFF3E8FE0),
    textPrimary: Color(0xFFE7FAFB),
    textSecondary: Color(0xFF9DBCC2),
    textMuted: Color(0xFF5C7B82),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF112B33),
    isDark: true,
    gradient: [Color(0xCC041017), Color(0xB302090E), Color(0xE6010507)],
    glowPrimary: Color(0x382FD6D0),
    glowSecondary: Color(0x2A3E8FE0),
    backgroundImage: 'assets/themes/abyss.jpg',
    imageDim: 0.5,
  );

  /// Moonlit zen garden with a pale sakura branch.
  static const PrismPalette sakuraNight = PrismPalette(
    background: Color(0xFF060912),
    surface: Color(0xFF10141F),
    surfaceElevated: Color(0xFF191E2C),
    accent: Color(0xFFFF9EC4),
    accentSecondary: Color(0xFFA9C4FF),
    textPrimary: Color(0xFFF6F1F8),
    textSecondary: Color(0xFFBEB6C8),
    textMuted: Color(0xFF7A7488),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF232939),
    isDark: true,
    gradient: [Color(0xCC080C18), Color(0xB305080F), Color(0xE6030509)],
    glowPrimary: Color(0x33FF9EC4),
    glowSecondary: Color(0x2AA9C4FF),
    backgroundImage: 'assets/themes/sakura_night.jpg',
    imageDim: 0.46,
  );

  /// Synthwave sun sinking into a dark horizon.
  static const PrismPalette retrowave = PrismPalette(
    background: Color(0xFF0A0413),
    surface: Color(0xFF150A22),
    surfaceElevated: Color(0xFF20102F),
    accent: Color(0xFFFF2E7E),
    accentSecondary: Color(0xFF8A5CFF),
    textPrimary: Color(0xFFFCE9F3),
    textSecondary: Color(0xFFC9A7BE),
    textMuted: Color(0xFF836A82),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF2E1740),
    isDark: true,
    gradient: [Color(0xCC110620), Color(0xA30A0415), Color(0xE605020B)],
    glowPrimary: Color(0x40FF2E7E),
    glowSecondary: Color(0x338A5CFF),
    backgroundImage: 'assets/themes/retrowave.jpg',
    imageDim: 0.5,
  );

  /// Builds a custom palette from a single accent color chosen by the user,
  /// keeping either the Midnight (dark) or Light base depending on [isDark].
  static PrismPalette custom(Color accent, {required bool isDark}) {
    final base = isDark ? midnight : light;
    final secondary = HSLColor.fromColor(accent)
        .withHue((HSLColor.fromColor(accent).hue + 35) % 360)
        .toColor();
    return base.copyWith(
      accent: accent,
      accentSecondary: secondary,
      // Tint the base gradient's top stop with the chosen accent so a custom
      // accent still produces the same premium layered background.
      gradient: [
        Color.lerp(base.backgroundStops.first, accent, isDark ? 0.12 : 0.05)!,
        base.backgroundStops[1],
        base.backgroundStops.last,
      ],
      glowPrimary: accent.withOpacity(isDark ? 0.22 : 0.10),
      glowSecondary: secondary.withOpacity(isDark ? 0.18 : 0.08),
    );
  }

  // ---------------------------------------------------------------------
  // Dark automotive themes
  // ---------------------------------------------------------------------

  static const PrismPalette nightDrive = PrismPalette(
    background: Color(0xFF04070A),
    surface: Color(0xFF0B1218),
    surfaceElevated: Color(0xFF121C24),
    accent: Color(0xFF35E0E0),
    accentSecondary: Color(0xFFFFA53D),
    textPrimary: Color(0xFFE9F4F6),
    textSecondary: Color(0xFFA6B9C0),
    textMuted: Color(0xFF6A7C84),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF16242D),
    isDark: true,
    gradient: [Color(0xB3040A0F), Color(0x99030608), Color(0xE6010304)],
    glowPrimary: Color(0x4035E0E0),
    glowSecondary: Color(0x26FFA53D),
    backgroundImage: 'assets/themes/night_drive.jpg',
    imageDim: 0.42,
  );

  static const PrismPalette carbonApex = PrismPalette(
    background: Color(0xFF050505),
    surface: Color(0xFF0E0E10),
    surfaceElevated: Color(0xFF17171A),
    accent: Color(0xFFFF7A18),
    accentSecondary: Color(0xFFB0B7BF),
    textPrimary: Color(0xFFF1F1F2),
    textSecondary: Color(0xFFB2B3B7),
    textMuted: Color(0xFF6E7076),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF1E1F23),
    isDark: true,
    gradient: [Color(0xB3070707), Color(0x99050505), Color(0xE6000000)],
    glowPrimary: Color(0x40FF7A18),
    glowSecondary: Color(0x1FB0B7BF),
    backgroundImage: 'assets/themes/carbon_apex.jpg',
    imageDim: 0.4,
  );

  static const PrismPalette chromeDrift = PrismPalette(
    background: Color(0xFF05080C),
    surface: Color(0xFF0D131A),
    surfaceElevated: Color(0xFF161E27),
    accent: Color(0xFF8FD3FF),
    accentSecondary: Color(0xFFDCE6F0),
    textPrimary: Color(0xFFEDF3F9),
    textSecondary: Color(0xFFAFBECC),
    textMuted: Color(0xFF6E7E8C),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF1A242F),
    isDark: true,
    gradient: [Color(0xB3060B11), Color(0x9904080C), Color(0xE6010305)],
    glowPrimary: Color(0x408FD3FF),
    glowSecondary: Color(0x1FDCE6F0),
    backgroundImage: 'assets/themes/chrome_drift.jpg',
    imageDim: 0.45,
  );

  static const PrismPalette redlineGt = PrismPalette(
    background: Color(0xFF070304),
    surface: Color(0xFF130809),
    surfaceElevated: Color(0xFF1D0C0E),
    accent: Color(0xFFFF3B30),
    accentSecondary: Color(0xFFFF8A7A),
    textPrimary: Color(0xFFF6E9E9),
    textSecondary: Color(0xFFC0A5A5),
    textMuted: Color(0xFF7E6667),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF2A1214),
    isDark: true,
    gradient: [Color(0xB30B0405), Color(0x99070203), Color(0xE6030101)],
    glowPrimary: Color(0x40FF3B30),
    glowSecondary: Color(0x26FF8A7A),
    backgroundImage: 'assets/themes/redline_gt.jpg',
    imageDim: 0.42,
  );

  // ---------------------------------------------------------------------
  // Anime themes
  // ---------------------------------------------------------------------

  static const PrismPalette animeSkyline = PrismPalette(
    background: Color(0xFF08061A),
    surface: Color(0xFF120E2B),
    surfaceElevated: Color(0xFF1B1540),
    accent: Color(0xFFE85CFF),
    accentSecondary: Color(0xFF7C6CFF),
    textPrimary: Color(0xFFF1E9FF),
    textSecondary: Color(0xFFBCAEDC),
    textMuted: Color(0xFF7A6E9B),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF261C4D),
    isDark: true,
    gradient: [Color(0xB30C0824), Color(0x99080517), Color(0xE604020C)],
    glowPrimary: Color(0x40E85CFF),
    glowSecondary: Color(0x337C6CFF),
    backgroundImage: 'assets/themes/anime_skyline.jpg',
    imageDim: 0.45,
  );

  static const PrismPalette animeAlley = PrismPalette(
    background: Color(0xFF060A12),
    surface: Color(0xFF0E1622),
    surfaceElevated: Color(0xFF16202F),
    accent: Color(0xFFFFA83C),
    accentSecondary: Color(0xFF3ED9D3),
    textPrimary: Color(0xFFF0EDE6),
    textSecondary: Color(0xFFB6B3AC),
    textMuted: Color(0xFF75797F),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF1C2735),
    isDark: true,
    gradient: [Color(0xB3070C15), Color(0x9905090F), Color(0xE6020407)],
    glowPrimary: Color(0x40FFA83C),
    glowSecondary: Color(0x333ED9D3),
    backgroundImage: 'assets/themes/anime_alley.jpg',
    imageDim: 0.45,
  );

  static const PrismPalette animeMecha = PrismPalette(
    background: Color(0xFF04090F),
    surface: Color(0xFF0B141D),
    surfaceElevated: Color(0xFF131F2B),
    accent: Color(0xFF32D8FF),
    accentSecondary: Color(0xFF6E8FA8),
    textPrimary: Color(0xFFE8F3FA),
    textSecondary: Color(0xFFA8BCC9),
    textMuted: Color(0xFF6B7F8C),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF17242F),
    isDark: true,
    gradient: [Color(0xB3050C13), Color(0x9903080D), Color(0xE6010406)],
    glowPrimary: Color(0x4032D8FF),
    glowSecondary: Color(0x266E8FA8),
    backgroundImage: 'assets/themes/anime_mecha.jpg',
    imageDim: 0.44,
  );

  static const PrismPalette animeSpirit = PrismPalette(
    background: Color(0xFF04100E),
    surface: Color(0xFF0A1A18),
    surfaceElevated: Color(0xFF102523),
    accent: Color(0xFFFFD75E),
    accentSecondary: Color(0xFF3FBFA4),
    textPrimary: Color(0xFFEBF5F0),
    textSecondary: Color(0xFFA9C2B9),
    textMuted: Color(0xFF6B857C),
    success: Color(0xFF4CD97B),
    warning: Color(0xFFFFB84C),
    error: Color(0xFFFF5C6C),
    divider: Color(0xFF163029),
    isDark: true,
    gradient: [Color(0xB3051411), Color(0x99030E0C), Color(0xE6010605)],
    glowPrimary: Color(0x40FFD75E),
    glowSecondary: Color(0x333FBFA4),
    backgroundImage: 'assets/themes/anime_spirit.jpg',
    imageDim: 0.46,
  );

  static PrismPalette paletteFor(AppThemeType type, {Color? customAccent, bool customIsDark = true}) {
    switch (type) {
      case AppThemeType.midnight:
        return midnight;
      case AppThemeType.amoled:
        return amoled;
      case AppThemeType.ocean:
        return ocean;
      case AppThemeType.purple:
        return purple;
      case AppThemeType.light:
        return light;
      case AppThemeType.custom:
        return custom(customAccent ?? midnight.accent, isDark: customIsDark);
      case AppThemeType.aurora:
        return aurora;
      case AppThemeType.sunset:
        return sunset;
      case AppThemeType.emerald:
        return emerald;
      case AppThemeType.crimson:
        return crimson;
      case AppThemeType.roseQuartz:
        return roseQuartz;
      case AppThemeType.nebula:
        return nebula;
      case AppThemeType.neonCity:
        return neonCity;
      case AppThemeType.forestMist:
        return forestMist;
      case AppThemeType.desertMoon:
        return desertMoon;
      case AppThemeType.glacier:
        return glacier;
      case AppThemeType.ember:
        return ember;
      case AppThemeType.blueRidge:
        return blueRidge;
      case AppThemeType.obsidian:
        return obsidian;
      case AppThemeType.auroraLake:
        return auroraLake;
      case AppThemeType.abyss:
        return abyss;
      case AppThemeType.sakuraNight:
        return sakuraNight;
      case AppThemeType.retrowave:
        return retrowave;
      case AppThemeType.nightDrive:
        return nightDrive;
      case AppThemeType.carbonApex:
        return carbonApex;
      case AppThemeType.chromeDrift:
        return chromeDrift;
      case AppThemeType.redlineGt:
        return redlineGt;
      case AppThemeType.animeSkyline:
        return animeSkyline;
      case AppThemeType.animeAlley:
        return animeAlley;
      case AppThemeType.animeMecha:
        return animeMecha;
      case AppThemeType.animeSpirit:
        return animeSpirit;
      default:
        return AestheticThemes.palettes[type] ?? midnight;
    }
  }

  static ThemeData buildThemeData(PrismPalette p) {
    final brightness = p.isDark ? Brightness.dark : Brightness.light;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: p.accent,
      onPrimary: p.isDark ? Colors.black : Colors.white,
      secondary: p.accentSecondary,
      onSecondary: p.isDark ? Colors.black : Colors.white,
      error: p.error,
      onError: Colors.white,
      surface: p.surface,
      onSurface: p.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      // Transparent so the shared [PrismBackground] gradient (installed once in
      // MaterialApp.builder) shows through every screen instead of each Scaffold
      // painting a flat color over it.
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      dividerColor: p.divider,
      splashFactory: InkSparkle.splashFactory,
      fontFamily: 'Roboto',
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle:
            p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: p.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.glass,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.glassBorder),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.isDark ? Colors.black : Colors.white,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.isDark ? Colors.black : Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.accent),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface.withOpacity(p.isDark ? 0.94 : 0.96),
        selectedItemColor: p.accent,
        unselectedItemColor: p.textMuted,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surfaceElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: p.divider,
        thumbColor: p.accent,
        overlayColor: p.accent.withOpacity(0.15),
        trackHeight: 3,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceElevated,
        selectedColor: p.accent.withOpacity(0.2),
        labelStyle: TextStyle(color: p.textPrimary),
        side: BorderSide(color: p.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
      iconTheme: IconThemeData(color: p.textPrimary),
      textTheme: Typography.material2021(platform: TargetPlatform.android)
          .white
          .apply(
            bodyColor: p.textPrimary,
            displayColor: p.textPrimary,
          )
          .copyWith(
            titleLarge: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
            titleMedium: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600),
            bodyMedium: TextStyle(color: p.textSecondary),
            bodySmall: TextStyle(color: p.textMuted),
          ),
      extensions: [p],
    );
  }
}
