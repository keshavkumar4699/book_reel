/// BookReel's own UI kit (UX_DESIGN.md Revisions 6 and 8).
///
/// The reader wears its scene (forest, café, rain…): there every sheet,
/// dialog, menu, toast and control is drawn in the scene's colours, on top of
/// it, so reading feels like one calm place. Every other screen uses a plain
/// light or dark kit ([Kit.appLight], [Kit.appDark]), as the reader chooses in
/// Settings → Appearance. Nothing here uses Material's surfaces, ripples or
/// popups.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/settings.dart';
import 'theme.dart';
import 'vibes.dart';

export 'kit_overlays.dart';

/// Weight on the variable UI fonts (Outfit, Nunito).
List<FontVariation> _w(double weight) => [FontVariation('wght', weight)];

/// Colours and type for app chrome, derived from the reader's scene.
@immutable
class Kit extends ThemeExtension<Kit> {
  const Kit({
    required this.vibe,
    required this.dark,
    required this.ink,
    required this.inkSoft,
    required this.accent,
    required this.onAccent,
    required this.glass,
    required this.sheet,
    required this.stroke,
    required this.field,
    required this.barrier,
    required this.base,
    required this.danger,
    this.palette,
    this.motion = true,
  });

  /// The scene's colours, or the reading theme's on the plain paper scene.
  factory Kit.forScene(Vibe vibe, ReadingTheme paper, {bool motion = true}) {
    final p = scenePalettes[vibe];
    if (p == null) {
      final dark = paper.isDark;
      return Kit(
        vibe: vibe,
        dark: dark,
        motion: motion,
        ink: paper.text,
        inkSoft: paper.muted,
        accent: paper.accent,
        onAccent: dark ? const Color(0xFF1A1208) : const Color(0xFFFFFFFF),
        glass: dark ? const Color(0x14FFFFFF) : const Color(0xB8FFFFFF),
        sheet: dark ? Color.alphaBlend(const Color(0x14FFFFFF), paper.background) : Color.alphaBlend(const Color(0xB3FFFFFF), paper.background),
        stroke: dark ? const Color(0x1FFFFFFF) : const Color(0x17000000),
        field: dark ? const Color(0x14FFFFFF) : const Color(0x0F000000),
        barrier: dark ? const Color(0x99000000) : const Color(0x59000000),
        base: paper.background,
        danger: dark ? const Color(0xFFFF8A80) : const Color(0xFFB3261E),
      );
    }
    if (p.lightInk) {
      // Night-side scenes: deep tinted glass, the scene's own light ink.
      final deep = Color.lerp(p.tint, const Color(0xFF000000), 0.2)!;
      return Kit(
        vibe: vibe,
        palette: p,
        dark: true,
        motion: motion,
        ink: p.ink,
        inkSoft: p.ink.withValues(alpha: 0.74),
        accent: p.accent,
        onAccent: deep,
        glass: deep.withValues(alpha: 0.46),
        sheet: Color.alphaBlend(p.ink.withValues(alpha: 0.06), deep),
        stroke: p.ink.withValues(alpha: 0.13),
        field: p.ink.withValues(alpha: 0.09),
        barrier: const Color(0x8C000000),
        base: deep,
        danger: const Color(0xFFFF9C94),
      );
    }
    // Daylight scenes: a warm veil and dark ink.
    return Kit(
      vibe: vibe,
      palette: p,
      dark: false,
      motion: motion,
      ink: p.ink,
      inkSoft: p.ink.withValues(alpha: 0.76),
      accent: p.accent,
      onAccent: p.tint,
      glass: p.tint.withValues(alpha: 0.66),
      sheet: p.tint,
      stroke: p.ink.withValues(alpha: 0.12),
      field: p.ink.withValues(alpha: 0.07),
      barrier: const Color(0x52000000),
      base: p.tint,
      danger: const Color(0xFFA1271D),
    );
  }

