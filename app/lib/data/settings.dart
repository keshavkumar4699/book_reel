import '../core/habit/habit_engine.dart';
import '../core/segmentation/rule_segmenter.dart';
import '../core/text/lexicon.dart';

enum ReadingThemeId { paper, white, sepia, dark, black }

/// [book] uses each book's own typographic voice (lib/ui/typography.dart).
enum ReadingFont { book, literata, atkinson, system }

enum KeyPointStyle { off, subtle, bold }

/// Calm animated backgrounds for the reader and Today screen.
enum Vibe { forest, cafe, rain, ocean, night, meadow, snow, city, paper }

/// Bump when defaults change in a way existing users should get.
const currentLayoutVersion = 3;

/// Bump when the plan ladder changes, so saved plans can be mapped.
const currentPlanVersion = 2;

/// Subscription tiers, cheapest first (DESIGN.md §6.1). Free reads books with
/// on-device rules; each paid tier steps up one Claude model.
enum Tier {
  free(label: 'Free', model: 'On-device rules', usdPerMonth: 0, freezes: 1),
  lite(label: 'Lite', model: 'Claude Haiku', usdPerMonth: 3.99, freezes: 2),
  plus(label: 'Plus', model: 'Claude Sonnet', usdPerMonth: 8.99, freezes: 3),
  pro(label: 'Pro', model: 'Claude Opus', usdPerMonth: 19.99, freezes: 4),
  scholar(label: 'Scholar', model: 'Claude Fable', usdPerMonth: 29.99, freezes: 5);

  const Tier({required this.label, required this.model, required this.usdPerMonth, required this.freezes});
  final String label;

  /// What reads the book and cuts the cards.
  final String model;

  /// US list price; Play Billing shows the local price at checkout.
  final double usdPerMonth;

  /// Streak freezes refilled each week.
  final int freezes;

  bool get paid => this != Tier.free;
}

class AppSettings {
  const AppSettings({
    this.theme = ReadingThemeId.paper,
    this.followSystemDark = true,
    this.font = ReadingFont.book,
    this.fontSize = 22,
    this.lineHeight = 1.55,
    this.letterSpacing = 0,
    this.wordSpacing = 0,
    this.cardLength = CardLength.snack,
    this.showAiTitles = true,
    this.keyPointStyle = KeyPointStyle.subtle,
    this.underlineHardWords = true,
    this.readingLevel = ReadingLevel.intermediate,
    this.goalUnit = GoalUnit.cards,
    this.dailyGoal = 20,
    this.goalMode = GoalMode.daily,
    this.weeklyDays = 5,
    this.reminderEnabled = true,
    this.reminderHour = 20,
    this.reminderMinute = 0,
    this.habitAnchor = '',
    this.recallCards = true,
    this.reflectCards = true,
    this.leftHanded = false,
    this.hideLeaderboards = false,
    this.onboardingDone = false,
    this.goalSetupDone = false,
    this.tier = Tier.free,
    this.displayName = 'Reader',
    this.interests = const [],
    this.vibe = Vibe.forest,
    this.animatedBackground = true,
    this.gestureTutorialSeen = false,
    this.layoutVersion = currentLayoutVersion,
    this.sceneSound = true,
    this.sceneSoundVolume = 0.6,
    this.autoScene = true,
  });

  final ReadingThemeId theme;
  final bool followSystemDark;
  final ReadingFont font;
  final double fontSize;
  final double lineHeight;
  final double letterSpacing;
  final double wordSpacing;
  final CardLength cardLength;
  final bool showAiTitles;
  final KeyPointStyle keyPointStyle;
  final bool underlineHardWords;
  final ReadingLevel readingLevel;
  final GoalUnit goalUnit;
  final int dailyGoal;
  final GoalMode goalMode;
  final int weeklyDays;
  final bool reminderEnabled;
  final int reminderHour;
  final int reminderMinute;
  final String habitAnchor;
  final bool recallCards;
  final bool reflectCards;
  final bool leftHanded;
  final bool hideLeaderboards;
  final bool onboardingDone;

  /// Goal is asked after the first cards, when motivation is highest (UX_DESIGN.md §5.9).
  final bool goalSetupDone;
  final Tier tier;
  final String displayName;
  final List<String> interests;
  final Vibe vibe;
  final bool animatedBackground;
  final bool gestureTutorialSeen;
  final int layoutVersion;

  /// The scene's own ambient sound (rain, café, waves…), for every tier.
  /// Readers mute it to play their own music.
  final bool sceneSound;
  final double sceneSoundVolume;

  /// Let the AI pick the background per chapter (paid tiers).
  final bool autoScene;

