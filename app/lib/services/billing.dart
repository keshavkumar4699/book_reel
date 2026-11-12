import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart' show ReplacementMode;
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../data/api_client.dart';
import '../data/settings.dart';
import '../data/settings_provider.dart';

/// Google Play subscription products (each with "monthly" and "yearly" base
/// plans), matching server/src/billing/play.ts.
const planProductIds = {
  Tier.lite: 'bookreel_lite',
  Tier.plus: 'bookreel_plus',
  Tier.pro: 'bookreel_pro',
  Tier.scholar: 'bookreel_scholar',
};

Tier? tierForProduct(String productId) => planProductIds.entries.where((e) => e.value == productId).firstOrNull?.key;

/// One way to buy a plan, at the price Play shows in the buyer's country.
class PlanOffer {
  const PlanOffer({required this.tier, required this.yearly, required this.price, this.trial, this.handle});
  final Tier tier;
  final bool yearly;

  /// Localised, e.g. "₹149" or "$3.99".
  final String price;

  /// A free trial on this offer, e.g. "7 days".
  final String? trial;

  /// The store's own product object.
  final Object? handle;
}

enum PurchaseState { pending, owned, error, canceled }

class StorePurchase {
  const StorePurchase({required this.productId, required this.token, required this.state, this.error, this.handle});
  final String productId;

  /// Play's purchase token, verified by the server.
  final String token;
  final PurchaseState state;
  final String? error;
  final Object? handle;
}

/// The store, behind a seam so the purchase flow can be tested.
abstract class StoreGateway {
  Future<bool> available();
  Future<List<PlanOffer>> offers();
  Stream<List<StorePurchase>> get purchases;
  Future<void> buy(PlanOffer offer, {StorePurchase? replacing});
  Future<void> finish(StorePurchase purchase);
  Future<void> restore();
}

/// Google Play through the official in_app_purchase plugin.
class PlayStoreGateway implements StoreGateway {
  final InAppPurchase _iap = InAppPurchase.instance;

  @override
  Future<bool> available() => _iap.isAvailable();

  static String? _period(String iso) {
    final m = RegExp(r'^P(\d+)([DWMY])$').firstMatch(iso);
    if (m == null) return null;
    final n = int.parse(m.group(1)!);
    final unit = switch (m.group(2)) { 'D' => 'day', 'W' => 'week', 'M' => 'month', _ => 'year' };
    return '$n $unit${n == 1 ? '' : 's'}';
  }

  @override
  Future<List<PlanOffer>> offers() async {
    final res = await _iap.queryProductDetails(planProductIds.values.toSet());
    final best = <String, PlanOffer>{};
    for (final pd in res.productDetails) {
      if (pd is! GooglePlayProductDetails) continue;
      final index = pd.subscriptionIndex;
      final details = pd.productDetails.subscriptionOfferDetails;
      final tier = tierForProduct(pd.id);
      if (index == null || details == null || index >= details.length || tier == null) continue;
      final o = details[index];
      final free = o.pricingPhases.where((p) => p.priceAmountMicros == 0).firstOrNull;
      final regular = o.pricingPhases.isEmpty ? null : o.pricingPhases.last;
      final offer = PlanOffer(
        tier: tier,
        yearly: o.basePlanId.contains('year'),
        price: regular?.formattedPrice ?? pd.price,
        trial: free == null ? null : _period(free.billingPeriod),
        handle: pd,
      );
      // Play lists only the offers this buyer may take; prefer one with a trial.
      final key = '${pd.id}|${o.basePlanId}';
      if (!best.containsKey(key) || (offer.trial != null && best[key]!.trial == null)) best[key] = offer;
    }
    return best.values.toList();
  }

  @override
  Stream<List<StorePurchase>> get purchases => _iap.purchaseStream.map((list) => [
        for (final p in list)
          StorePurchase(
            productId: p.productID,
            token: p.verificationData.serverVerificationData,
            state: switch (p.status) {
              PurchaseStatus.pending => PurchaseState.pending,
              PurchaseStatus.purchased || PurchaseStatus.restored => PurchaseState.owned,
              PurchaseStatus.error => PurchaseState.error,
              PurchaseStatus.canceled => PurchaseState.canceled,
            },
            error: p.error?.message,
            handle: p,
          ),
      ]);

  @override
  Future<void> buy(PlanOffer offer, {StorePurchase? replacing}) async {
    final old = replacing?.handle;
    await _iap.buyNonConsumable(
      purchaseParam: GooglePlayPurchaseParam(
        productDetails: offer.handle! as ProductDetails,
        // Switching plans: Play prorates the time left on the old one.
        changeSubscriptionParam: old is GooglePlayPurchaseDetails
            ? ChangeSubscriptionParam(oldPurchaseDetails: old, replacementMode: ReplacementMode.withTimeProration)
            : null,
      ),
    );
  }

