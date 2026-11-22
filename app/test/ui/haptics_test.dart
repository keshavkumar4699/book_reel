import 'package:book_reel/data/settings.dart';
import 'package:book_reel/ui/haptics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> played;

  setUp(() {
    played = [];
    Haptics.enabled = true;
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') played.add('${call.arguments ?? 'vibrate'}');
      return null;
    });
  });

  tearDown(() {
    Haptics.enabled = true;
    debugDefaultTargetPlatformOverride = null;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('on Android every kind is one the phone plays: a key click, a firm buzz, two clicks for a success', (tester) async {
    Haptics.select();
    Haptics.tap();
    Haptics.press();
    Haptics.tick();
    await tester.pump();
    expect(played, ['HapticFeedbackType.lightImpact', 'HapticFeedbackType.lightImpact', 'vibrate', 'HapticFeedbackType.selectionClick']);
    played.clear();
    Haptics.success();
    await tester.pump();
    expect(played, ['HapticFeedbackType.lightImpact']);
    await tester.pump(const Duration(milliseconds: 150));
    expect(played, ['HapticFeedbackType.lightImpact', 'HapticFeedbackType.lightImpact']);
  });

  testWidgets('on an iPhone, the system’s own selection and success feedback', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    Haptics.select();
    Haptics.press();
    Haptics.success();
    await tester.pump(const Duration(milliseconds: 150));
    expect(played, ['HapticFeedbackType.selectionClick', 'HapticFeedbackType.mediumImpact', 'HapticFeedbackType.successNotification']);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('with Vibration off, nothing', (tester) async {
    Haptics.enabled = false;
    Haptics.select();
    Haptics.tap();
    Haptics.press();
    Haptics.tick();
    Haptics.success();
    await tester.pump(const Duration(milliseconds: 150));
    expect(played, isEmpty);
  });

  test('the Vibration setting is on unless turned off, and kept', () {
    expect(const AppSettings().haptics, isTrue);
    expect(AppSettings.fromJson(const AppSettings(haptics: false).toJson()).haptics, isFalse);
    expect(AppSettings.fromJson(const {}).haptics, isTrue);
  });
}