  GoalConfig get goal => GoalConfig(
        unit: goalUnit,
        dailyTarget: dailyGoal,
        mode: goalMode,
        weeklyDays: weeklyDays,
        freezesPerWeek: tier.freezes,
      );

  AppSettings copyWith({
    ReadingThemeId? theme,
    bool? followSystemDark,
    ReadingFont? font,
    double? fontSize,
    double? lineHeight,
    double? letterSpacing,
    double? wordSpacing,
    CardLength? cardLength,
    bool? showAiTitles,
    KeyPointStyle? keyPointStyle,
    bool? underlineHardWords,
    ReadingLevel? readingLevel,
    GoalUnit? goalUnit,
    int? dailyGoal,
    GoalMode? goalMode,
    int? weeklyDays,
    bool? reminderEnabled,
    int? reminderHour,
    int? reminderMinute,
    String? habitAnchor,
    bool? recallCards,
    bool? reflectCards,
    bool? leftHanded,
    bool? hideLeaderboards,
    bool? onboardingDone,
    bool? goalSetupDone,
    Tier? tier,
    String? displayName,
    List<String>? interests,
    Vibe? vibe,
    bool? animatedBackground,
    bool? gestureTutorialSeen,
    bool? sceneSound,
    double? sceneSoundVolume,
    bool? autoScene,
  }) =>
      AppSettings(
        theme: theme ?? this.theme,
        followSystemDark: followSystemDark ?? this.followSystemDark,
        font: font ?? this.font,
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        wordSpacing: wordSpacing ?? this.wordSpacing,
        cardLength: cardLength ?? this.cardLength,
        showAiTitles: showAiTitles ?? this.showAiTitles,
        keyPointStyle: keyPointStyle ?? this.keyPointStyle,
        underlineHardWords: underlineHardWords ?? this.underlineHardWords,
        readingLevel: readingLevel ?? this.readingLevel,
        goalUnit: goalUnit ?? this.goalUnit,
        dailyGoal: dailyGoal ?? this.dailyGoal,
        goalMode: goalMode ?? this.goalMode,
        weeklyDays: weeklyDays ?? this.weeklyDays,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        reminderHour: reminderHour ?? this.reminderHour,
        reminderMinute: reminderMinute ?? this.reminderMinute,
        habitAnchor: habitAnchor ?? this.habitAnchor,
        recallCards: recallCards ?? this.recallCards,
        reflectCards: reflectCards ?? this.reflectCards,
        leftHanded: leftHanded ?? this.leftHanded,
        hideLeaderboards: hideLeaderboards ?? this.hideLeaderboards,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        goalSetupDone: goalSetupDone ?? this.goalSetupDone,
        tier: tier ?? this.tier,
        displayName: displayName ?? this.displayName,
        interests: interests ?? this.interests,
        vibe: vibe ?? this.vibe,
        animatedBackground: animatedBackground ?? this.animatedBackground,
        gestureTutorialSeen: gestureTutorialSeen ?? this.gestureTutorialSeen,
        layoutVersion: layoutVersion,
        sceneSound: sceneSound ?? this.sceneSound,
        sceneSoundVolume: sceneSoundVolume ?? this.sceneSoundVolume,
        autoScene: autoScene ?? this.autoScene,
      );

