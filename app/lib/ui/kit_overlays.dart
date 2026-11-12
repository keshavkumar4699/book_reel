import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kit.dart';

// ---------------------------------------------------------------- sheets

/// Opens a sheet that rises from the bottom in the scene's colours. Drag its
/// handle down, tap outside or press back to close.
Future<T?> showKitSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  String? subtitle,
  Widget? trailing,
  bool scrollable = true,
  double maxHeight = 0.9,
  bool dismissible = true,
  EdgeInsets padding = const EdgeInsets.fromLTRB(16, 4, 16, 16),
}) {
  final kit = Kit.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push<T>(_KitSheetRoute<T>(
    kit: kit,
    dismissible: dismissible,
    label: title,
    builder: (ctx) => InheritedTheme.captureAll(
      context,
      _KitSheet(
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        scrollable: scrollable,
        maxHeight: maxHeight,
        padding: padding,
        child: Builder(builder: builder),
      ),
      to: navigator.context,
    ),
  ));
}

class _KitSheetRoute<T> extends PopupRoute<T> {
  _KitSheetRoute({required this.builder, required this.kit, required this.dismissible, this.label});

  final WidgetBuilder builder;
  final Kit kit;
  final bool dismissible;
  final String? label;

  @override
  Color? get barrierColor => kit.barrier;

  @override
  bool get barrierDismissible => dismissible;

  @override
  String? get barrierLabel => 'Close${label == null ? '' : ' $label'}';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => builder(context);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curve), child: child);
  }
}

class _KitSheet extends StatefulWidget {
  const _KitSheet({
    required this.child,
    required this.scrollable,
    required this.maxHeight,
    required this.padding,
    this.title,
    this.subtitle,
    this.trailing,
  });

  final Widget child;
  final bool scrollable;
  final double maxHeight;
  final EdgeInsets padding;
  final String? title;
  final String? subtitle;
  final Widget? trailing;

  @override
  State<_KitSheet> createState() => _KitSheetState();
}

