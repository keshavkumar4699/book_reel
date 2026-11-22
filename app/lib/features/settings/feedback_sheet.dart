import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/api_client.dart';
import '../../services/error_reporter.dart';
import '../../ui/haptics.dart';
import '../../ui/kit.dart';
import '../../l10n/l10n.dart';

enum FeedbackKind { idea, problem, other }

/// The app's version as people see it: "1.0.0 (57)" from "1.0.0+57".
String appVersionLabel([String version = ErrorReporter.version]) {
  final parts = version.split('+');
  return parts.length == 2 ? '${parts[0]} (${parts[1]})' : version;
}

/// Settings → Send feedback (Production plan B8): an idea, a problem or
/// anything else, with an optional email for a reply. With online features
/// it goes to the Cloro server; without, the phone's share sheet sends it
/// (by email or any app). The app version and phone are added only if the
/// reader leaves that on.
Future<void> showFeedbackSheet(BuildContext context) =>
    showKitSheet<void>(context, title: tr('Send feedback'), subtitle: tr('Ideas and problems are read by a person'), builder: (_) => const _FeedbackForm());

class _FeedbackForm extends ConsumerStatefulWidget {
  const _FeedbackForm();

  @override
  ConsumerState<_FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends ConsumerState<_FeedbackForm> {
  final _message = TextEditingController();
  final _contact = TextEditingController();
  FeedbackKind _kind = FeedbackKind.idea;
  bool _details = true;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    _contact.dispose();
    super.dispose();
  }

  String get _device => _details ? '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'.trim() : '';

  Future<void> _send() async {
    final message = _message.text.trim();
    if (message.isEmpty) {
      setState(() => _error = tr('Write a few words first.'));
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final api = ref.read(apiProvider);
    final locale = Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? '';
    final contact = _contact.text.trim();
    if (api.enabled) {
      try {
        await api.sendFeedback(
          kind: _kind.name,
          message: message,
          contact: contact,
          version: _details ? ErrorReporter.version : '',
          platform: _details ? Platform.operatingSystem : '',
          locale: _details ? locale : '',
          device: _device.length > 120 ? _device.substring(0, 120) : _device,
        );
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() {
          _sending = false;
          _error = e.status == 429 ? tr('That’s a lot of feedback for one hour. Try again later.') : tr('It didn’t send. Check your connection and try again.');
        });
        return;
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _sending = false;
          _error = tr('It didn’t send. Check your connection and try again.');
        });
        return;
      }
      Haptics.success();
      if (!mounted) return;
      final messenger = Navigator.of(context);
      showKitToast(context, tr('Thanks! Your feedback was sent.'), emoji: '💌');
      messenger.pop();
      return;
    }
    // No server: the phone's share sheet (email or any app).
    final text = [
      message,
      if (contact.isNotEmpty) '\n${tr('Reply to: {contact}', {'contact': contact})}',
      if (_details) '\nCloro ${appVersionLabel()} · $_device${locale.isEmpty ? '' : ' · $locale'}',
    ].join('\n');
    await SharePlus.instance.share(ShareParams(text: text, subject: 'Cloro feedback: ${_kind.name}'));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    Widget label(String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(t, style: kit.label));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      KitSegmented<FeedbackKind>(
        values: FeedbackKind.values,
        selected: _kind,
        label: (k) => switch (k) {
          FeedbackKind.idea => tr('Idea'),
          FeedbackKind.problem => tr('Problem'),
          FeedbackKind.other => tr('Other'),
        },
        onChanged: (k) => setState(() => _kind = k),
      ),
      label(tr('YOUR MESSAGE')),
      KitTextField(
        controller: _message,
        hint: _kind == FeedbackKind.problem ? tr('What happened, and what did you expect?') : tr('What would make Cloro better for you?'),
        maxLines: 6,
        minLines: 4,
        maxLength: 2000,
        semanticLabel: tr('Your message'),
      ),
      label(tr('EMAIL FOR A REPLY (OPTIONAL)')),
      KitTextField(
        controller: _contact,
        hint: tr('you@example.com'),
        keyboardType: TextInputType.emailAddress,
        capitalization: TextCapitalization.none,
        maxLength: 200,
        semanticLabel: tr('Email for a reply'),
      ),
      const SizedBox(height: 6),
      KitSwitchRow(
        icon: Icons.phone_android_rounded,
        title: tr('Include app version and phone'),
        subtitle: 'Cloro ${appVersionLabel()} · ${Platform.operatingSystem}',
        value: _details,
        onChanged: (v) => setState(() => _details = v),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: kit.caption.copyWith(color: kit.danger)),
      ],
      const SizedBox(height: 16),
      KitButton(label: _sending ? tr('Sending…') : tr('Send'), icon: Icons.send_rounded, expand: true, onPressed: _sending ? null : _send),
    ]);
  }
}
