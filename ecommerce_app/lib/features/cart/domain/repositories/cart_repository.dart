

import 'package:uts_gaming_console/features/cart/data/models/cart_item_model.dart';

abstract class CartRepository {
  Future<void> saveCart(List<CartItem> items);
  Future<List<CartItem>> loadCart();
  Future<void> clearCart();
}
