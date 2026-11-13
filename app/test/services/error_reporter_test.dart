import 'dart:io';

import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/services/error_reporter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fake_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> container({FakeServer? server}) async {
    final dir = Directory.systemTemp.createTempSync('errors');
    final store = await JsonStore.open(dir);
    final c = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(store),
      apiProvider.overrideWithValue(
          BookReelApi(baseUrl: server == null ? '' : 'http://fake', deviceId: 'dev1', httpClient: server?.client)),
    ]);
    addTearDown(() async {
      c.dispose();
      await store.flush();
      dir.deleteSync(recursive: true);
    });
    return c;
  }

  StackTrace at(String where) => StackTrace.fromString('#0 $where\n#1 main (main.dart:1)');

  test('an error is sent once, with where it happened and the version; at most 10 a run', () async {
    final server = FakeServer();
    final reporter = ErrorReporter(await container(server: server));
    expect(await reporter.report(StateError('Bad state: no book'), at('ReaderScreen.build (reader_screen.dart:42)')), isTrue);
    expect(await reporter.report(StateError('Bad state: no book'), at('ReaderScreen.build (reader_screen.dart:42)')), isFalse,
        reason: 'the same error from the same place counts once');
    expect(server.errors.single, {
      'message': 'Bad state: Bad state: no book',
      'stack': '#0 ReaderScreen.build (reader_screen.dart:42)\n#1 main (main.dart:1)',
      'version': 'dev',
      'platform': 'android',
    });
    for (var i = 0; i < 20; i++) {
      await reporter.report(FormatException('bad $i'), at('Parser.parse (epub.dart:$i)'));
    }
    expect(server.errors, hasLength(ErrorReporter.maxPerRun));
    expect(server.errors.every((e) => (e['message'] as String).length <= 500), isTrue);
  });

  test('nothing is sent with crash reports off, or offline', () async {
    final server = FakeServer();
    final c = await container(server: server);
    c.read(settingsProvider.notifier).update((s) => s.copyWith(crashReports: false));
    expect(await ErrorReporter(c).report(Exception('x'), null), isFalse);
    expect(server.errors, isEmpty);
    expect(await ErrorReporter(await container()).report(Exception('x'), null), isFalse);
  });

  test('long messages and traces are cut to size', () async {
    final server = FakeServer();
    final reporter = ErrorReporter(await container(server: server));
    await reporter.report(Exception('x' * 2000), StackTrace.fromString('y' * 20000));
    expect((server.errors.single['message'] as String).length, 500);
    expect((server.errors.single['stack'] as String).length, 8000);
  });
}
