import 'package:flutter/foundation.dart' show kIsWeb;

class AppConstants {
  static final String baseUrl = kIsWeb ? 'http://localhost:8080/v1' : 'http://10.0.2.2:8080/v1';

  // Auth endpoints
  static const String verifyToken = '/auth/verify-token';

  // Product endpoints
  static const String products = '/products';

  // Timeout
  static const int connectTimeout = 15000;
  static const int receiveTimeout = 15000;
}
