import 'package:flutter/foundation.dart';

class CheckoutProvider extends ChangeNotifier {
  bool _isProcessing = false;
  String? _orderId;

  bool get isProcessing => _isProcessing;
  String? get orderId => _orderId;

  /// Simulasi proses checkout/pembayaran
  Future<bool> processCheckout() async {
    _isProcessing = true;
    notifyListeners();

    try {
      // Simulasi API call untuk pembayaran
      await Future.delayed(const Duration(seconds: 2));

      // Generate order ID
      _orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch}';

      _isProcessing = false;
      notifyListeners();

      return true;
    } catch (e) {
      _isProcessing = false;
      notifyListeners();
      return false;
    }
  }

  void resetCheckout() {
    _isProcessing = false;
    _orderId = null;
    notifyListeners();
  }
}