  /// The kit for the reader's settings.
  factory Kit.fromSettings(AppSettings s, Brightness platform) =>
      Kit.forScene(s.vibe, ReadingTheme.of(effectiveReadingTheme(s, platform)), motion: s.animatedBackground);

  /// Light chrome for screens outside the reader: warm paper white, ember accent.
  static const appLight = Kit(
    vibe: Vibe.paper,
    dark: false,
    motion: false,
    ink: Color(0xFF1D1B18),
    inkSoft: Color(0xFF625D55), // 5.8:1 on [base]
    accent: Color(0xFFA4511A), // 5.0:1 on [base], 5.6:1 on white
    onAccent: Color(0xFFFFFFFF),
    glass: Color(0xFFFFFFFF),
    sheet: Color(0xFFFFFFFF),
    stroke: Color(0x17000000),
    field: Color(0x0D000000),
    barrier: Color(0x66000000),
    base: Color(0xFFF5F2EC),
    danger: Color(0xFFB3261E),
  );

  /// Dark chrome for screens outside the reader: warm near-black, amber accent.
  static const appDark = Kit(
    vibe: Vibe.paper,
    dark: true,
    motion: false,
    ink: Color(0xFFECE7DF),
    inkSoft: Color(0xFFA59E94), // 7.1:1 on [base]
    accent: Color(0xFFE9A85A), // 9.2:1 on [base]
    onAccent: Color(0xFF1E1408),
    glass: Color(0xFF1E1C1A),
    sheet: Color(0xFF242220),
    stroke: Color(0x1FFFFFFF),
    field: Color(0x14FFFFFF),
    barrier: Color(0x99000000),
    base: Color(0xFF121110),
    danger: Color(0xFFFF8A80),
  );

  /// The app kit for [brightness].
  static Kit app(Brightness brightness) => brightness == Brightness.dark ? appDark : appLight;

  static Kit of(BuildContext context) => Theme.of(context).extension<Kit>() ?? appLight;

  final Vibe vibe;
  final ScenePalette? palette;

  /// Light ink on dark glass.
  final bool dark;

  /// Scenes may move (the reader's "Animated background" setting).
  final bool motion;

  /// Primary text and icons.
  final Color ink;

  /// Secondary text.
  final Color inkSoft;

  /// Active controls, links, progress.
  final Color accent;

  /// Text and icons on an [accent] fill.
  final Color onAccent;

  /// Panels that sit on the scene.
  final Color glass;

  /// Sheets, dialogs, toasts and the tab dock (opaque, so nothing ghosts through).
  final Color sheet;

  /// Hairlines and borders.
  final Color stroke;

  /// Text fields, segmented tracks, unselected chips.
  final Color field;

  /// Dims the screen behind sheets and dialogs.
  final Color barrier;

  /// Solid colour behind everything when no scene is drawn.
  final Color base;
  final Color danger;

  SystemUiOverlayStyle get statusBar => dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

  TextStyle get display => TextStyle(
      fontFamily: 'Outfit', fontSize: 30, height: 1.12, fontWeight: FontWeight.w700, fontVariations: _w(700), letterSpacing: -0.4, color: ink);
  TextStyle get title =>
      TextStyle(fontFamily: 'Outfit', fontSize: 22, height: 1.18, fontWeight: FontWeight.w600, fontVariations: _w(600), color: ink);
  TextStyle get heading =>
      TextStyle(fontFamily: 'Outfit', fontSize: 17.5, height: 1.25, fontWeight: FontWeight.w600, fontVariations: _w(600), color: ink);
  TextStyle get body =>
      TextStyle(fontFamily: 'Nunito', fontSize: 15.5, height: 1.4, fontWeight: FontWeight.w500, fontVariations: _w(500), color: ink);
  TextStyle get strong =>
      TextStyle(fontFamily: 'Nunito', fontSize: 15.5, height: 1.3, fontWeight: FontWeight.w700, fontVariations: _w(700), color: ink);
  TextStyle get caption =>
      TextStyle(fontFamily: 'Nunito', fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w600, fontVariations: _w(600), color: inkSoft);
  TextStyle get label => TextStyle(
      fontFamily: 'Nunito', fontSize: 12, height: 1.2, fontWeight: FontWeight.w800, fontVariations: _w(800), letterSpacing: 0.9, color: inkSoft);

