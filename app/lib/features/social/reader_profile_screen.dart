import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../ui/haptics.dart';
import '../../ui/kit.dart';
import 'people_screen.dart';
import '../journal/feed.dart' show journalFeedProvider;
import 'profile_header.dart';
import 'safety.dart';
import '../../l10n/l10n.dart';

/// Another reader's public profile ("me", a user id or "@handle").
final readerProfileProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, id) => ref.read(apiProvider).profile(id));

/// Another reader's profile (Cloro plan §11): the same header as yours, with
/// Follow / Following, "Follows you" and their streak.
class ReaderProfileScreen extends ConsumerStatefulWidget {
  const ReaderProfileScreen({super.key, required this.id});

  /// A user id or "@handle".
  final String id;

  @override
  ConsumerState<ReaderProfileScreen> createState() => _ReaderProfileScreenState();
}

class _ReaderProfileScreenState extends ConsumerState<ReaderProfileScreen> {
  /// Set while a follow change is on its way (shown at once).
  bool? _following;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final async = ref.watch(readerProfileProvider(widget.id));
    final p = async.value;
    final List<Widget> children = async.when(
      loading: () => const [Padding(padding: EdgeInsets.all(60), child: Center(child: KitSpinner()))],
      error: (e, _) => [
        KitEmpty(
          emoji: '☁️',
          title: tr('Can’t reach Cloro right now'),
          message: tr('Try again in a moment.'),
          action: KitButton.secondary(label: tr('Try again'), onPressed: () => ref.invalidate(readerProfileProvider(widget.id))),
        ),
      ],
      data: (p) => p == null
          ? [KitEmpty(emoji: '🔍', title: tr('No reader found'), message: tr('They may have changed their username.'))]
          : _profile(context, kit, p),
    );
    final handle = p?['handle'] as String?;
    return KitPage(
      back: true,
      backdrop: true,
      title: handle != null && handle.isNotEmpty ? '@$handle' : (p?['display_name'] as String? ?? 'Reader'),
      onRefresh: () => ref.refresh(readerProfileProvider(widget.id).future),
      actions: [
        if (p != null && p['me'] != true)
          KitIconButton(
            icon: Icons.more_horiz_rounded,
            semanticLabel: tr('More: report or block'),
            onPressed: () => showSafetyActions(
              context,
              ref,
              type: 'user',
              id: p['user_id'] as String,
              userId: p['user_id'] as String,
              name: (p['display_name'] as String?) ?? tr('this reader'),
              onBlocked: () {
                refreshSocial(ref);
                ref.invalidate(journalFeedProvider);
                if (context.mounted) Navigator.of(context).maybePop();
              },
            ),
          ),
      ],
      children: [DefaultTextStyle(style: kit.body, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))],
    );
  }

  List<Widget> _profile(BuildContext context, Kit kit, Map<String, dynamic> p) {
    final id = p['user_id'] as String;
    final name = (p['display_name'] as String?) ?? 'Reader';
    final me = p['me'] == true;
    final following = _following ?? p['you_follow'] == true;
    final streak = (p['streak'] as Map?)?.cast<String, dynamic>() ?? const {};
    final current = (streak['current'] as num?)?.toInt() ?? 0;
    final best = (streak['best'] as num?)?.toInt() ?? 0;
    // Counts move with a follow made here, before the server is asked again.
    final followers = ((p['followers'] as num?)?.toInt() ?? 0) + (following == (p['you_follow'] == true) ? 0 : (following ? 1 : -1));
    void lists(PeopleTab tab) =>
        context.push(Uri(path: '/people/${Uri.encodeComponent(id)}', queryParameters: {'tab': tab.name, 'name': name}).toString());
    return [
      ProfileHeader(
        avatar: PersonAvatar(name: name, emoji: (p['avatar'] as String?) ?? '', size: 88),
        name: name,
        pronouns: (p['pronouns'] as String?) ?? '',
        followers: followers,
        following: (p['following'] as num?)?.toInt() ?? 0,
        onFollowers: () => lists(PeopleTab.followers),
        onFollowing: () => lists(PeopleTab.following),
        bio: (p['bio'] as String?) ?? '',
        reading: p['reading'] as String?,
        genres: ((p['genres'] as List?) ?? const []).cast<String>(),
        extra: p['follows_you'] == true && !me ? Text(tr('Follows you'), style: kit.caption) : null,
        actions: [
          if (me)
            KitButton.secondary(label: tr('Edit your profile'), expand: true, onPressed: () => context.go('/profile'))
          else
            FollowButton(following: following, expand: true, onPressed: () => _toggle(id, following)),
        ],
      ),
      const KitDivider(),
      KitGroup(children: [
        KitRow(emoji: '🔥', title: tr('{n}-day streak', {'n': current}), value: tr('Best {n}', {'n': best}), chevron: false),
      ]),
    ];
  }

  Future<void> _toggle(String id, bool following) async {
    Haptics.tap();
    setState(() => _following = !following);
    try {
      final api = ref.read(apiProvider);
      following ? await api.unfollow(id) : await api.follow(id);
      refreshSocial(ref);
    } catch (_) {
      if (!mounted) return;
      setState(() => _following = following);
      showKitToast(context, tr('Couldn’t update. Check your connection.'), icon: Icons.cloud_off_rounded);
    }
  }
}
