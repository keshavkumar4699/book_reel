import 'dart:async';
import 'dart:io';

import 'package:book_reel/data/api_client.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/services/billing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fake_server.dart';

class FakeStore implements StoreGateway {
  final _purchases = StreamController<List<StorePurchase>>.broadcast();
  final bought = <(PlanOffer, StorePurchase?)>[];
  final finished = <StorePurchase>[];
  bool restored = false;

  void deliver(List<StorePurchase> p) => _purchases.add(p);

  @override
  Future<bool> available() async => true;
  @override
  Future<List<PlanOffer>> offers() async => [
        for (final t in planProductIds.keys) ...[
          PlanOffer(tier: t, yearly: false, price: '₹${t.index * 100 + 49}', trial: t == Tier.plus ? '7 days' : null),
          PlanOffer(tier: t, yearly: true, price: '₹${t.index * 1000 + 199}'),
        ],
      ];
  @override
  Stream<List<StorePurchase>> get purchases => _purchases.stream;
  @override
  Future<void> buy(PlanOffer offer, {StorePurchase? replacing}) async => bought.add((offer, replacing));
  @override
  Future<void> finish(StorePurchase purchase) async => finished.add(purchase);
  @override
  Future<void> restore() async => restored = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late JsonStore store;
  late FakeServer server;
  late FakeStore play;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('billing');
    store = await JsonStore.open(dir);
    server = FakeServer();
    play = FakeStore();
    BillingController.gatewayFactory = () => play;
  });

  tearDown(() async {
    await store.flush();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  ProviderContainer container({bool withServer = true}) => ProviderContainer(overrides: [
        storeProvider.overrideWithValue(store),
        apiProvider.overrideWithValue(
            BookReelApi(baseUrl: withServer ? 'http://fake' : '', deviceId: 'dev1', httpClient: server.client)),
      ]);

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('buying a plan: Play sells it, the server verifies it, the app takes the plan from the server', () async {
    final c = container();
    addTearDown(c.dispose);
    c.read(billingProvider);
    await settle();
    final state = c.read(billingProvider);
    expect(state.live, isTrue);
    expect(state.offer(Tier.plus, yearly: false)!.trial, '7 days');
    expect(state.offer(Tier.pro, yearly: true)!.price, '₹3199');

    await c.read(billingProvider.notifier).buy(state.offer(Tier.plus, yearly: false)!);
    expect(play.bought.single.$1.tier, Tier.plus);
    expect(c.read(billingProvider).busy, isTrue);

    // Play reports the purchase; only a token the server accepts changes the plan.
    server.playTokens['tok-plus'] = 'plus';
    play.deliver([const StorePurchase(productId: 'bookreel_plus', token: 'tok-plus', state: PurchaseState.owned)]);
    await settle();
    expect(c.read(settingsProvider).tier, Tier.plus);
    expect(play.finished.single.token, 'tok-plus', reason: 'acknowledged only after the server verified it');
    expect(c.read(billingProvider).busy, isFalse);
    expect(c.read(billingProvider).expiresAt, DateTime.utc(2027));

    // Switching to Pro replaces the Plus purchase (Play prorates it).
    await c.read(billingProvider.notifier).buy(c.read(billingProvider).offer(Tier.pro, yearly: false)!);
    expect(play.bought.last.$2?.token, 'tok-plus');
  });

  test('pending, rejected and cancelled purchases never change the plan', () async {
    final c = container();
    addTearDown(c.dispose);
    c.read(billingProvider);
    await settle();
    play.deliver([const StorePurchase(productId: 'bookreel_pro', token: 't1', state: PurchaseState.pending)]);
    await settle();
    expect(c.read(billingProvider).message, contains('Waiting for the payment'));
    play.deliver([const StorePurchase(productId: 'bookreel_pro', token: 'forged', state: PurchaseState.owned)]);
    await settle();
    expect(c.read(settingsProvider).tier, Tier.free);
    expect(c.read(billingProvider).message, contains('couldn\u2019t confirm'));
    expect(play.finished, isEmpty);
    play.deliver([const StorePurchase(productId: 'bookreel_pro', token: 't2', state: PurchaseState.canceled)]);
    await settle();
    expect(c.read(billingProvider).message, isNull);
  });

  test('the plan follows the account: a subscription found on the server applies at start', () async {
    server.entitled['dev1'] = 'scholar';
    final c = container();
    addTearDown(c.dispose);
    c.read(billingProvider);
    await settle();
    expect(c.read(settingsProvider).tier, Tier.scholar);
    // An expired subscription (server enforces billing) drops back to Free.
    server.entitled.remove('dev1');
    await c.read(billingProvider.notifier).restore();
    expect(play.restored, isTrue);
    expect(c.read(settingsProvider).tier, Tier.free);
  });

  test('without the server, purchases are off (nothing could verify them)', () async {
    final c = container(withServer: false);
    addTearDown(c.dispose);
    c.read(billingProvider);
    await settle();
    expect(c.read(billingProvider).live, isFalse);
    expect(tierForProduct('bookreel_lite'), Tier.lite);
    expect(tierForProduct('something_else'), isNull);
  });
}