  @override
  Kit copyWith() => this;

  @override
  Kit lerp(ThemeExtension<Kit>? other, double t) => t < 0.5 ? this : (other as Kit? ?? this);
}

final _themes = <Object, ThemeData>{};

/// [buildAppTheme] for a kit, cached by [key] (building a colour scheme from a
/// seed is not free, and the reader rebuilds often).
ThemeData cachedAppTheme(Object key, Kit Function() kit) => _themes[key] ??= buildAppTheme(kit());

/// The app's ThemeData: Material defaults neutralised (no ripples, no Roboto),
/// the kit attached, and calm fade transitions between pages.
ThemeData buildAppTheme(Kit kit) {
  final brightness = kit.dark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(seedColor: kit.accent, brightness: brightness).copyWith(
    primary: kit.accent,
    onPrimary: kit.onAccent,
    surface: kit.base,
    onSurface: kit.ink,
    onSurfaceVariant: kit.inkSoft,
    outline: kit.stroke,
    error: kit.danger,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Nunito',
    scaffoldBackgroundColor: kit.base,
    canvasColor: kit.base,
    splashFactory: NoSplash.splashFactory,
    splashColor: const Color(0x00000000),
    highlightColor: const Color(0x00000000),
    hoverColor: const Color(0x00000000),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: kit.accent,
      selectionColor: kit.accent.withValues(alpha: 0.35),
      selectionHandleColor: kit.accent,
    ),
    iconTheme: IconThemeData(color: kit.ink),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: KitPageTransitions(),
      TargetPlatform.iOS: KitPageTransitions(),
      TargetPlatform.linux: KitPageTransitions(),
      TargetPlatform.macOS: KitPageTransitions(),
      TargetPlatform.windows: KitPageTransitions(),
      TargetPlatform.fuchsia: KitPageTransitions(),
    }),
    extensions: [kit],
  );
}

/// A calm cross-fade between pages: the content changes in place rather than
/// a new screen sliding in.
class KitPageTransitions extends PageTransitionsBuilder {
  const KitPageTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic),
      child: child,
    );
  }
}

// ---------------------------------------------------------------- backdrop

/// The page background: the scene under an even veil when the kit has one
/// (the reader, its session-end screen), else the kit's plain [Kit.base].
/// Still unless [animate].
class SceneBackdrop extends StatelessWidget {
  const SceneBackdrop({super.key, this.animate = false, this.veil = 0.28});

  final bool animate;

  /// Extra shade on top of the scene's calibrated scrim.
  final double veil;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final p = kit.palette;
    if (p == null) return ColoredBox(color: kit.base, child: const SizedBox.expand());
    return Stack(fit: StackFit.expand, children: [
      VibeBackground(vibe: kit.vibe, animate: animate && kit.motion),
      IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [for (final a in p.shade) p.tint.withValues(alpha: 1 - (1 - a) * (1 - veil))],
            ),
          ),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- pages

/// A screen: background, top bar and scrolling content.
class KitPage extends StatelessWidget {
  const KitPage({
    super.key,
    this.title,
    this.subtitle,
    this.back = true,
    this.actions = const [],
    this.children = const [],
    this.slivers,
    this.backdrop = true,
    this.dock = false,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 28),
    this.header,
    this.onRefresh,
  });

  final String? title;
  final String? subtitle;

  /// Show a back button (pushed screens); tab screens have none.
  final bool back;
  final List<Widget> actions;
  final List<Widget> children;

  /// Instead of [children], for long lists.
  final List<Widget>? slivers;

  /// Paint the background (pushed screens); tab screens sit on the shell's.
  final bool backdrop;

