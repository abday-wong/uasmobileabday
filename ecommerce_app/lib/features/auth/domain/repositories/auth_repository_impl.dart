

import 'package:uts_gaming_console/core/constants/app_constants.dart';
import 'package:uts_gaming_console/core/services/dio_client.dart';
import 'package:uts_gaming_console/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl extends AuthRepository {
  @override
  Future<String> verifyFirebaseToken(String firebaseToken) async {
    final response = await DioClient.instance.post(
      AppConstants.verifyToken,
      data: {'firebase_token': firebaseToken},
    );

    final data = response.data['data'] as Map<String, dynamic>;
    return data['access_token'] as String;
  }

}