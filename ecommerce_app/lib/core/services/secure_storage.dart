import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      keyCipherAlgorithm:
          KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
    ),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _keyToken = 'auth_token';
  static const _keyTransactions = 'transactions';

  static Future<void> saveToken(String token) async =>
      _storage.write(key: _keyToken, value: token);

  static Future<String?> getToken() async => _storage.read(key: _keyToken);

  static Future<void> clearAll() async => _storage.deleteAll();

  static Future<void> saveTransaction(Map<String, dynamic> transaction) async {
    final existing = await _storage.read(key: _keyTransactions);
    List<dynamic> list = [];
    if (existing != null) {
      try {
        list = jsonDecode(existing) as List<dynamic>;
      } catch (_) {}
    }
    list.add(transaction);
    await _storage.write(key: _keyTransactions, value: jsonEncode(list));
  }

  static Future<List<Map<String, dynamic>>> getTransactions() async {
    final existing = await _storage.read(key: _keyTransactions);
    if (existing == null) return [];
    try {
      final decoded = jsonDecode(existing) as List<dynamic>;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList().reversed.toList();
    } catch (_) {
      return [];
    }
  }
}