  /// Leave room for the floating tab dock.
  final bool dock;
  final EdgeInsets padding;

  /// Shown above the content, under the top bar.
  final Widget? header;

  /// Pull down to refresh.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom + (dock ? KitNavBar.reservedHeight : 0);
    final pad = padding.copyWith(bottom: padding.bottom + bottom);
    Widget content = CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
      SliverToBoxAdapter(
        child: SafeArea(bottom: false, child: KitTopBar(title: title, subtitle: subtitle, back: back, actions: actions)),
      ),
      if (header != null) SliverToBoxAdapter(child: header),
      if (slivers != null)
        SliverPadding(padding: pad, sliver: SliverMainAxisGroup(slivers: slivers!))
      else
        SliverPadding(padding: pad, sliver: SliverList(delegate: SliverChildListDelegate(children))),
    ]);
    if (onRefresh != null) {
      content = RefreshIndicator(onRefresh: onRefresh!, color: kit.accent, backgroundColor: kit.sheet, child: content);
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kit.statusBar,
      child: Scaffold(
        backgroundColor: backdrop ? kit.base : const Color(0x00000000),
        body: DefaultTextStyle(
          style: kit.body,
          child: backdrop ? Stack(children: [const Positioned.fill(child: SceneBackdrop()), Positioned.fill(child: content)]) : content,
        ),
      ),
    );
  }
}

/// Back button, title and actions, drawn on the scene.
class KitTopBar extends StatelessWidget {
  const KitTopBar({super.key, this.title, this.subtitle, this.back = true, this.actions = const []});

  final String? title;
  final String? subtitle;
  final bool back;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(back ? 10 : 20, 8, 12, 10),
      child: Row(children: [
        if (back) ...[
          KitIconButton(icon: Icons.arrow_back_rounded, semanticLabel: 'Back', onPressed: () => Navigator.maybePop(context)),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (title != null)
              Semantics(header: true, child: Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: back ? kit.title : kit.display)),
            if (subtitle != null) Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: kit.caption),
          ]),
        ),
        for (final a in actions) ...[const SizedBox(width: 6), a],
      ]),
    );
  }
}

// ---------------------------------------------------------------- touch

/// Tap target with a soft press-down scale instead of an ink ripple.
class KitPressable extends StatefulWidget {
  const KitPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.selected,
    this.pressedScale = 0.96,
    this.haptic = false,
    this.excludeSemantics = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final bool? selected;
  final double pressedScale;
  final bool haptic;

  /// Read only [semanticLabel], not the child's own text.
  final bool excludeSemantics;

  @override
  State<KitPressable> createState() => _KitPressableState();
}

class _KitPressableState extends State<KitPressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final own = widget.excludeSemantics;
    return Semantics(
      container: true,
      button: enabled,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      excludeSemantics: own,
      // With the child's semantics replaced, this node carries the actions.
      onTap: own ? widget.onTap : null,
      onLongPress: own ? widget.onLongPress : null,
      child: GestureDetector(
        excludeFromSemantics: own,
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down ? widget.pressedScale : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: _down ? 0.82 : 1,
            duration: const Duration(milliseconds: 110),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Round glass icon button (48 dp target).
class KitIconButton extends StatelessWidget {
  const KitIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.glass = true,
    this.color,
    this.size = 42,
    this.iconSize = 22,
    this.shadows,
    this.child,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;

  /// Draw the glass circle (off for icons that float on a scene).
  final bool glass;
  final Color? color;
  final double size;
  final double iconSize;
  final List<Shadow>? shadows;

  /// Replaces the icon (e.g. an emoji).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    return KitPressable(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      excludeSemantics: true,
      pressedScale: 0.9,
      child: SizedBox(
        width: math.max(48, size),
        height: math.max(48, size),
        child: Center(
          child: Container(
            width: size,
            height: size,
            decoration: glass
                ? BoxDecoration(shape: BoxShape.circle, color: kit.glass, border: Border.all(color: kit.stroke))
                : null,
            alignment: Alignment.center,
            child: child ?? Icon(icon, size: iconSize, color: color ?? kit.ink, shadows: shadows),
          ),
        ),
      ),
    );
  }
}

