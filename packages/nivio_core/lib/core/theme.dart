import 'package:flutter/material.dart';
import 'package:nivio/core/app_platform.dart';

/// Representation of an entire app theme palette
class NivioAppTheme {
  final String key;
  final String label;
  final String description;
  final Color scaffoldBackgroundColor;
  final Color surface;
  final Color surfaceContainer;
  final Color primary;
  final Color secondary;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final List<Color> gradientColors;

  const NivioAppTheme({
    required this.key,
    required this.label,
    required this.description,
    required this.scaffoldBackgroundColor,
    required this.surface,
    required this.surfaceContainer,
    required this.primary,
    required this.secondary,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.gradientColors,
  });
}

/// ThemeExtension to expose semantic Nivio colors anywhere in the widget tree
class NivioThemeColors extends ThemeExtension<NivioThemeColors> {
  final Color background;
  final Color surface;
  final Color surfaceContainer;
  final Color primary;
  final Color secondary;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final LinearGradient backgroundGradient;

  const NivioThemeColors({
    required this.background,
    required this.surface,
    required this.surfaceContainer,
    required this.primary,
    required this.secondary,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.backgroundGradient,
  });

  @override
  NivioThemeColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceContainer,
    Color? primary,
    Color? secondary,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    LinearGradient? backgroundGradient,
  }) {
    return NivioThemeColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
    );
  }

  @override
  NivioThemeColors lerp(ThemeExtension<NivioThemeColors>? other, double t) {
    if (other is! NivioThemeColors) return this;
    return NivioThemeColors(
      background: Color.lerp(background, other.background, t) ?? background,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceContainer:
          Color.lerp(surfaceContainer, other.surfaceContainer, t) ??
          surfaceContainer,
      primary: Color.lerp(primary, other.primary, t) ?? primary,
      secondary: Color.lerp(secondary, other.secondary, t) ?? secondary,
      border: Color.lerp(border, other.border, t) ?? border,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      backgroundGradient:
          LinearGradient.lerp(
            backgroundGradient,
            other.backgroundGradient,
            t,
          ) ??
          backgroundGradient,
    );
  }
}

class NivioTheme {
  const NivioTheme._();

  // Legacy Nivio palette constants for backwards compatibility
  static const Color netflixRed = Color(0xFFE50914);
  static const Color netflixBlack = Color(0xFF0D0F14);
  static const Color netflixDarkGrey = Color(0xFF151922);
  static const Color netflixGrey = Color(0xFF7E8798);
  static const Color netflixLightGrey = Color(0xFFB7BECC);
  static const Color netflixWhite = Color(0xFFF6F8FF);
  static const Color glassFill = Color(0x33293246);
  static const Color glassStroke = Color(0x40FFFFFF);

  static const TextStyle sectionHeaderStyle = TextStyle(
    color: Colors.white70,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.2,
  );

