import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../ui/haptics.dart';
import '../../ui/kit.dart';
import 'profile_header.dart';
import '../../l10n/l10n.dart';

/// What to tell the reader when the server says no.
String apiErrorMessage(Object e, {String? fallback}) {
  fallback ??= tr('Couldn’t reach Cloro. Check your connection.');
  if (e is ApiException) {
    if (e.rateLimited) return tr('That’s a lot at once. Try again in a minute.');
    final m = e.message;
    if (m != null && e.status == 400) return m;
  }
  return fallback;
}

/// Why something is being reported (the server's reasons).
List<(String, String)> get reportReasons => [
  ('spam', tr('Spam')),
  ('harassment', tr('Harassment or bullying')),
  ('hate', tr('Hate')),
  ('sexual', tr('Sexual content')),
  ('self_harm', tr('Self-harm')),
  ('impersonation', tr('Pretending to be someone')),
  ('other', tr('Something else')),
];

/// Report a reader, an activity or a comment: pick a reason, then it's sent.
/// Returns whether a report was sent.
Future<bool> showReportSheet(BuildContext context, WidgetRef ref, {required String type, required String id}) async {
  final what = switch (type) { 'comment' => tr('this comment'), 'activity' => tr('this post'), _ => tr('this reader') };
  final reason = await showKitActions<String>(
    context,
    title: tr('Report {what}', {'what': what}),
    subtitle: tr('Reports are private. Someone at Cloro looks at each one.'),
    actions: [for (final (value, label) in reportReasons) KitAction(value, label)],
  );
  if (reason == null || !context.mounted) return false;
  try {
    await ref.read(apiProvider).report(type: type, id: id, reason: reason);
    if (context.mounted) showKitToast(context, tr('Thanks for telling us. We’ll take a look.'), icon: Icons.flag_rounded);
    return true;
  } catch (e) {
    if (context.mounted) showKitToast(context, apiErrorMessage(e), icon: Icons.cloud_off_rounded);
    return false;
  }
}

/// Block a reader, after saying what it does. Returns whether they're blocked.
Future<bool> confirmBlock(BuildContext context, WidgetRef ref, {required String userId, required String name}) async {
  final ok = await showKitConfirm(
    context,
    title: tr('Block {name}?', {'name': name}),
    message: tr('You’ll stop following each other, and neither of you will see the other’s profile, reading or comments. '
        'They aren’t told. You can unblock them in Settings.'),
    confirm: tr('Block'),
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  try {
    await ref.read(apiProvider).block(userId);
    Haptics.press();
    if (context.mounted) showKitToast(context, tr('{name} is blocked', {'name': name}), icon: Icons.block_rounded);
    return true;
  } catch (e) {
    if (context.mounted) showKitToast(context, apiErrorMessage(e), icon: Icons.cloud_off_rounded);
    return false;
  }
}

/// The "⋯" choices on someone else's profile, post or comment.
Future<void> showSafetyActions(
  BuildContext context,
  WidgetRef ref, {
  required String type,
  required String id,
  required String userId,
  required String name,
  VoidCallback? onBlocked,
}) async {
  final choice = await showKitActions<String>(context, actions: [
    KitAction('report', switch (type) { 'comment' => 'Report comment', 'activity' => 'Report post', _ => tr('Report {name}', {'name': name}) }, icon: Icons.flag_outlined),
    KitAction('block', tr('Block {name}', {'name': name}), icon: Icons.block_rounded, destructive: true),
  ]);
  if (!context.mounted || choice == null) return;
  if (choice == 'report') {
    await showReportSheet(context, ref, type: type, id: id);
  } else if (await confirmBlock(context, ref, userId: userId, name: name)) {
    onBlocked?.call();
  }
}

final blockedProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.read(apiProvider).blocked());

/// Settings → Blocked readers: who you've blocked, with Unblock.
class BlockedReaders extends ConsumerWidget {
  const BlockedReaders({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kit = Kit.of(context);
    return ref.watch(blockedProvider).when(
          loading: () => const Padding(padding: EdgeInsets.all(30), child: Center(child: KitSpinner())),
          error: (e, _) => Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(apiErrorMessage(e), style: kit.caption)),
          data: (items) => items.isEmpty
              ? Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(tr('You haven’t blocked anyone.'), style: kit.caption))
              : KitGroup(children: [
                  for (final p in items)
                    KitRow(
                      leading: PersonAvatar(name: '${p['display_name']}', emoji: '${p['avatar'] ?? ''}', size: 36),
                      title: '${p['display_name']}',
                      subtitle: p['handle'] == null ? null : '@${p['handle']}',
                      chevron: false,
                      trailing: KitButton.secondary(
                        label: tr('Unblock'),
                        compact: true,
                        onPressed: () async {
                          try {
                            await ref.read(apiProvider).unblock('${p['user_id']}');
                            ref.invalidate(blockedProvider);
                          } catch (e) {
                            if (context.mounted) showKitToast(context, apiErrorMessage(e), icon: Icons.cloud_off_rounded);
                          }
                        },
                      ),
                    ),
                ]),
        );
  }
}
