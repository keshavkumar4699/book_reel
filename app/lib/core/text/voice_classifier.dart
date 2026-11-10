/// On-device guess of a book's typographic voice (free tier, and the first
/// guess on paid tiers until the AI has looked at the book).
///
/// Signals, strongest first: the publisher's subject tags (`dc:subject`),
/// words in the title, then genre vocabulary and style in the opening pages
/// (dialogue, second person, archaic words, sentence length).
library;

import '../../ui/typography.dart';
import '../models/book.dart';

/// The opening pages of a book (skipping short front matter such as a
/// contents page), for genre detection.
String voiceSample(BookContent book, {int words = 4000}) {
  final out = StringBuffer();
  var count = 0;
  for (final c in book.chapters) {
    if (c.wordCount < 250 && book.chapters.length > 2) continue;
    for (final s in c.sentences) {
      out
        ..write(s.text)
        ..write(' ');
      count += s.wordCount;
      if (count >= words) return out.toString();
    }
  }
  return out.toString();
}

class VoiceGuess {
  const VoiceGuess(this.voice, this.scores);
  final BookVoice voice;
  final Map<BookVoice, double> scores;
}

const _subjectCues = <BookVoice, List<String>>{
  BookVoice.playful: ['juvenile', "children's", 'children', 'picture book', 'nursery', 'humor', 'humour', 'humorous', 'nonsense', 'comic'],
  BookVoice.fantasy: ['fantasy', 'fairy tale', 'fairy tales', 'mytholog', 'legend', 'folklore', 'magic', 'dragons', 'wizards', 'arthurian'],
  BookVoice.scifi: ['science fiction', 'sci-fi', 'space opera', 'cyberpunk', 'dystopia', 'robots', 'time travel', 'interplanetary', 'extraterrestrial'],
  BookVoice.suspense: ['mystery', 'detective', 'thriller', 'suspense', 'crime', 'horror', 'ghost', 'murder', 'gothic', 'noir', 'espionage', 'spy'],
  BookVoice.romance: ['romance', 'love stories', 'love story', 'courtship', 'romantic'],
  BookVoice.modern: ['self-help', 'self help', 'business', 'management', 'psychology', 'economics', 'personal development', 'success',
      'productivity', 'leadership', 'finance', 'investing', 'health', 'technology', 'popular science', 'science', 'motivation', 'habits'],
  BookVoice.classic: ['classics', 'literature', 'literary', 'poetry', 'essays', 'philosophy', 'history', 'biography', 'drama', 'fiction'],
};

/// Generic tags ("fiction", "history") are weaker than genre tags.
const _weakSubjects = {'fiction', 'literature', 'history', 'biography', 'science', 'drama'};

const _titleCues = <BookVoice, List<String>>{
  BookVoice.fantasy: ['dragon', 'magic', 'sword', 'wizard', 'kingdom', 'throne', 'quest', 'realm', 'witch', 'sorcer', 'elf', 'crown', 'spell', 'myth'],
  BookVoice.scifi: ['star', 'space', 'galaxy', 'robot', 'android', 'mars', 'planet', 'machine', 'cyber', 'quantum', 'martian', 'future', 'neuro'],
  BookVoice.suspense: ['murder', 'death', 'dead', 'kill', 'mystery', 'detective', 'blood', 'shadow', 'ghost', 'crime', 'case of', 'silent', 'missing', 'vanish'],
  BookVoice.romance: ['love', 'heart', 'bride', 'wedding', 'kiss', 'darling', 'beloved', 'romance', 'passion', 'pride and prejudice'],
  BookVoice.playful: ['little', 'adventures of', 'bear', 'bunny', 'rabbit', 'pig', 'kitten', 'puppy', 'wonderland', 'pooh', 'peter pan'],
  BookVoice.modern: ['how to', 'habit', 'guide', 'principles', 'mindset', 'thinking', 'success', 'rich', 'leader', 'psychology', 'power of',
      'art of', 'lessons', 'rules', 'atomic', 'deep work', 'secrets of'],
};