  static const TextStyle pageHeaderStyle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w500,
  );

  // 1. Blackout (OLED pure black)
  static const blackoutTheme = NivioAppTheme(
    key: 'blackout',
    label: 'AMOLED Black',
    description: 'Pure black with neutral accents',
    scaffoldBackgroundColor: Color(0xFF000000),
    surface: Color(0xFF1A1A1A),
    surfaceContainer: Color(0xFF222222),
    primary: Color(0xFFF5F5F5),
    secondary: Color(0xFFE0E0E0),
    border: Color(0xFF252A2A),
    textPrimary: Color(0xFFF5F7F8),
    textSecondary: Color(0xFF969CA3),
    gradientColors: [Colors.black, Colors.black],
  );

  // 2. Monokai
  static const monokaiTheme = NivioAppTheme(
    key: 'monokai',
    label: 'Monokai',
    description: 'Classic code editor charcoal with vibrant green & orange',
    scaffoldBackgroundColor: Color(0xFF272822),
    surface: Color(0xFF1E1F1C),
    surfaceContainer: Color(0xFF383830),
    primary: Color(0xFFA6E22E),
    secondary: Color(0xFFFD971F),
    border: Color(0xFF49483E),
    textPrimary: Color(0xFFF8F8F2),
    textSecondary: Color(0xFF8F908A),
    gradientColors: [Color(0xFF34352D), Color(0xFF272822)],
  );

  // 3. Catppuccin (Mocha)
  static const catppuccinTheme = NivioAppTheme(
    key: 'catppuccin',
    label: 'Catppuccin',
    description: 'Soothing velvet dark theme with mauve & pastel accents',
    scaffoldBackgroundColor: Color(0xFF1E1E2E),
    surface: Color(0xFF313244),
    surfaceContainer: Color(0xFF181825),
    primary: Color(0xFFCBA6F7),
    secondary: Color(0xFF89B4FA),
    border: Color(0xFF45475A),
    textPrimary: Color(0xFFCDD6F4),
    textSecondary: Color(0xFFA6ADC8),
    gradientColors: [Color(0xFF2A2B3D), Color(0xFF1E1E2E)],
  );

  // 4. Dracula
  static const draculaTheme = NivioAppTheme(
    key: 'dracula',
    label: 'Dracula',
    description: 'Iconic dark blue-grey with purple and pink highlights',
    scaffoldBackgroundColor: Color(0xFF282A36),
    surface: Color(0xFF44475A),
    surfaceContainer: Color(0xFF343746),
    primary: Color(0xFFBD93F9),
    secondary: Color(0xFFFF79C6),
    border: Color(0xFF6272A4),
    textPrimary: Color(0xFFF8F8F2),
    textSecondary: Color(0xFF9EA9CE),
    gradientColors: [Color(0xFF363948), Color(0xFF282A36)],
  );

  // 5. Amber
  static const amberTheme = NivioAppTheme(
    key: 'amber',
    label: 'Amber',
    description: 'Cozy dark obsidian with warm golden amber tones',
    scaffoldBackgroundColor: Color(0xFF14100B),
    surface: Color(0xFF221A11),
    surfaceContainer: Color(0xFF2D2318),
    primary: Color(0xFFFFB300),
    secondary: Color(0xFFF59E0B),
    border: Color(0xFF3D2F1D),
    textPrimary: Color(0xFFFEF3C7),
    textSecondary: Color(0xFFA89F91),
    gradientColors: [Color(0xFF261D13), Color(0xFF14100B)],
  );

  // 6. Lavender
  static const lavenderTheme = NivioAppTheme(
    key: 'lavender',
    label: 'Lavender',
    description: 'Dreamy twilight purple with soft lavender highlights',
    scaffoldBackgroundColor: Color(0xFF161426),
    surface: Color(0xFF241F3D),
    surfaceContainer: Color(0xFF2E284D),
    primary: Color(0xFFB4BEFE),
    secondary: Color(0xFFC084FC),
    border: Color(0xFF42386E),
    textPrimary: Color(0xFFF3E8FF),
    textSecondary: Color(0xFFA59BB5),
    gradientColors: [Color(0xFF262142), Color(0xFF161426)],
  );

  // Keep the saved 'system' key for the Classic palette.
  static const classicTheme = NivioAppTheme(
    key: 'system',
    label: 'Classic',
    description: 'Nivio’s original dark palette with red accents',
    scaffoldBackgroundColor: Color(0xFF0D0F14),
    surface: Color(0xFF151922),
    surfaceContainer: Color(0xFF1D2330),
    primary: Color(0xFFE50914),
    secondary: Color(0xFF7E8798),
    border: Color(0x33FFFFFF),
    textPrimary: Color(0xFFF6F8FF),
    textSecondary: Color(0xFFB7BECC),
    gradientColors: [Color(0xFF151922), Color(0xFF0D0F14)],
  );

  static List<NivioAppTheme> get availableThemes => const [
    classicTheme,
    blackoutTheme,
    catppuccinTheme,
    draculaTheme,
    amberTheme,
    lavenderTheme,
    monokaiTheme,
  ];

  static NivioAppTheme getTheme(String key) {
    for (final theme in availableThemes) {
      if (theme.key == key) return theme;
    }
    return classicTheme;
  }

  static Color accentColorOf(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
  }

  static Color backgroundColorOf(BuildContext context) {
    return Theme.of(context).scaffoldBackgroundColor;
  }

  /// The AMOLED Black theme is active (pure black background).
  static bool isAmoled(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor.toARGB32() == 0xFF000000;

  /// Background for bottom sheets and dialogs: true black in AMOLED mode,
  /// otherwise [fallback] (the dark grey sheets have always used).
  static Color sheetColorOf(
    BuildContext context, {
    Color fallback = netflixDarkGrey,
  }) => isAmoled(context) ? Colors.black : fallback;

  static Color surfaceColorOf(BuildContext context) {
    return Theme.of(context).colorScheme.surface;
  }

  static LinearGradient backgroundGradientOf(BuildContext context) {
    final ext = Theme.of(context).extension<NivioThemeColors>();
    if (ext != null) return ext.backgroundGradient;
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF151922), netflixBlack],
    );
  }

  static NivioThemeColors themeColorsOf(BuildContext context) {
    final ext = Theme.of(context).extension<NivioThemeColors>();
    if (ext != null) return ext;
    return NivioThemeColors(
      background: netflixBlack,
      surface: netflixDarkGrey,
      surfaceContainer: netflixDarkGrey,
      primary: accentColorOf(context),
      secondary: netflixGrey,
      border: glassStroke,
      textPrimary: netflixWhite,
      textSecondary: netflixLightGrey,
      backgroundGradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF151922), Color(0xFF0D0F14)],
      ),
    );
  }

  static ThemeData buildTheme(
    String themeKey, {
    String fontFamily = 'Satoshi',
    bool dynamicColors = true,
  }) {
    final appTheme = dynamicColors ? getTheme(themeKey) : blackoutTheme;
    final amoled = appTheme.key == blackoutTheme.key;
    final onPrimary =
        ThemeData.estimateBrightnessForColor(appTheme.primary) ==
            Brightness.light
        ? const Color(0xFF111111)
        : Colors.white;

    final themeColors = NivioThemeColors(
      background: appTheme.scaffoldBackgroundColor,
      surface: appTheme.surface,
      surfaceContainer: appTheme.surfaceContainer,
      primary: appTheme.primary,
      secondary: appTheme.secondary,
      border: appTheme.border,
      textPrimary: appTheme.textPrimary,
      textSecondary: appTheme.textSecondary,
      backgroundGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: appTheme.gradientColors,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: appTheme.scaffoldBackgroundColor,
      primaryColor: appTheme.primary,
      cardColor: appTheme.surface,
      dialogBackgroundColor: amoled ? Colors.black : appTheme.surface,
      canvasColor: appTheme.scaffoldBackgroundColor,
      dividerColor: appTheme.border,
      extensions: [themeColors],
      colorScheme: ColorScheme.fromSeed(
        seedColor: appTheme.primary,
        brightness: Brightness.dark,
        primary: appTheme.primary,
        onPrimary: onPrimary,
        secondary: appTheme.secondary,
        onSurface: appTheme.textPrimary,
        onSurfaceVariant: appTheme.textSecondary,
        outline: appTheme.border,
        surface: appTheme.surface,
        surfaceContainer: appTheme.surfaceContainer,
      ),
      // AMOLED: sheets, dialogs and menus stay true black too.
      bottomSheetTheme: amoled
          ? const BottomSheetThemeData(
              backgroundColor: Colors.black,
              modalBackgroundColor: Colors.black,
              surfaceTintColor: Colors.transparent,
            )
          : null,
      dialogTheme: amoled
          ? const DialogThemeData(
              backgroundColor: Colors.black,
              surfaceTintColor: Colors.transparent,
            )
          : null,
      popupMenuTheme: amoled
          ? const PopupMenuThemeData(
              color: Colors.black,
              surfaceTintColor: Colors.transparent,
            )
          : null,
      appBarTheme: AppBarTheme(
        backgroundColor: amoled ? Colors.black : Colors.transparent,
        surfaceTintColor: amoled ? Colors.transparent : null,
        scrolledUnderElevation: amoled ? 0 : null,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: appTheme.textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(
          color: appTheme.textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.w700,
        ),
        displayMedium: TextStyle(
          color: appTheme.textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
        displaySmall: TextStyle(
          color: appTheme.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: TextStyle(
          color: appTheme.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: appTheme.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: appTheme.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(color: appTheme.textPrimary, fontSize: 16),
        bodyMedium: TextStyle(
          color: appTheme.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          color: appTheme.textSecondary.withOpacity(0.8),
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: appTheme.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: appTheme.border),
        ),
        hintStyle: TextStyle(color: appTheme.textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: appTheme.primary,
          foregroundColor: onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ).merge(AppPlatform.isTv ? _tvFocusButtonStyle() : null),
      ),
      cardTheme: CardThemeData(
        color: appTheme.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: appTheme.primary,
        thumbColor: appTheme.primary,
        inactiveTrackColor: appTheme.border,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return appTheme.primary;
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return appTheme.primary.withOpacity(0.4);
          }
          return null;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: appTheme.primary,
      ),
      // TV renders the desktop layout, so match desktop's sizing: Flutter
      // defaults Android to standard density and padded tap targets, which
      // make every button (e.g. the hero's Watch Now) visibly bigger than on
      // desktop. null keeps each platform's default elsewhere.
      visualDensity: AppPlatform.isTv ? VisualDensity.compact : null,
      materialTapTargetSize: AppPlatform.isTv
          ? MaterialTapTargetSize.shrinkWrap
          : null,
      // On a TV everything is driven by D-pad focus, and the default focus
      // overlay is too faint to see from the couch.
      focusColor: AppPlatform.isTv ? Colors.white.withOpacity(0.16) : null,
      iconButtonTheme: AppPlatform.isTv
          ? IconButtonThemeData(style: _tvFocusButtonStyle(circle: true))
          : null,
      filledButtonTheme: AppPlatform.isTv
          ? FilledButtonThemeData(style: _tvFocusButtonStyle())
          : null,
      outlinedButtonTheme: AppPlatform.isTv
          ? OutlinedButtonThemeData(style: _tvFocusButtonStyle())
          : null,
      textButtonTheme: AppPlatform.isTv
          ? TextButtonThemeData(style: _tvFocusButtonStyle())
          : null,
    );
  }

  /// TV only: the focused button fills solid white with dark content, like
  /// Netflix. Done with the background/foreground builders because, unlike
  /// colours, a button's own `styleFrom` never sets them, so this also
  /// covers buttons with custom colours (e.g. the hero's Watch Now).
  static ButtonStyle _tvFocusButtonStyle({bool circle = false}) {
    return ButtonStyle(
      backgroundBuilder: (context, states, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: states.contains(WidgetState.focused)
            ? Colors.white
            : Colors.transparent,
        child: child,
      ),
      foregroundBuilder: (context, states, child) => ColorFiltered(
        colorFilter: states.contains(WidgetState.focused)
            ? const ColorFilter.mode(Color(0xFF121212), BlendMode.srcIn)
            : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
        child: child,
      ),
      shape: circle ? const WidgetStatePropertyAll(CircleBorder()) : null,
    );
  }

  static ThemeData buildDarkTheme({
    String fontFamily = 'Satoshi',
    Color accentColor = netflixRed,
  }) {
    return buildTheme(classicTheme.key, fontFamily: fontFamily);
  }

  static final ThemeData darkTheme = buildDarkTheme();
}