  Map<String, dynamic> toJson() => {
        'theme': theme.name,
        'followSystemDark': followSystemDark,
        'font': font.name,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'letterSpacing': letterSpacing,
        'wordSpacing': wordSpacing,
        'cardLength': cardLength.name,
        'showAiTitles': showAiTitles,
        'keyPointStyle': keyPointStyle.name,
        'underlineHardWords': underlineHardWords,
        'readingLevel': readingLevel.name,
        'goalUnit': goalUnit.name,
        'dailyGoal': dailyGoal,
        'goalMode': goalMode.name,
        'weeklyDays': weeklyDays,
        'reminderEnabled': reminderEnabled,
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
        'habitAnchor': habitAnchor,
        'recallCards': recallCards,
        'reflectCards': reflectCards,
        'leftHanded': leftHanded,
        'hideLeaderboards': hideLeaderboards,
        'onboardingDone': onboardingDone,
        'goalSetupDone': goalSetupDone,
        'tier': tier.name,
        'displayName': displayName,
        'interests': interests,
        'vibe': vibe.name,
        'animatedBackground': animatedBackground,
        'gestureTutorialSeen': gestureTutorialSeen,
        'layoutVersion': layoutVersion,
        'sceneSound': sceneSound,
        'sceneSoundVolume': sceneSoundVolume,
        'autoScene': autoScene,
        'planVersion': currentPlanVersion,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    double num_(Object? v, double f) => (v as num?)?.toDouble() ?? f;
    final version = (j['layoutVersion'] as int?) ?? 1;
    final legacy = version < 2;
    var savedFont = pick(ReadingFont.values, j['font'], d.font);
    // Layout v3: each book gets its own fonts. Readers still on the default of
    // their version (Literata in v1, Atkinson in v2) move to it; a font picked
    // on purpose is kept.
    if ((version < 2 && savedFont == ReadingFont.literata) || (version == 2 && savedFont == ReadingFont.atkinson)) {
      savedFont = ReadingFont.book;
    }
    final savedGoal = (j['dailyGoal'] as int?) ?? d.dailyGoal;
    // Plan v2 (Nov 2026) added Lite at the old Plus price and moved every plan
    // up one model. A saved plan keeps its price: Plus → Lite, Pro → Plus,
    // Scholar → Pro.
    var savedTier = pick(Tier.values, j['tier'], d.tier);
    if (((j['planVersion'] as int?) ?? 1) < 2 && savedTier.paid && savedTier != Tier.lite) {
      savedTier = Tier.values[savedTier.index - 1];
    }
    return AppSettings(
      theme: pick(ReadingThemeId.values, j['theme'], d.theme),
      followSystemDark: (j['followSystemDark'] as bool?) ?? d.followSystemDark,
      // Layout v2 (social feed): short cards, larger sans text. Migrate untouched defaults.
      font: savedFont,
      fontSize: legacy ? (num_(j['fontSize'], d.fontSize) < 22 ? 22 : num_(j['fontSize'], d.fontSize)) : num_(j['fontSize'], d.fontSize),
      lineHeight: num_(j['lineHeight'], d.lineHeight),
      letterSpacing: num_(j['letterSpacing'], d.letterSpacing),
      wordSpacing: num_(j['wordSpacing'], d.wordSpacing),
      cardLength: legacy ? CardLength.snack : pick(CardLength.values, j['cardLength'], d.cardLength),
      showAiTitles: (j['showAiTitles'] as bool?) ?? d.showAiTitles,
      keyPointStyle: pick(KeyPointStyle.values, j['keyPointStyle'], d.keyPointStyle),
      underlineHardWords: (j['underlineHardWords'] as bool?) ?? d.underlineHardWords,
      readingLevel: pick(ReadingLevel.values, j['readingLevel'], d.readingLevel),
      goalUnit: pick(GoalUnit.values, j['goalUnit'], d.goalUnit),
      dailyGoal: legacy && savedGoal == 10 ? 20 : savedGoal,
      goalMode: pick(GoalMode.values, j['goalMode'], d.goalMode),
      weeklyDays: (j['weeklyDays'] as int?) ?? d.weeklyDays,
      reminderEnabled: (j['reminderEnabled'] as bool?) ?? d.reminderEnabled,
      reminderHour: (j['reminderHour'] as int?) ?? d.reminderHour,
      reminderMinute: (j['reminderMinute'] as int?) ?? d.reminderMinute,
      habitAnchor: (j['habitAnchor'] as String?) ?? d.habitAnchor,
      recallCards: (j['recallCards'] as bool?) ?? d.recallCards,
      reflectCards: (j['reflectCards'] as bool?) ?? d.reflectCards,
      leftHanded: (j['leftHanded'] as bool?) ?? d.leftHanded,
      hideLeaderboards: (j['hideLeaderboards'] as bool?) ?? d.hideLeaderboards,
      onboardingDone: (j['onboardingDone'] as bool?) ?? d.onboardingDone,
      goalSetupDone: (j['goalSetupDone'] as bool?) ?? d.goalSetupDone,
      tier: savedTier,
      displayName: (j['displayName'] as String?) ?? d.displayName,
      interests: ((j['interests'] as List?) ?? const []).cast<String>(),
      vibe: pick(Vibe.values, j['vibe'], d.vibe),
      animatedBackground: (j['animatedBackground'] as bool?) ?? d.animatedBackground,
      gestureTutorialSeen: (j['gestureTutorialSeen'] as bool?) ?? d.gestureTutorialSeen,
      // Readers who turned the old soundtrack off keep their sound off.
      sceneSound: (j['sceneSound'] as bool?) ?? (j['soundtrack'] as bool?) ?? d.sceneSound,
      sceneSoundVolume: num_(j['sceneSoundVolume'], d.sceneSoundVolume).clamp(0.0, 1.0),
      autoScene: (j['autoScene'] as bool?) ?? d.autoScene,
    );
  }
}
