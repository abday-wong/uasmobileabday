
import 'package:uts_gaming_console/features/cart/data/models/cart_item_model.dart';

import 'cart_repository.dart';

class CartRepositoryImpl implements CartRepository {
  // Dalam implementasi nyata, data akan disimpan ke database atau shared preferences
  final List<CartItem> _localCart = [];

  @override
  Future<void> saveCart(List<CartItem> items) async {
    // Simulasi menyimpan ke database
    _localCart.clear();
    _localCart.addAll(items);
  }

  @override
  Future<List<CartItem>> loadCart() async {
    // Simulasi mengambil dari database
    return _localCart;
  }

  @override
  Future<void> clearCart() async {
    // Simulasi menghapus dari database
    _localCart.clear();
  }
}