  @override
  Future<void> finish(StorePurchase purchase) async {
    final h = purchase.handle;
    if (h is PurchaseDetails && h.pendingCompletePurchase) await _iap.completePurchase(h);
  }

  @override
  Future<void> restore() => _iap.restorePurchases();
}

@immutable
class BillingState {
  const BillingState({this.live = false, this.offers = const [], this.busy = false, this.message, this.expiresAt});

  /// Plans can be bought here (store reachable, server verifies, products set up).
  final bool live;
  final List<PlanOffer> offers;
  final bool busy;
  final String? message;

  /// When the current plan renews or ends.
  final DateTime? expiresAt;

  PlanOffer? offer(Tier tier, {required bool yearly}) => offers.where((o) => o.tier == tier && o.yearly == yearly).firstOrNull;

  BillingState copyWith({bool? live, List<PlanOffer>? offers, bool? busy, String? message, bool clearMessage = false, DateTime? expiresAt}) =>
      BillingState(
        live: live ?? this.live,
        offers: offers ?? this.offers,
        busy: busy ?? this.busy,
        message: clearMessage ? null : (message ?? this.message),
        expiresAt: expiresAt ?? this.expiresAt,
      );
}

/// Subscriptions (DESIGN.md §6, IMPLEMENTATION_PLAN.md Phase 8): buys plans in
/// Play, has the server verify every purchase, and takes the plan from the
/// server's answer, so a plan follows the account and ends with the
/// subscription.
class BillingController extends Notifier<BillingState> {
  /// Tests replace the store.
  static StoreGateway Function() gatewayFactory = PlayStoreGateway.new;

  StoreGateway? _store;
  StreamSubscription<List<StorePurchase>>? _sub;
  StorePurchase? _active;

  @override
  BillingState build() {
    ref.onDispose(() => _sub?.cancel());
    scheduleMicrotask(_init);
    return const BillingState();
  }

  Future<void> _init() async {
    final api = ref.read(apiProvider);
    if (!api.enabled) return; // purchases can't be verified without the server
    await refreshEntitlement();
    try {
      final store = _store = gatewayFactory();
      if (!await store.available()) return;
      _sub = store.purchases.listen(_onPurchases);
      final offers = await store.offers();
      state = state.copyWith(live: offers.isNotEmpty, offers: offers);
    } catch (e) {
      debugPrint('Billing unavailable: $e');
    }
  }

  /// Takes the plan the server has on record (when billing is enforced).
  Future<void> refreshEntitlement() async {
    try {
      final e = await ref.read(apiProvider).entitlement();
      _apply(e);
    } catch (_) {
      // Offline: keep the plan we have.
    }
  }

  void _apply(Map<String, dynamic> e) {
    final tier = Tier.values.where((t) => t.name == e['tier']).firstOrNull ?? Tier.free;
    final expires = e['expires_at'] == null ? null : DateTime.tryParse(e['expires_at'] as String);
    if (e['enforced'] == true || tier != Tier.free) {
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(tier: tier));
    }
    state = state.copyWith(expiresAt: expires);
  }

  Future<void> _onPurchases(List<StorePurchase> list) async {
    for (final p in list) {
      switch (p.state) {
        case PurchaseState.pending:
          state = state.copyWith(busy: true, message: 'Waiting for the payment to go through…');
        case PurchaseState.canceled:
          state = state.copyWith(busy: false, clearMessage: true);
        case PurchaseState.error:
          state = state.copyWith(busy: false, message: p.error ?? 'The purchase did not go through.');
        case PurchaseState.owned:
          try {
            _apply(await ref.read(apiProvider).verifyPurchase(productId: p.productId, purchaseToken: p.token));
            _active = p;
            state = state.copyWith(busy: false, clearMessage: true);
          } on ApiException catch (e) {
            state = state.copyWith(busy: false, message: 'We couldn’t confirm this purchase (${e.status}). Try Restore later.');
            continue;
          } catch (_) {
            state = state.copyWith(busy: false, message: 'Offline: the plan will switch on once you’re back online.');
            continue;
          }
          // Acknowledge only what the server confirmed: an unacknowledged
          // purchase is redelivered, and Play refunds it after 3 days.
          await _store?.finish(p);
      }
    }
  }

  Future<void> buy(PlanOffer offer) async {
    final store = _store;
    if (store == null) return;
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      await store.buy(offer, replacing: _active);
    } catch (e) {
      state = state.copyWith(busy: false, message: 'Couldn’t open Google Play: $e');
    }
  }

  Future<void> restore() async {
    state = state.copyWith(clearMessage: true);
    await _store?.restore();
    await refreshEntitlement();
  }
}

final billingProvider = NotifierProvider<BillingController, BillingState>(BillingController.new);
