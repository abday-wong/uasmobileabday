
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uts_gaming_console/core/constants/app_constants.dart';
import 'package:uts_gaming_console/core/services/secure_storage.dart';


class DioClient {
  static Dio? _instance;

  static Dio get instance {
    _instance ??= _createDio(); // Singleton pattern
    return _instance!;
  }

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: Duration(milliseconds: AppConstants.connectTimeout),
        receiveTimeout: Duration(milliseconds: AppConstants.receiveTimeout),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // Interceptor 1: Logging
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          debugPrint('[REQUEST] ${options.method} ${options.path}');
          handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint('[RESPONSE] ${response.statusCode}');
          handler.next(response);
        },
        onError: (error, handler) async {
          debugPrint('[ERROR] ${error.response?.statusCode}');
          if (error.response?.statusCode == 401) {
            await SecureStorage.clearAll(); // Auto logout
          }
          handler.next(error);
        },
      ),
    );

    // Interceptor 2: Auto-inject Bearer Token
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await SecureStorage.getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );

    return dio;
  }
}