enum KitButtonKind { primary, secondary, ghost, danger }

/// Pill button: filled with the scene's accent, or outlined, or bare text.
class KitButton extends StatelessWidget {
  const KitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
    this.kind = KitButtonKind.primary,
    this.expand = false,
    this.compact = false,
  });

  const KitButton.secondary(
      {super.key, required this.label, required this.onPressed, this.icon, this.leading, this.expand = false, this.compact = false})
      : kind = KitButtonKind.secondary;

  const KitButton.ghost(
      {super.key, required this.label, required this.onPressed, this.icon, this.leading, this.expand = false, this.compact = false})
      : kind = KitButtonKind.ghost;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// A custom glyph before the label (drawn in the button's text colour).
  final Widget? leading;
  final KitButtonKind kind;
  final bool expand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final (Color bg, Color fg, Color? border) = switch (kind) {
      KitButtonKind.primary => (kit.accent, kit.onAccent, null),
      KitButtonKind.secondary => (kit.field, kit.ink, kit.stroke),
      KitButtonKind.ghost => (const Color(0x00000000), kit.accent, null),
      KitButtonKind.danger => (kit.danger.withValues(alpha: 0.14), kit.danger, kit.danger.withValues(alpha: 0.4)),
    };
    final h = compact ? 40.0 : 52.0;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: compact ? 18 : 20, color: fg), const SizedBox(width: 8)],
        if (leading != null) ...[
          IconTheme.merge(data: IconThemeData(color: fg, size: compact ? 18 : 20), child: leading!),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: kit.strong.copyWith(color: fg, fontSize: compact ? 14 : 15.5)),
        ),
      ],
    );
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: KitPressable(
        onTap: onPressed,
        haptic: true,
        child: Container(
          height: h,
          padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 22),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(h / 2),
            border: border == null ? null : Border.all(color: border),
          ),
          child: content,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- surfaces

/// A glass panel on the scene (replaces cards).
class KitPanel extends StatelessWidget {
  const KitPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.radius = 22,
    this.color,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? kit.glass,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: kit.stroke),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return KitPressable(onTap: onTap, semanticLabel: semanticLabel, pressedScale: 0.98, child: box);
  }
}

/// A labelled group of rows in one panel, separated by hairlines.
class KitGroup extends StatelessWidget {
  const KitGroup({super.key, this.label, required this.children, this.footer});

  final String? label;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
          child: Semantics(header: true, child: Text(label!.toUpperCase(), style: kit.label)),
        ),
      KitPanel(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Container(height: 1, margin: const EdgeInsets.only(left: 16), color: kit.stroke),
            children[i],
          ],
        ]),
      ),
      if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 0), child: Text(footer!, style: kit.caption)),
    ]);
  }
}

/// Small rounded square holding an icon or emoji.
class KitBubble extends StatelessWidget {
  const KitBubble({super.key, this.icon, this.emoji, this.color, this.size = 36});

  final IconData? icon;
  final String? emoji;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final c = color ?? kit.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(size * 0.32)),
      alignment: Alignment.center,
      child: emoji != null
          ? Text(emoji!, style: TextStyle(fontSize: size * 0.5))
          : Icon(icon, size: size * 0.56, color: c),
    );
  }
}

