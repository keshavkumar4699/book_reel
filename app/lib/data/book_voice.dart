import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/book.dart';
import '../core/text/voice_classifier.dart';
import '../ui/typography.dart';
import 'api_client.dart';
import 'library.dart';
import 'settings.dart';
import 'settings_provider.dart';

/// Gives every book a typographic voice: the on-device guess straight away,
/// then, on paid tiers, the AI's choice (asked once per book and stored on
/// the library entry, so it works offline afterwards).
class BookVoiceService {
  BookVoiceService(this.ref);

  final Ref ref;
  final Set<String> _asked = {};

  Future<void> ensure(String bookId, BookContent book) async {
    final library = ref.read(libraryProvider.notifier);
    var meta = library.byId(bookId);
    if (meta == null) return;
    if (meta.voice == null) {
      final guess = classifyVoice(title: book.title, author: book.author, subjects: meta.subjects, sample: voiceSample(book));
      library.setVoice(bookId, guess.voice.name, 'rules');
      meta = library.byId(bookId);
    }
    final settings = ref.read(settingsProvider);
    final api = ref.read(apiProvider);
    if (settings.tier == Tier.free || !api.enabled || meta == null || meta.voiceSource == 'ai') return;
    if (!_asked.add(bookId)) return;
    try {
      final voice = await api.bookProfile(
        settings.tier.name,
        title: book.title,
        author: book.author,
        contentHash: bookId,
        subjects: meta.subjects,
        sample: voiceSample(book, words: 900),
      );
      if (BookVoice.values.any((v) => v.name == voice)) library.setVoice(bookId, voice, 'ai');
    } catch (e) {
      debugPrint('Book design unavailable, keeping the on-device choice: $e');
    }
  }
}

final bookVoiceProvider = Provider<BookVoiceService>(BookVoiceService.new);
