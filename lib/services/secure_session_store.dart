import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the short-lived registration credentials in the platform keychain.
///
/// Activation credentials must not be kept in SharedPreferences because those
/// values are included in ordinary app backups on some devices.
class SecureSessionStore {
  static const _tokenKey = 'eliteradiq_activation_token_v2';
  static const _registrationIdKey = 'eliteradiq_registration_id_v2';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  Future<void> save({required String registrationId, required String token}) async {
    await _storage.write(key: _registrationIdKey, value: registrationId);
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<String?> readRegistrationId() => _storage.read(key: _registrationIdKey);

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _registrationIdKey);
  }
}