/// One row: icon, title, subtitle, a value or control, and a chevron when it
/// opens something.
class KitRow extends StatelessWidget {
  const KitRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.icon,
    this.emoji,
    this.leading,
    this.trailing,
    this.onTap,
    this.chevron,
    this.destructive = false,
    this.selected = false,
    this.iconColor,
    this.maxSubtitleLines = 3,
  });

  final String title;
  final String? subtitle;
  final String? value;
  final IconData? icon;
  final String? emoji;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool? chevron;
  final bool destructive;

  /// Shows a check mark (single choice lists).
  final bool selected;
  final Color? iconColor;
  final int maxSubtitleLines;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final color = destructive ? kit.danger : kit.ink;
    final lead = leading ??
        (icon != null || emoji != null ? KitBubble(icon: icon, emoji: emoji, color: destructive ? kit.danger : iconColor) : null);
    final showChevron = chevron ?? (onTap != null && trailing == null && !selected);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        if (lead != null) ...[lead, const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: kit.strong.copyWith(color: color)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!, maxLines: maxSubtitleLines, overflow: TextOverflow.ellipsis, style: kit.caption),
              ),
          ]),
        ),
        if (value != null)
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: kit.caption),
            ),
          ),
        if (trailing != null) Padding(padding: const EdgeInsets.only(left: 10), child: trailing),
        if (selected) Padding(padding: const EdgeInsets.only(left: 10), child: Icon(Icons.check_circle_rounded, color: kit.accent)),
        if (showChevron) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.chevron_right_rounded, color: kit.inkSoft)),
      ]),
    );
    if (onTap == null) return row;
    return KitPressable(onTap: onTap, selected: selected ? true : null, pressedScale: 0.985, child: row);
  }
}

// ---------------------------------------------------------------- controls

/// On/off pill.
class KitSwitch extends StatelessWidget {
  const KitSwitch({super.key, required this.value, required this.onChanged, this.semanticLabel});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    const curve = Curves.easeOutCubic;
    const d = Duration(milliseconds: 180);
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onChanged == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onChanged!(!value);
              },
        child: AnimatedContainer(
          duration: d,
          curve: curve,
          width: 50,
          height: 30,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: value ? kit.accent : kit.ink.withValues(alpha: 0.18),
          ),
          child: AnimatedAlign(
            duration: d,
            curve: curve,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: d,
              width: 24,
              height: 24,
              decoration: BoxDecoration(shape: BoxShape.circle, color: value ? kit.onAccent : kit.ink.withValues(alpha: 0.86)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row with a switch; tapping anywhere on it toggles.
class KitSwitchRow extends StatelessWidget {
  const KitSwitchRow({super.key, required this.title, this.subtitle, required this.value, required this.onChanged, this.icon, this.emoji});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: KitRow(
        title: title,
        subtitle: subtitle,
        icon: icon,
        emoji: emoji,
        chevron: false,
        trailing: KitSwitch(value: value, onChanged: onChanged),
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!value);
        },
      ),
    );
  }
}

/// A track of options, one selected (replaces segmented buttons).
class KitSegmented<T> extends StatelessWidget {
  const KitSegmented({super.key, required this.values, required this.selected, required this.label, required this.onChanged});

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: kit.field, borderRadius: BorderRadius.circular(15)),
      child: Row(children: [
        for (final v in values)
          Expanded(
            child: KitPressable(
              onTap: () {
                if (v != selected) {
                  HapticFeedback.selectionClick();
                  onChanged(v);
                }
              },
              selected: v == selected,
              pressedScale: 0.97,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: v == selected ? kit.accent : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label(v),
                      maxLines: 1, style: kit.strong.copyWith(fontSize: 14, color: v == selected ? kit.onAccent : kit.ink)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// A pill to pick or toggle (replaces Material chips).
class KitChip extends StatelessWidget {
  const KitChip({super.key, required this.label, this.selected = false, this.onTap, this.icon, this.emoji});

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final fg = selected ? kit.onAccent : kit.ink;
    return KitPressable(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      selected: onTap == null ? null : selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? kit.accent : kit.field,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? kit.accent : kit.stroke),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (emoji != null) ...[Text(emoji!, style: const TextStyle(fontSize: 15)), const SizedBox(width: 6)],
          if (icon != null) ...[Icon(icon, size: 17, color: fg), const SizedBox(width: 6)],
          Flexible(child: Text(label, style: kit.strong.copyWith(fontSize: 14, color: fg))),
        ]),
      ),
    );
  }
}

