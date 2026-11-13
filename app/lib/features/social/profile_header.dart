import 'package:flutter/material.dart';

import '../../ui/kit.dart';

/// Another reader's picture: their emoji, or their initial. (Photos stay on
/// their own phone.)
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, this.emoji = '', this.size = 40});

  final String name;
  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    final n = name.trim();
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: kit.field,
          child: Center(
            child: emoji.isNotEmpty
                ? Text(emoji, style: TextStyle(fontSize: size * 0.5))
                : Text(n.isEmpty || n == 'Reader' ? '📖' : n.characters.first.toUpperCase(),
                    style: kit.title.copyWith(color: kit.ink, fontSize: size * 0.42)),
          ),
        ),
      ),
    );
  }
}

/// A profile's header, Strava-style (Cloro plan §11), for yours and other
/// readers':
///
/// ```
/// [ photo ]  Name · she/her
///            128 followers · 96 following
/// Short bio
/// 📖 Reading: Pride and Prejudice
/// Fantasy · History · Poetry
/// [ actions ]
/// ```
///
/// The counts are left out when they aren't known (offline): no false zeros.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.avatar,
    required this.name,
    this.pronouns = '',
    this.followers,
    this.following,
    this.onFollowers,
    this.onFollowing,
    this.bio = '',
    this.onAddBio,
    this.reading,
    this.onReading,
    this.genres = const [],
    this.extra,
    this.actions = const [],
  });

  final Widget avatar;
  final String name;
  final String pronouns;
  final int? followers;
  final int? following;
  final VoidCallback? onFollowers;
  final VoidCallback? onFollowing;
  final String bio;

  /// Your own profile with no bio yet: a gentle prompt instead.
  final VoidCallback? onAddBio;
  final String? reading;
  final VoidCallback? onReading;

  /// Up to 3 are shown.
  final List<String> genres;

  /// A line under the name (e.g. "Follows you", a streak).
  final Widget? extra;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    String count(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        avatar,
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: name, style: kit.strong.copyWith(fontSize: 18)),
                if (pronouns.trim().isNotEmpty) TextSpan(text: '  ·  ${pronouns.trim()}', style: kit.caption),
              ]),
            ),
            if (followers != null && following != null) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 4, children: [
                _CountLink(label: count(followers!, 'follower', 'followers'), onTap: onFollowers),
                Text('·', style: kit.caption),
                _CountLink(label: '${following!} following', onTap: onFollowing),
              ]),
            ],
            if (extra != null) ...[const SizedBox(height: 6), extra!],
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      if (bio.trim().isNotEmpty)
        Text(bio.trim(), style: kit.body)
      else if (onAddBio != null)
        GestureDetector(onTap: onAddBio, child: Text('Add a bio: what you love to read, and why', style: kit.caption)),
      if (reading != null && reading!.isNotEmpty) ...[
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onReading,
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '📖 Reading: ', style: kit.caption),
            TextSpan(text: reading, style: kit.body.copyWith(fontWeight: FontWeight.w600)),
          ])),
        ),
      ],
      if (genres.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(genres.take(3).join(' · '), style: kit.caption),
      ],
      if (actions.isNotEmpty) ...[
        const SizedBox(height: 14),
        Row(children: [
          for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: a)],
        ]),
      ],
    ]);
  }
}

class _CountLink extends StatelessWidget {
  const _CountLink({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    return Semantics(
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Text(label, style: kit.body.copyWith(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
