import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ui/kit.dart';

/// Open-source licences (fonts, scene sounds, packages), in the app's own
/// style instead of the stock licence page.
class LicensesScreen extends StatefulWidget {
  const LicensesScreen({super.key});

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  late final Future<Map<String, List<String>>> _licenses = _load();

  static Future<Map<String, List<String>>> _load() async {
    final out = <String, List<String>>{};
    await for (final entry in LicenseRegistry.licenses) {
      final text = entry.paragraphs.map((p) => '${'  ' * p.indent.clamp(0, 8)}${p.text}').join('\n\n');
      for (final package in entry.packages) {
        (out[package] ??= []).add(text);
      }
    }
    return Map.fromEntries(out.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())));
  }

  @override
  Widget build(BuildContext context) {
    final kit = Kit.of(context);
    return FutureBuilder<Map<String, List<String>>>(
      future: _licenses,
      builder: (context, snap) {
        final data = snap.data;
        return KitPage(
          title: 'Licences',
          subtitle: 'Fonts, scene sounds, dictionary and code that Cloro is built on',
          children: [
            if (data == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: KitSpinner()))
            else
              KitGroup(children: [
                for (final e in data.entries)
                  KitRow(
                    title: e.key,
                    subtitle: e.value.length == 1 ? null : '${e.value.length} licences',
                    onTap: () => showKitSheet<void>(
                      context,
                      title: e.key,
                      builder: (_) => SelectableText(e.value.join('\n\n— — —\n\n'), style: kit.caption.copyWith(color: kit.ink)),
                    ),
                  ),
              ]),
          ],
        );
      },
    );
  }
}