/// Smooth slider with an accent fill and a ring knob.
class KitSlider extends StatelessWidget {
  const KitSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.semanticLabel,
    this.format,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String? semanticLabel;
  final String Function(double)? format;

  double _snap(double v) {
    v = v.clamp(min, max);
    if (divisions == null || divisions! <= 0) return v;
    final step = (max - min) / divisions!;
    return min + ((v - min) / step).round() * step;
  }

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final step = (max - min) / ((divisions ?? 0) > 0 ? divisions! : 20);
    String show(double v) => format?.call(v) ?? v.toStringAsFixed(1);
    final t = max == min ? 0.0 : ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Semantics(
      slider: true,
      label: semanticLabel,
      value: show(value),
      increasedValue: show(_snap(value + step)),
      decreasedValue: show(_snap(value - step)),
      onIncrease: () => onChanged(_snap(value + step)),
      onDecrease: () => onChanged(_snap(value - step)),
      child: LayoutBuilder(builder: (context, c) {
        const knob = 24.0;
        final w = c.maxWidth;
        void update(Offset local) {
          final v = _snap(min + ((local.dx - knob / 2) / (w - knob)).clamp(0.0, 1.0) * (max - min));
          if ((v - value).abs() > 1e-9) {
            if (divisions != null) HapticFeedback.selectionClick();
            onChanged(v);
          }
        }

        return GestureDetector(
          // The slider node above carries increase/decrease for screen readers.
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => update(d.localPosition),
          onHorizontalDragStart: (d) => update(d.localPosition),
          onHorizontalDragUpdate: (d) => update(d.localPosition),
          child: SizedBox(
            height: 40,
            width: w,
            child: CustomPaint(
              painter: _SliderPainter(
                t: t,
                fill: kit.accent,
                track: kit.ink.withValues(alpha: 0.16),
                knob: kit.dark ? kit.ink : const Color(0xFFFFFFFF),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter({required this.t, required this.fill, required this.track, required this.knob});

  final double t;
  final Color fill;
  final Color track;
  final Color knob;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 12.0;
    final y = size.height / 2;
    final left = r, right = size.width - r;
    final x = left + (right - left) * t;
    final bar = RRect.fromLTRBR(left, y - 3, right, y + 3, const Radius.circular(3));
    canvas.drawRRect(bar, Paint()..color = track);
    canvas.drawRRect(RRect.fromLTRBR(left, y - 3, x, y + 3, const Radius.circular(3)), Paint()..color = fill);
    canvas.drawCircle(Offset(x, y), r, Paint()..color = fill);
    canvas.drawCircle(Offset(x, y), r - 4, Paint()..color = knob);
  }

  @override
  bool shouldRepaint(_SliderPainter old) => old.t != t || old.fill != fill || old.track != track || old.knob != knob;
}

/// Thin rounded progress bar.
class KitProgress extends StatelessWidget {
  const KitProgress({super.key, required this.value, this.height = 6, this.color, this.track});

  final double value;
  final double height;
  final Color? color;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    return Semantics(
      value: '${(value.clamp(0.0, 1.0) * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: Stack(fit: StackFit.expand, children: [
            ColoredBox(color: track ?? kit.ink.withValues(alpha: 0.14)),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: value.clamp(0.0, 1.0),
              child: ColoredBox(color: color ?? kit.accent),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A slowly turning arc (replaces the Material spinner).
class KitSpinner extends StatefulWidget {
  const KitSpinner({super.key, this.size = 30, this.color});

  final double size;
  final Color? color;

  @override
  State<KitSpinner> createState() => _KitSpinnerState();
}

class _KitSpinnerState extends State<KitSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    return Semantics(
      label: 'Loading',
      child: RotationTransition(
        turns: _c,
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _ArcPainter(widget.color ?? kit.accent, kit.ink.withValues(alpha: 0.12)),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.color, this.track);
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.11;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, p..color = track);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 1.3, false, p..color = color);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color || old.track != track;
}

/// Rounded text field on a soft fill.
class KitTextField extends StatelessWidget {
  const KitTextField({
    super.key,
    this.controller,
    this.hint,
    this.maxLines = 1,
    this.minLines,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.capitalization = TextCapitalization.sentences,
    this.maxLength,
    this.keyboardType,
    this.semanticLabel,
  });

  final TextEditingController? controller;
  final String? hint;
  final int maxLines;
  final int? minLines;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final TextCapitalization capitalization;
  final int? maxLength;
  final TextInputType? keyboardType;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: kit.field,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kit.stroke),
      ),
      child: Semantics(
        label: semanticLabel ?? hint,
        textField: true,
        child: TextField(
          controller: controller,
          autofocus: autofocus,
          maxLines: maxLines,
          minLines: minLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: textInputAction,
          textCapitalization: capitalization,
          cursorColor: kit.accent,
          style: kit.body,
          decoration: InputDecoration.collapsed(hintText: hint, hintStyle: kit.body.copyWith(color: kit.inkSoft.withValues(alpha: 0.7)))
              .copyWith(counterText: ''),
        ),
      ),
    );
  }
}

/// Count bubble (replaces Material badges).
class KitBadge extends StatelessWidget {
  const KitBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    if (count <= 0) return child;
    return Stack(clipBehavior: Clip.none, children: [
      child,
      Positioned(
        right: -2,
        top: -2,
        child: Container(
          constraints: const BoxConstraints(minWidth: 18),
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: kit.accent, borderRadius: BorderRadius.circular(9)),
          child: Text(count > 99 ? '99+' : '$count', style: kit.label.copyWith(color: kit.onAccent, fontSize: 10.5, letterSpacing: 0)),
        ),
      ),
    ]);
  }
}