const _textCues = <BookVoice, List<String>>{
  BookVoice.fantasy: ['sword', 'swords', 'dragon', 'dragons', 'wizard', 'wizards', 'spell', 'spells', 'magic', 'magical', 'kingdom', 'castle',
      'elf', 'elves', 'dwarf', 'dwarves', 'quest', 'prophecy', 'enchanted', 'enchantment', 'sorcerer', 'sorceress', 'potion', 'realm', 'throne',
      'knight', 'knights', 'witch', 'goblin', 'goblins', 'troll', 'rune', 'runes', 'mage', 'staff', 'fairy', 'fairies'],
  BookVoice.scifi: ['planet', 'planets', 'spaceship', 'starship', 'galaxy', 'robot', 'robots', 'android', 'laser', 'orbit', 'alien', 'aliens',
      'quantum', 'hologram', 'colony', 'asteroid', 'spacecraft', 'computer', 'terraform', 'warp', 'hyperspace', 'airlock', 'cyborg', 'drone',
      'drones', 'reactor', 'module', 'thrusters', 'interface', 'simulation', 'algorithm'],
  BookVoice.suspense: ['murder', 'murdered', 'detective', 'inspector', 'police', 'killer', 'corpse', 'blood', 'crime', 'suspect', 'clue', 'clues',
      'victim', 'gun', 'knife', 'scream', 'screamed', 'poison', 'evidence', 'alibi', 'investigation', 'dead', 'death', 'body', 'terror', 'fear'],
  BookVoice.romance: ['kiss', 'kissed', 'kisses', 'love', 'loved', 'lover', 'darling', 'heart', 'lips', 'embrace', 'passion', 'wedding', 'marry',
      'married', 'marriage', 'beloved', 'blushed', 'sweetheart', 'caress', 'tender', 'affection', 'engaged', 'suitor'],
  BookVoice.playful: ['mummy', 'mommy', 'daddy', 'teddy', 'giggled', 'silly', 'bunny', 'puppy', 'kitten', 'toy', 'toys', 'hooray', 'granny',
      'grandma', 'rabbit', 'mouse', 'cat', 'dog', 'duck', 'pig', 'bear', 'frog', 'little', 'curious', 'nonsense', 'funny', 'tea'],
  BookVoice.modern: ['research', 'study', 'studies', 'data', 'percent', 'business', 'company', 'habit', 'habits',
      'success', 'strategy', 'example', 'results', 'brain', 'goal', 'goals', 'framework', 'principle', 'productivity', 'customers', 'market',
      'money', 'invest', 'leaders', 'team', 'skills', 'psychologists', 'scientists', 'experiment', 'researchers'],
  BookVoice.classic: ['thee', 'thou', 'thy', 'hath', 'doth', 'whilst', 'upon', 'shall', 'sir', 'madam', 'carriage', 'parlour', 'countenance',
      'exceedingly', 'ere', 'nay', 'indeed', 'gentleman', 'ladyship', 'perceive', 'amiable', 'agreeable', 'acquaintance', 'endeavour'],
};

/// Weight per cue hit in the sample text, per 1,000 words.
const _textWeight = <BookVoice, double>{
  BookVoice.fantasy: 1.4,
  BookVoice.scifi: 1.6,
  BookVoice.suspense: 0.9,
  BookVoice.romance: 0.6,
  BookVoice.playful: 0.35,
  BookVoice.modern: 0.25,
  BookVoice.classic: 0.6,
};

final RegExp _wordRe = RegExp(r"[a-z][a-z'’]*");

VoiceGuess classifyVoice({
  required String title,
  String author = '',
  List<String> subjects = const [],
  String description = '',
  required String sample,
}) {
  final scores = {for (final v in BookVoice.values) v: 0.0};

  // 1. Subject tags.
  for (final raw in subjects) {
    final subject = raw.toLowerCase();
    for (final e in _subjectCues.entries) {
      for (final cue in e.value) {
        if (!subject.contains(cue)) continue;
        scores[e.key] = scores[e.key]! + (_weakSubjects.contains(cue) ? 2.5 : (e.key == BookVoice.playful ? 10 : 8));
        break;
      }
    }
  }

  // 2. Title (and description, more weakly).
  final t = ' ${title.toLowerCase()} ';
  final d = ' ${description.toLowerCase()} ';
  for (final e in _titleCues.entries) {
    for (final cue in e.value) {
      if (t.contains(cue)) scores[e.key] = scores[e.key]! + 3;
      if (d.contains(cue)) scores[e.key] = scores[e.key]! + 1;
    }
  }

  // 3. Vocabulary and style of the opening pages.
  final words = _wordRe.allMatches(sample.toLowerCase()).map((m) => m.group(0)!).toList();
  if (words.isNotEmpty) {
    final counts = <String, int>{};
    for (final w in words) {
      counts[w] = (counts[w] ?? 0) + 1;
    }
    final per1k = 1000 / words.length;
    for (final e in _textCues.entries) {
      var hits = 0;
      for (final cue in e.value) {
        hits += counts[cue] ?? 0;
      }
      scores[e.key] = scores[e.key]! + hits * per1k * _textWeight[e.key]! / 4;
    }
    final sentences = sample.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.trim().isNotEmpty).toList();
    // An opening quotation mark (not an apostrophe inside a word).
    final opening = RegExp(r'(^|[\s(\[—–-])["“‘]');
    final dialogue = sentences.where(opening.hasMatch).length / (sentences.isEmpty ? 1 : sentences.length);
    final youRate = ((counts['you'] ?? 0) + (counts['your'] ?? 0)) * per1k;
    final modernHits = _textCues[BookVoice.modern]!.fold(0, (n, c) => n + (counts[c] ?? 0)) * per1k;
    final avgSentence = words.length / (sentences.isEmpty ? 1 : sentences.length);
    if (dialogue > 0.18) {
      scores[BookVoice.classic] = scores[BookVoice.classic]! + 2; // a novel
    } else if (youRate > 10 && modernHits > 4) {
      scores[BookVoice.modern] = scores[BookVoice.modern]! + 3; // talks to the reader about ideas
    }
    if (avgSentence > 26) scores[BookVoice.classic] = scores[BookVoice.classic]! + 1.5;
  }

  var best = BookVoice.classic;
  for (final v in BookVoice.values) {
    if (scores[v]! > scores[best]!) best = v;
  }
  // Weak evidence: stay with the calm literary default.
  if (scores[best]! < 3) best = BookVoice.classic;
  return VoiceGuess(best, scores);
}
