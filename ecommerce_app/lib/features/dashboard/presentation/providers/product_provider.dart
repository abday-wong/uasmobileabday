import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:uts_gaming_console/core/constants/app_constants.dart';
import 'package:uts_gaming_console/core/services/dio_client.dart';
import 'package:uts_gaming_console/features/dashboard/data/models/product_model.dart';

enum ProductStatus { initial, loading, loaded, error }

class ProductProvider extends ChangeNotifier{
  ProductStatus       _status   = ProductStatus.initial;
  List<ProductModel>  _products = [];
  String?             _error;
  ProductStatus      get status   => _status;
  List<ProductModel> get products => _products;
  String?            get error    => _error;
  bool               get isLoading => _status == ProductStatus.loading;

  // Fetch products — token otomatis disertakan oleh DioClient interceptor
  Future<void> fetchProducts() async {
    _status = ProductStatus.loading;
    notifyListeners();

    try {
      final response = await DioClient.instance.get(AppConstants.products);

      // Backend response: { "data": [ {...}, {...} ] }
      final List<dynamic> data = response.data['data'];
      _products = data.map((e) => ProductModel.fromJson(e)).toList();
      _status   = ProductStatus.loaded;
    } on DioException catch (e) {
      _error  = e.response?.data['message'] ?? 'Gagal memuat produk';
      _status = ProductStatus.error;
    }

    notifyListeners();
  }

}