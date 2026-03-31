import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Product ID for the "Remove ads" one-time purchase.
/// Must match the product ID in Google Play Console.
const String removeAdsProductId = 'remove_ads';

const _keyHasRemovedAds = 'has_removed_ads';

/// Manages in-app purchase for "Remove ads" ($1.99).
/// Purchase state is persisted locally and restored on app start.
class PurchaseService extends ChangeNotifier {
  PurchaseService() {
    _init();
  }

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool _hasRemovedAds = false;
  bool get hasRemovedAds => _hasRemovedAds;

  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  Future<void> _init() async {
    _hasRemovedAds = await _loadPurchaseState();

    _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) {
      debugPrint('PurchaseService: IAP not available');
      notifyListeners();
      return;
    }

    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (e) => debugPrint('PurchaseService stream error: $e'),
    );

    // Restore any pending purchases
    await _restorePurchasesInternal();
    notifyListeners();
  }

  Future<bool> _loadPurchaseState() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHasRemovedAds) ?? false;
  }

  Future<void> _savePurchaseState(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasRemovedAds, value);
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      if (purchase.productID != removeAdsProductId) continue;

      switch (purchase.status) {
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _hasRemovedAds = true;
          _savePurchaseState(true);
          _error = null;
          if (purchase.pendingCompletePurchase) {
            _iap.completePurchase(purchase);
          }
          break;
        case PurchaseStatus.error:
          _error = purchase.error?.message ?? 'Purchase failed';
          break;
        case PurchaseStatus.canceled:
          _error = null;
          break;
      }
    }
    notifyListeners();
  }

  Future<void> purchaseRemoveAds() async {
    if (!_isAvailable || _isLoading || _hasRemovedAds) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _iap.queryProductDetails({removeAdsProductId});
      if (response.notFoundIDs.isNotEmpty) {
        _error = 'Product not found. Add "remove_ads" in Play Console.';
        return;
      }
      final product = response.productDetails.firstOrNull;
      if (product == null) {
        _error = 'Product not available';
        return;
      }

      final purchaseParam = PurchaseParam(productDetails: product);
      final success = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      if (!success) {
        _error = 'Could not start purchase';
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> restorePurchases() async {
    if (!_isAvailable || _isLoading) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    await _restorePurchasesInternal();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _restorePurchasesInternal() async {
    await _iap.restorePurchases();
    // State is updated via _onPurchaseUpdate when restore completes
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
