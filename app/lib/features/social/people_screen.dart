import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../friends/friends_screen.dart' show InviteCard;
import '../../ui/kit.dart';
import 'profile_header.dart';

enum PeopleTab {
  followers('Followers'),
  following('Following');

  const PeopleTab(this.label);
  final String label;
}

/// Your account as the server sees it: id, invite code, follower counts.
final socialMeProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.read(apiProvider).me());

/// A reader's followers or following ("me", a user id or "@handle").
final peopleProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, (String, PeopleTab)>((ref, key) {
  final api = ref.read(apiProvider);
  return key.$2 == PeopleTab.followers ? api.followers(key.$1) : api.following(key.$1);
});

/// After a follow or unfollow: counts and lists everywhere are refreshed.
void refreshSocial(WidgetRef ref) {
  ref.invalidate(socialMeProvider);
  ref.invalidate(peopleProvider);
}

/// Followers and following (Cloro plan §11), with Find people and your
/// invite on your own lists.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key, this.userId = 'me', this.tab = PeopleTab.followers, this.name});

  /// "me", a user id or "@handle".
  final String userId;
  final PeopleTab tab;

  /// Whose lists, for the title (another reader's).
  final String? name;

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  late PeopleTab _tab = widget.tab;

  bool get _own => widget.userId == 'me';

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider);
    final kit = Kit.of(context);
    final key = (widget.userId, _tab);
    final List<Widget> children;
    if (!api.enabled) {
      children = const [
        KitEmpty(emoji: '☁️', title: 'Following needs the Cloro server', message: 'Your reading is saved on this phone.'),
      ];
    } else {
      final me = ref.watch(socialMeProvider).value;
      children = [
        KitSegmented<PeopleTab>(values: PeopleTab.values, selected: _tab, label: (t) => t.label, onChanged: (t) => setState(() => _tab = t)),
        const SizedBox(height: 8),
        if (_own)
          KitGroup(children: [
            KitRow(icon: Icons.person_search_rounded, title: 'Find people', subtitle: 'Follow a reader by their @username', onTap: _find),
            KitRow(icon: Icons.key_rounded, title: 'Follow by invite code', onTap: _byCode),
          ]),
        ...ref.watch(peopleProvider(key)).when(
              loading: () => const [Padding(padding: EdgeInsets.all(48), child: Center(child: KitSpinner()))],
              error: (e, _) => [
                KitEmpty(
                  emoji: '☁️',
                  title: 'Can’t reach Cloro right now',
                  message: 'Try again in a moment.',
                  action: KitButton.secondary(label: 'Try again', onPressed: () => ref.invalidate(peopleProvider(key))),
                ),
              ],
              data: (people) => [
                if (people.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Text(
                      _tab == PeopleTab.followers
                          ? (_own ? 'No followers yet. Share your invite below.' : 'No followers yet.')
                          : (_own ? 'You don’t follow anyone yet. Find people by their @username.' : 'Not following anyone yet.'),
                      textAlign: TextAlign.center,
                      style: kit.caption,
                    ),
                  )
                else
                  KitGroup(divided: _own, children: [
                    for (final p in people) _PersonRow(person: p, myId: me?['user_id'] as String?),
                  ]),
              ],
            ),
        if (_own && me != null) ...[
          const KitDivider(),
          InviteCard(code: me['invite_code'] as String, url: me['invite_url'] as String),
        ],
      ];
    }
    return KitPage(
      back: true,
      backdrop: true,
      title: _own ? 'People' : (widget.name ?? 'People'),
      onRefresh: api.enabled
          ? () async {
              refreshSocial(ref);
              await ref.read(peopleProvider(key).future);
            }
          : null,
      children: [DefaultTextStyle(style: kit.body, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))],
    );
  }

  Future<void> _find() async {
    final handle = await showKitPrompt(
      context,
      title: 'Find people',
      message: 'Follow a reader by their @username',
      hint: '@username',
      confirm: 'Follow',
    );
    if (handle == null || handle.trim().isEmpty || !mounted) return;
    final name = handle.trim().replaceFirst(RegExp('^@'), '');
    try {
      final user = await ref.read(apiProvider).followHandle(name);
      if (!mounted) return;
      if (user == null) {
        showKitToast(context, 'No reader is called @$name.');
        return;
      }
      HapticFeedback.selectionClick();
      showKitToast(context, 'You now follow ${user['display_name']}');
      refreshSocial(ref);
      setState(() => _tab = PeopleTab.following);
    } catch (_) {
      if (mounted) showKitToast(context, 'Couldn’t follow. Check your connection.', icon: Icons.cloud_off_rounded);
    }
  }

  Future<void> _byCode() async {
    final code = await showKitPrompt(
      context,
      title: 'Follow by invite code',
      message: 'Enter their invite code: you’ll follow each other',
      hint: 'e.g. 7PA756JQ',
      confirm: 'Follow',
      capitalization: TextCapitalization.characters,
    );
    if (code == null || code.isEmpty || !mounted) return;
    try {
      final name = await ref.read(apiProvider).addFriend(code);
      if (!mounted) return;
      showKitToast(context, name == null ? 'No reader found with that code.' : 'You and $name now follow each other 🎉');
      if (name != null) refreshSocial(ref);
    } catch (_) {
      if (mounted) showKitToast(context, 'Couldn’t follow. Check your connection.', icon: Icons.cloud_off_rounded);
    }
  }
}

/// One reader in a list: tap for their profile; Follow / Following beside.
class _PersonRow extends ConsumerStatefulWidget {
  const _PersonRow({required this.person, required this.myId});
  final Map<String, dynamic> person;
  final String? myId;

  @override
  ConsumerState<_PersonRow> createState() => _PersonRowState();
}

class _PersonRowState extends ConsumerState<_PersonRow> {
  late bool _following = widget.person['you_follow'] == true;
  bool _busy = false;

  @override
  void didUpdateWidget(_PersonRow old) {
    super.didUpdateWidget(old);
    // Only when the list itself has news (a refresh), not on every rebuild.
    if (!_busy && old.person['you_follow'] != widget.person['you_follow']) _following = widget.person['you_follow'] == true;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.person;
    final id = p['user_id'] as String;
    final name = (p['display_name'] as String?) ?? 'Reader';
    final handle = p['handle'] as String?;
    return KitRow(
      leading: PersonAvatar(name: name, emoji: (p['avatar'] as String?) ?? '', size: 44),
      title: name,
      subtitle: handle == null || handle.isEmpty ? null : '@$handle',
      chevron: false,
      trailing: id == widget.myId ? null : FollowButton(following: _following, onPressed: _toggle),
      onTap: () => context.push('/u/${Uri.encodeComponent(id)}'),
    );
  }

  Future<void> _toggle() async {
    final id = widget.person['user_id'] as String;
    final follow = !_following;
    HapticFeedback.selectionClick();
    setState(() {
      _following = follow;
      _busy = true;
    });
    try {
      final api = ref.read(apiProvider);
      follow ? await api.follow(id) : await api.unfollow(id);
      ref.invalidate(socialMeProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() => _following = !follow);
      showKitToast(context, 'Couldn’t update. Check your connection.', icon: Icons.cloud_off_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// "Follow" (solid) or "Following" (quiet).
class FollowButton extends StatelessWidget {
  const FollowButton({super.key, required this.following, required this.onPressed, this.expand = false});
  final bool following;
  final VoidCallback onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) => following
      ? KitButton.secondary(label: 'Following', compact: !expand, expand: expand, onPressed: onPressed)
      : KitButton(label: 'Follow', compact: !expand, expand: expand, onPressed: onPressed);
}
