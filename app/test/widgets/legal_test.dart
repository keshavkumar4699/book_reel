import 'package:book_reel/features/settings/legal_screen.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1236, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(theme: buildAppTheme(Kit.appLight), home: child)));
    for (var i = 0; i < 50 && find.byType(MarkdownText).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  testWidgets('the privacy policy and terms are readable in the app, offline', (tester) async {
    await show(tester, const LegalScreen(doc: LegalDoc.privacy));
    expect(find.text('Privacy policy'), findsOneWidget, reason: 'the title once (the file’s own heading is the title)');
    expect(find.text('The short version'), findsOneWidget);
    expect(find.textContaining('Your books stay on your phone', findRichText: true), findsOneWidget);
    expect(find.text('Anthropic (Claude)'), findsOneWidget, reason: 'the table of services, one block per row');

    await show(tester, const LegalScreen(doc: LegalDoc.terms));
    expect(find.text('Terms of use'), findsOneWidget);
    expect(find.text('Be kind'), findsOneWidget);
  });

  testWidgets('Markdown: headings, paragraphs, lists, tables and bold', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Kit.appLight),
      home: const Scaffold(body: MarkdownText('## Part\n\nSome **bold** words\nwrapped.\n\n- one\n- two\n\n| Who | What |\n|---|---|\n| Asha | reads |\n')),
    ));
    expect(find.text('Part'), findsOneWidget);
    expect(find.textContaining('Some bold words wrapped.', findRichText: true), findsOneWidget);
    expect(find.textContaining('one', findRichText: true), findsWidgets);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.textContaining('What: reads', findRichText: true), findsOneWidget);
  });
}
