import 'package:book_reel/data/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plans run cheapest first, each paid plan one model up', () {
    expect(Tier.values.map((t) => t.name), ['free', 'lite', 'plus', 'pro', 'scholar']);
    expect(Tier.values.map((t) => t.usdPerMonth), [0, 3.99, 8.99, 19.99, 29.99]);
    expect(Tier.values.map((t) => t.model), ['On-device rules', 'Claude Haiku', 'Claude Sonnet', 'Claude Opus', 'Claude Fable']);
    expect(Tier.values.map((t) => t.freezes), [1, 2, 3, 4, 5]);
    expect(Tier.values.where((t) => t.paid), [Tier.lite, Tier.plus, Tier.pro, Tier.scholar]);
  });

  test('a plan saved before Lite existed keeps its price', () {
    Tier saved(String tier, [int? planVersion]) =>
        AppSettings.fromJson({'tier': tier, 'planVersion': ?planVersion}).tier;
    // Old ladder: Plus $3.99 (Haiku), Pro $8.99 (Sonnet), Scholar $19.99 (Opus).
    expect(saved('free'), Tier.free);
    expect(saved('plus'), Tier.lite);
    expect(saved('pro'), Tier.plus);
    expect(saved('scholar'), Tier.pro);
    // Saved on the new ladder: kept as is.
    expect(saved('plus', currentPlanVersion), Tier.plus);
    expect(saved('scholar', currentPlanVersion), Tier.scholar);
    final round = AppSettings.fromJson(const AppSettings(tier: Tier.scholar).toJson());
    expect(round.tier, Tier.scholar);
  });
}