/// Friendly empty state.
class KitEmpty extends StatelessWidget {
  const KitEmpty({super.key, required this.emoji, required this.title, this.message, this.action});

  final String emoji;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 44)),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: kit.heading),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(message!, textAlign: TextAlign.center, style: kit.caption),
        ],
        if (action != null) ...[const SizedBox(height: 18), action!],
      ]),
    );
  }
}

// ---------------------------------------------------------------- tabs

class KitNavItem {
  const KitNavItem(this.icon, this.activeIcon, this.label, {this.badge = 0});
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int badge;
}

/// Floating glass dock for the four tabs.
class KitNavBar extends StatelessWidget {
  const KitNavBar({super.key, required this.items, required this.index, required this.onSelect});

  /// Room the dock takes above the bottom safe area.
  static const reservedHeight = 86.0;

  final List<KitNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 12),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: kit.sheet,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: kit.stroke),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 8))],
        ),
        child: Row(children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: KitPressable(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelect(i);
                },
                selected: i == index,
                semanticLabel: '${items[i].label} tab',
                excludeSemantics: true,
                pressedScale: 0.9,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  KitBadge(
                    count: items[i].badge,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: i == index ? kit.accent.withValues(alpha: 0.2) : const Color(0x00000000),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(i == index ? items[i].activeIcon : items[i].icon,
                          size: 23, color: i == index ? kit.accent : kit.inkSoft),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(items[i].label,
                      style: kit.label.copyWith(fontSize: 11, letterSpacing: 0.2, color: i == index ? kit.ink : kit.inkSoft)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- icons

/// The share glyph of reels apps: a solid arrow curving up and to the right.
class ShareArrowIcon extends StatelessWidget {
  const ShareArrowIcon({super.key, this.size = 24, this.color, this.shadows});

  final double size;
  final Color? color;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    return Transform.flip(
      flipX: true,
      child: Icon(Icons.reply_rounded, size: size, color: color, shadows: shadows),
    );
  }
}
