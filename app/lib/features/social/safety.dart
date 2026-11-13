import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../ui/kit.dart';
import 'profile_header.dart';

/// What to tell the reader when the server says no.
String apiErrorMessage(Object e, {String fallback = 'Couldn’t reach Cloro. Check your connection.'}) {
  if (e is ApiException) {
    if (e.rateLimited) return 'That’s a lot at once. Try again in a minute.';
    final m = e.message;
    if (m != null && e.status == 400) return m;
  }
  return fallback;
}

/// Why something is being reported (the server's reasons).
const reportReasons = <(String, String)>[
  ('spam', 'Spam'),
  ('harassment', 'Harassment or bullying'),
  ('hate', 'Hate'),
  ('sexual', 'Sexual content'),
  ('self_harm', 'Self-harm'),
  ('impersonation', 'Pretending to be someone'),
  ('other', 'Something else'),
];

/// Report a reader, an activity or a comment: pick a reason, then it's sent.
/// Returns whether a report was sent.
Future<bool> showReportSheet(BuildContext context, WidgetRef ref, {required String type, required String id}) async {
  final what = switch (type) { 'comment' => 'this comment', 'activity' => 'this post', _ => 'this reader' };
  final reason = await showKitActions<String>(
    context,
    title: 'Report $what',
    subtitle: 'Reports are private. Someone at Cloro looks at each one.',
    actions: [for (final (value, label) in reportReasons) KitAction(value, label)],
  );
  if (reason == null || !context.mounted) return false;
  try {
    await ref.read(apiProvider).report(type: type, id: id, reason: reason);
    if (context.mounted) showKitToast(context, 'Thanks for telling us. We’ll take a look.', icon: Icons.flag_rounded);
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
    title: 'Block $name?',
    message: 'You’ll stop following each other, and neither of you will see the other’s profile, reading or comments. '
        'They aren’t told. You can unblock them in Settings.',
    confirm: 'Block',
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  try {
    await ref.read(apiProvider).block(userId);
    HapticFeedback.mediumImpact();
    if (context.mounted) showKitToast(context, '$name is blocked', icon: Icons.block_rounded);
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
    KitAction('report', switch (type) { 'comment' => 'Report comment', 'activity' => 'Report post', _ => 'Report $name' }, icon: Icons.flag_outlined),
    KitAction('block', 'Block $name', icon: Icons.block_rounded, destructive: true),
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
              ? Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text('You haven’t blocked anyone.', style: kit.caption))
              : KitGroup(children: [
                  for (final p in items)
                    KitRow(
                      leading: PersonAvatar(name: '${p['display_name']}', emoji: '${p['avatar'] ?? ''}', size: 36),
                      title: '${p['display_name']}',
                      subtitle: p['handle'] == null ? null : '@${p['handle']}',
                      chevron: false,
                      trailing: KitButton.secondary(
                        label: 'Unblock',
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