class _KitSheetState extends State<_KitSheet> with SingleTickerProviderStateMixin {
  final _drag = ValueNotifier<double>(0);
  late final AnimationController _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  double _from = 0;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() => _drag.value = _from * (1 - Curves.easeOutCubic.transform(_settle.value)));
  }

  @override
  void dispose() {
    _settle.dispose();
    _drag.dispose();
    super.dispose();
  }

  void _dragUpdate(DragUpdateDetails d) {
    _settle.stop();
    _drag.value = math.max(0, _drag.value + d.delta.dy);
  }

  void _dragEnd(DragEndDetails d, double height) {
    if (_drag.value > height * 0.22 || (d.primaryVelocity ?? 0) > 700) {
      Navigator.of(context).maybePop();
      return;
    }
    _from = _drag.value;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final media = MediaQuery.of(context);
    final maxH = (media.size.height - media.padding.top - media.viewInsets.bottom - 12) * widget.maxHeight;
    final header = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _dragUpdate,
      onVerticalDragEnd: (d) => _dragEnd(d, maxH),
      child: Column(children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: kit.ink.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(2))),
        if (widget.title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(header: true, child: Text(widget.title!, style: kit.title.copyWith(fontSize: 20))),
                  if (widget.subtitle != null) ...[const SizedBox(height: 3), Text(widget.subtitle!, style: kit.caption)],
                ]),
              ),
              ?widget.trailing,
            ]),
          )
        else
          const SizedBox(height: 10),
      ]),
    );
    final body = Padding(padding: widget.padding, child: widget.child);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 640, maxHeight: maxH),
          child: ValueListenableBuilder<double>(
            valueListenable: _drag,
            builder: (context, dy, child) => Transform.translate(offset: Offset(0, dy), child: child),
            child: Material(
              type: MaterialType.transparency,
              child: DefaultTextStyle(
                style: kit.body,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: kit.sheet,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(top: BorderSide(color: kit.stroke)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      header,
                      Flexible(child: widget.scrollable ? SingleChildScrollView(child: body) : body),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A choice in [showKitActions].
class KitAction<T> {
  const KitAction(this.value, this.label,
      {this.icon, this.emoji, this.leadingColor, this.subtitle, this.destructive = false, this.selected = false});
  final T value;
  final String label;
  final IconData? icon;
  final String? emoji;

  /// A colour swatch in place of an icon.
  final Color? leadingColor;
  final String? subtitle;
  final bool destructive;
  final bool selected;
}

/// A menu of actions in a sheet (replaces popup menus and option lists).
Future<T?> showKitActions<T>(BuildContext context, {String? title, String? subtitle, required List<KitAction<T>> actions}) {
  return showKitSheet<T>(
    context,
    title: title,
    subtitle: subtitle,
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
    builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
      for (final a in actions)
        KitRow(
          title: a.label,
          subtitle: a.subtitle,
          icon: a.icon,
          emoji: a.emoji,
          leading: a.leadingColor == null
              ? null
              : Container(width: 26, height: 26, margin: const EdgeInsets.all(5), decoration: BoxDecoration(shape: BoxShape.circle, color: a.leadingColor)),
          destructive: a.destructive,
          selected: a.selected,
          chevron: false,
          onTap: () => Navigator.of(ctx).pop(a.value),
        ),
    ]),
  );
}

// ---------------------------------------------------------------- dialogs

/// A button in [showKitDialog].
class KitDialogAction<T> {
  const KitDialogAction(this.label, {this.value, this.primary = false, this.destructive = false});
  final String label;
  final T? value;
  final bool primary;
  final bool destructive;
}

/// A centred card that fades and grows in (replaces alert dialogs).
Future<T?> showKitDialog<T>(
  BuildContext context, {
  String? title,
  String? message,
  Widget? content,
  List<KitDialogAction<T>> actions = const [],
  bool dismissible = true,
}) {
  final kit = Kit.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push<T>(_KitDialogRoute<T>(
    kit: kit,
    dismissible: dismissible,
    builder: (ctx) => InheritedTheme.captureAll(
      context,
      _KitDialog<T>(title: title, message: message, content: content, actions: actions),
      to: navigator.context,
    ),
  ));
}

/// Yes/no question; true when confirmed.
Future<bool> showKitConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirm = 'OK',
  String cancel = 'Cancel',
  bool destructive = false,
}) async {
  final ok = await showKitDialog<bool>(context, title: title, message: message, actions: [
    KitDialogAction(cancel, value: false),
    KitDialogAction(confirm, value: true, primary: true, destructive: destructive),
  ]);
  return ok ?? false;
}

class _KitDialogRoute<T> extends PopupRoute<T> {
  _KitDialogRoute({required this.builder, required this.kit, required this.dismissible});

  final WidgetBuilder builder;
  final Kit kit;
  final bool dismissible;

  @override
  Color? get barrierColor => kit.barrier;

  @override
  bool get barrierDismissible => dismissible;

  @override
  String? get barrierLabel => 'Close';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 240);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => builder(context);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeIn);
    return FadeTransition(
      opacity: curve,
      child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curve), child: child),
    );
  }
}

class _KitDialog<T> extends StatelessWidget {
  const _KitDialog({required this.actions, this.title, this.message, this.content});

