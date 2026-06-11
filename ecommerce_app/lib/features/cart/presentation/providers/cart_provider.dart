import 'package:flutter/foundation.dart';
import 'package:uts_gaming_console/features/cart/data/models/cart_item_model.dart';

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => _items;

  int get itemCount => _items.length;

  double get totalPrice {
    return _items.fold(0, (sum, item) => sum + item.totalPrice);
  }

  /// Tambah barang ke cart
  void addItem(String productId, String productName, double price, {String? imageUrl}) {
    final index = _items.indexWhere((item) => item.productId == productId);
    
    if (index == -1) {
      // Item tidak ada, tambah baru
      final newItem = CartItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        productId: productId,
        productName: productName,
        price: price,
        quantity: 1,
        imageUrl: imageUrl,
      );
      _items.add(newItem);
    } else {
      // Item sudah ada, update quantity
      final item = _items[index];
      final updatedItem = item.copyWith(quantity: item.quantity + 1);
      _items[index] = updatedItem;
    }
    
    notifyListeners();
  }

  /// Hapus barang dari cart
  void removeItem(String productId) {
    _items.removeWhere((item) => item.productId == productId);
    notifyListeners();
  }

  /// Update quantity barang
  void updateItemQuantity(String productId, int quantity) {
    final index = _items.indexWhere((item) => item.productId == productId);
    if (index != -1) {
      if (quantity <= 0) {
        _items.removeAt(index);
      } else {
        _items[index] = _items[index].copyWith(quantity: quantity);
      }
      notifyListeners();
    }
  }

  /// Clear semua item
  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}