  final String? title;
  final String? message;
  final Widget? content;
  final List<KitDialogAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    Widget button(KitDialogAction<T> a) => KitButton(
          label: a.label,
          expand: true,
          kind: a.destructive
              ? KitButtonKind.danger
              : a.primary
                  ? KitButtonKind.primary
                  : KitButtonKind.secondary,
          onPressed: () => Navigator.of(context).pop(a.value),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              type: MaterialType.transparency,
              child: DefaultTextStyle(
                style: kit.body,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                  decoration: BoxDecoration(
                    color: kit.sheet,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: kit.stroke),
                  ),
                  child: Semantics(
                    scopesRoute: true,
                    namesRoute: true,
                    explicitChildNodes: true,
                    label: title,
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (title != null) Text(title!, style: kit.title.copyWith(fontSize: 20)),
                      if (message != null) ...[const SizedBox(height: 8), Text(message!, style: kit.body.copyWith(color: kit.inkSoft))],
                      if (content != null) ...[const SizedBox(height: 14), content!],
                      if (actions.isNotEmpty) const SizedBox(height: 20),
                      if (actions.length == 2)
                        Row(children: [Expanded(child: button(actions[0])), const SizedBox(width: 10), Expanded(child: button(actions[1]))])
                      else
                        for (final a in actions) Padding(padding: const EdgeInsets.only(top: 8), child: button(a)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a line (or a few) of text in a sheet that sits above the keyboard.
Future<String?> showKitPrompt(
  BuildContext context, {
  required String title,
  String? message,
  String initial = '',
  String? hint,
  int maxLines = 1,
  String confirm = 'Save',
  int? maxLength,
  TextCapitalization capitalization = TextCapitalization.sentences,
}) {
  return showKitSheet<String>(
    context,
    title: title,
    subtitle: message,
    builder: (ctx) => _PromptBody(
      initial: initial,
      hint: hint,
      maxLines: maxLines,
      confirm: confirm,
      maxLength: maxLength,
      capitalization: capitalization,
    ),
  );
}

class _PromptBody extends StatefulWidget {
  const _PromptBody({
    required this.initial,
    required this.hint,
    required this.maxLines,
    required this.confirm,
    required this.maxLength,
    required this.capitalization,
  });

  final String initial;
  final String? hint;
  final int maxLines;
  final String confirm;
  final int? maxLength;
  final TextCapitalization capitalization;

  @override
  State<_PromptBody> createState() => _PromptBodyState();
}

class _PromptBodyState extends State<_PromptBody> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done() => Navigator.of(context).pop(_c.text.trim());

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KitTextField(
        controller: _c,
        hint: widget.hint,
        autofocus: true,
        maxLines: widget.maxLines,
        minLines: widget.maxLines > 1 ? 3 : null,
        maxLength: widget.maxLength,
        capitalization: widget.capitalization,
        textInputAction: widget.maxLines == 1 ? TextInputAction.done : TextInputAction.newline,
        onSubmitted: widget.maxLines == 1 ? (_) => _done() : null,
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: KitButton.secondary(label: 'Cancel', expand: true, onPressed: () => Navigator.of(context).pop())),
        const SizedBox(width: 10),
        Expanded(child: KitButton(label: widget.confirm, expand: true, onPressed: _done)),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------- toasts

OverlayEntry? _toast;

/// A short message that drops in at the top of the screen and leaves on its
/// own (swipe it up to dismiss). Replaces snack bars.
void showKitToast(
  BuildContext context,
  String message, {
  IconData? icon,
  String? emoji,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(milliseconds: 2200),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final kit = Kit.of(context);
  final old = _toast;
  if (old != null && old.mounted) old.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Toast(
      kit: kit,
      message: message,
      icon: icon,
      emoji: emoji,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: actionLabel == null ? duration : duration + const Duration(milliseconds: 1600),
      onGone: () {
        if (entry.mounted) entry.remove();
        if (identical(_toast, entry)) _toast = null;
      },
    ),
  );
  _toast = entry;
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  const _Toast({
    required this.kit,
    required this.message,
    required this.duration,
    required this.onGone,
    this.icon,
    this.emoji,
    this.actionLabel,
    this.onAction,
  });

  final Kit kit;
  final String message;
  final IconData? icon;
  final String? emoji;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final VoidCallback onGone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260), reverseDuration: const Duration(milliseconds: 180));
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(widget.duration, _hide);
  }

  void _hide() {
    if (!mounted || _leaving) return;
    _leaving = true;
    _timer?.cancel();
    _c.reverse().whenCompleteOrCancel(() {
      if (mounted) widget.onGone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kit = widget.kit;
    final top = MediaQuery.paddingOf(context).top;
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
    // Just below the top bars, so their buttons stay reachable; a toast
    // without an action lets every touch through.
    return Positioned(
      top: top + 68,
      left: 16,
      right: 16,
      child: IgnorePointer(
        ignoring: widget.actionLabel == null,
        child: Align(
        alignment: Alignment.topCenter,
        child: FadeTransition(
          opacity: _c,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, -0.7), end: Offset.zero).animate(curve),
            child: GestureDetector(
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) < 0) _hide();
              },
              child: Semantics(
                liveRegion: true,
                container: true,
                child: DefaultTextStyle(
                  style: kit.body,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 480),
                    padding: EdgeInsets.fromLTRB(16, 12, widget.actionLabel == null ? 18 : 8, 12),
                    decoration: BoxDecoration(
                      color: kit.sheet,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: kit.stroke),
                      boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6))],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (widget.emoji != null) ...[Text(widget.emoji!, style: const TextStyle(fontSize: 18)), const SizedBox(width: 10)],
                      if (widget.icon != null) ...[Icon(widget.icon, size: 20, color: kit.accent), const SizedBox(width: 10)],
                      Flexible(child: Text(widget.message, style: kit.strong.copyWith(fontSize: 14.5))),
                      if (widget.actionLabel != null) ...[
                        const SizedBox(width: 6),
                        KitPressable(
                          onTap: () {
                            _hide();
                            widget.onAction?.call();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Text(widget.actionLabel!, style: kit.strong.copyWith(fontSize: 14.5, color: kit.accent)),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------- time

/// Hour and minute wheels in a sheet (replaces the Material clock dialog).
Future<TimeOfDay?> showKitTimePicker(BuildContext context, {required TimeOfDay initial, String title = 'Pick a time', String? subtitle}) {
  return showKitSheet<TimeOfDay>(
    context,
    title: title,
    subtitle: subtitle,
    builder: (ctx) => _TimeWheels(initial: initial),
  );
}

class _TimeWheels extends StatefulWidget {
  const _TimeWheels({required this.initial});
  final TimeOfDay initial;

  @override
  State<_TimeWheels> createState() => _TimeWheelsState();
}

class _TimeWheelsState extends State<_TimeWheels> {
  late int _hour = widget.initial.hour;
  late int _minute = ((widget.initial.minute / 5).round() * 5).clamp(0, 55);
  late final _hours = FixedExtentScrollController(initialItem: _hour);
  late final _minutes = FixedExtentScrollController(initialItem: _minute ~/ 5);

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  String _hourLabel(int h, bool h24) {
    if (h24) return h.toString().padLeft(2, '0');
    final twelve = h % 12 == 0 ? 12 : h % 12;
    return '$twelve ${h < 12 ? 'am' : 'pm'}';
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required int selected,
    required String Function(int) label,
    required ValueChanged<int> onChanged,
    required String semantic,
  }) {
    final kit = Kit.of(context);
    return Semantics(
      label: semantic,
      value: label(selected),
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 46,
        diameterRatio: 1.5,
        perspective: 0.004,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (i) {
          HapticFeedback.selectionClick();
          onChanged(i);
        },
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (context, i) => Center(
            child: Text(label(i), style: kit.title.copyWith(color: i == selected ? kit.ink : kit.inkSoft.withValues(alpha: 0.6))),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 200,
        child: Stack(children: [
          Center(
            child: Container(height: 48, decoration: BoxDecoration(color: kit.field, borderRadius: BorderRadius.circular(16))),
          ),
          Row(children: [
            Expanded(
              child: _wheel(
                controller: _hours,
                count: 24,
                selected: _hour,
                label: (i) => _hourLabel(i, h24),
                onChanged: (i) => setState(() => _hour = i),
                semantic: 'Hour',
              ),
            ),
            Text(':', style: kit.title),
            Expanded(
              child: _wheel(
                controller: _minutes,
                count: 12,
                selected: _minute ~/ 5,
                label: (i) => (i * 5).toString().padLeft(2, '0'),
                onChanged: (i) => setState(() => _minute = i * 5),
                semantic: 'Minute',
              ),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      KitButton(label: 'Set time', expand: true, onPressed: () => Navigator.of(context).pop(TimeOfDay(hour: _hour, minute: _minute))),
    ]);
  }
}
