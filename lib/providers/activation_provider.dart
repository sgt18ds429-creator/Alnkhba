import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/registered_user.dart';
import '../services/api_service.dart';
import '../services/secure_session_store.dart';

/// Secure activation/admin state.
///
/// IMPORTANT:
/// - The client never reads/writes activation tables directly.
/// - All activation and admin mutations go through SECURITY DEFINER RPCs.
/// - The server is the source of truth; local preferences are only a UX cache.
class ActivationProvider extends ChangeNotifier {
  static const String _isActivatedKey = 'eliteradiq_is_activated';
  static const String _currentUserIdKey = 'eliteradiq_current_user_id';
  static const String _deviceIdKey = 'eliteradiq_installation_id';

  final SupabaseClient _supabase = Supabase.instance.client;
  final SecureSessionStore _sessionStore = SecureSessionStore();
  final ApiService _apiService = ApiService();

  bool _isActivated = false;
  bool _isLoading = true;
  RegisteredUser? _currentUser;
  List<RegisteredUser> _registeredUsers = [];
  List<String> _allowedCodes = [];
  String? _deviceId;

  bool get isActivated => _isActivated;
  bool get isLoading => _isLoading;
  RegisteredUser? get currentUser => _currentUser;
  List<RegisteredUser> get registeredUsers => List.unmodifiable(_registeredUsers);
  List<String> get allowedCodes => List.unmodifiable(_allowedCodes);

  String generateActivationCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final suffix = List.generate(16, (_) => alphabet[random.nextInt(alphabet.length)]).join();
    return 'ELITE-$suffix';
  }

  ActivationProvider() {
    _loadState();
  }

  Future<String> _getDeviceId() async {
    if (_deviceId != null && _deviceId!.isNotEmpty) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      _deviceId = existing;
      return existing;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final id = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _deviceId = id;
    await prefs.setString(_deviceIdKey, id);
    return id;
  }

  RegisteredUser _userFromRow(Map<String, dynamic> row) {
    return RegisteredUser(
      id: row['id']?.toString() ?? '',
      fullName: row['full_name']?.toString() ?? row['fullName']?.toString() ?? '',
      activationCode: row['activation_code']?.toString() ?? row['activationCode']?.toString() ?? '',
      activatedAt:
          (row['activated_at'] as num?)?.toInt() ?? (row['activatedAt'] as num?)?.toInt() ?? 0,
      expiresAt: (row['expires_at'] as num?)?.toInt() ?? (row['expiresAt'] as num?)?.toInt(),
      deviceId: row['device_id']?.toString() ?? row['deviceId']?.toString(),
      pending: row['pending'] == true,
    );
  }

  List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  Map<String, dynamic>? _object(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    final rows = _rows(data);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _acceptActivationResult(Map<String, dynamic> result) async {
    final userData = result['user'];
    if (userData is! Map) {
      throw const FormatException('Activation response has no user object');
    }
    final user = _userFromRow(Map<String, dynamic>.from(userData));
    if (user.id.isEmpty || user.isExpired) {
      throw const FormatException('Activation response contains invalid user');
    }

    final token = result['access_token']?.toString();
    if (token == null || token.length < 48) {
      throw const FormatException('Activation response has no secure token');
    }
    await _sessionStore.save(registrationId: user.id, token: token);
    _currentUser = user;
    _isActivated = true;
    await _saveStateLocally();
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _getDeviceId();
      final cachedId = prefs.getString(_currentUserIdKey);

      // Local flags are not trusted. Validate the registration against the DB.
      if (cachedId != null && cachedId.isNotEmpty) {
        await _loadCurrentUser(cachedId);
      } else {
        await _clearLocalActivation();
      }
    } catch (e) {
      debugPrint('Activation state error: $e');
      await _clearLocalActivation();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadCurrentUser(String userId) async {
    String? sessionToken;
    try {
      final deviceId = await _getDeviceId();
      sessionToken = await _sessionStore.readToken();
      if (sessionToken == null || sessionToken.length < 48) {
        await _clearLocalActivation();
        return;
      }
      final response = await _supabase.rpc(
        'get_my_registration_v2',
        params: {'p_user_id': userId, 'p_device_id': deviceId, 'p_token': sessionToken},
      );
      final result = _object(response);
      if (result == null || result['ok'] != true) {
        await _clearLocalActivation();
        return;
      }
      await _acceptActivationResult(result);
    } catch (e) {
      debugPrint('Registration validation error: $e');
      // A temporary network failure must not destroy a valid one-time
      // activation credential. The AI backend still validates this token on
      // every request, so offline restoration cannot bypass server access.
      final secureId = await _sessionStore.readRegistrationId();
      if (sessionToken != null && sessionToken.length >= 48 && secureId == userId) {
        _currentUser = RegisteredUser(
          id: userId,
          fullName: 'مستخدم مفعّل (بانتظار المزامنة)',
          activationCode: 'محفوظ بأمان',
          activatedAt: 0,
        );
        _isActivated = true;
        await _saveStateLocally();
      } else {
        await _clearLocalActivation();
      }
    }
  }

  Future<void> refreshFromCloud() async {
    try {
      await _getDeviceId();

      if (_isAdmin()) {
        final users = await _supabase.rpc('admin_list_users');
        final codes = await _supabase.rpc('admin_list_codes');
        _registeredUsers = _rows(users).map(_userFromRow).toList();
        _allowedCodes = _rows(
          codes,
        ).map((r) => r['code']?.toString() ?? '').where((c) => c.isNotEmpty).toList();
        _registeredUsers.sort((a, b) => b.activatedAt.compareTo(a.activatedAt));
      } else if (_currentUser != null) {
        await _loadCurrentUser(_currentUser!.id);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Cloud refresh error: $e');
    }
  }

  bool _isAdmin() {
    final role = _supabase.auth.currentUser?.appMetadata['role']?.toString().toLowerCase();
    return role == 'admin';
  }

  Future<String?> activate({required String fullName, required String code}) async {
    final trimmedName = fullName.trim();
    final normalizedCode = code.trim().toUpperCase().replaceAll(' ', '');

    final words = trimmedName.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 3) {
      return 'يرجى كتابة الاسم الثلاثي الكامل (يتكون من 3 كلمات على الأقل)';
    }
    if (normalizedCode.isEmpty) return 'يرجى كتابة كود التفعيل';

    try {
      final deviceId = await _getDeviceId();
      final result = await _apiService.activateRegistration(
        fullName: trimmedName,
        code: normalizedCode,
        deviceId: deviceId,
      );
      if (result['ok'] != true) {
        return result['message']?.toString() ?? 'تعذر تفعيل الحساب، تحقق من الكود وحاول مجدداً';
      }
      await _acceptActivationResult(result);
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      debugPrint('Activation RPC error: ${e.code} ${e.message}');
      return 'فشل التفعيل، تحقق من الكود والاتصال بالإنترنت ثم حاول مجدداً.';
    } catch (e) {
      debugPrint('Activation error: $e');
      return 'فشل التفعيل، تأكد من الاتصال بالإنترنت';
    }
  }

  Future<String?> verifyDeveloperCredentials({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = response.user;
      if (user == null) return 'تعذر تسجيل الدخول إلى حساب المطور';

      final role = user.appMetadata['role']?.toString().toLowerCase();
      if (role != 'admin') {
        await _supabase.auth.signOut();
        return 'هذا الحساب لا يملك صلاحية المطور';
      }

      await refreshFromCloud();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذر الاتصال بخدمة المصادقة';
    }
  }

  Future<String?> addNewUserByAdmin({
    required String fullName,
    required String activationCode,
    int? durationDays,
  }) async {
    if (!_isAdmin()) return 'غير مصرح لك بتنفيذ هذا الإجراء';
    final name = fullName.trim();
    final code = activationCode.trim().toUpperCase();
    if (name.isEmpty) return 'يرجى كتابة الاسم الثلاثي للمستخدم';
    if (code.isEmpty) return 'يرجى كتابة كود التفعيل';

    try {
      await _supabase.rpc(
        'admin_add_user',
        params: {'p_full_name': name, 'p_code': code, 'p_duration_days': durationDays},
      );
      await refreshFromCloud();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (_) {
      return 'حدث خطأ أثناء إضافة المستخدم';
    }
  }

  Future<String?> addActivationCode(String newCode) async {
    if (!_isAdmin()) return 'غير مصرح لك بتنفيذ هذا الإجراء';
    final code = newCode.trim().toUpperCase().replaceAll(' ', '');
    if (code.isEmpty) return 'يرجى كتابة كود التفعيل';

    try {
      await _supabase.rpc('admin_add_code', params: {'p_code': code});
      await refreshFromCloud();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (_) {
      return 'حدث خطأ أثناء إضافة الكود';
    }
  }

  Future<String?> deleteActivationCode(String codeToDelete) async {
    if (!_isAdmin()) return 'غير مصرح لك بتنفيذ هذا الإجراء';
    try {
      await _supabase.rpc(
        'admin_delete_code',
        params: {'p_code': codeToDelete.trim().toUpperCase()},
      );
      await refreshFromCloud();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذر إلغاء كود التفعيل';
    }
  }

  Future<String?> updateUserDuration(String userId, int? durationDays) async {
    if (!_isAdmin()) return 'غير مصرح لك بتنفيذ هذا الإجراء';
    if (durationDays != null && (durationDays < 0 || durationDays > 3650)) {
      return 'المدة يجب أن تكون بين 0 و3650 يوماً';
    }
    try {
      await _supabase.rpc(
        'admin_update_user_duration',
        params: {'p_user_id': userId, 'p_duration_days': durationDays},
      );
      await refreshFromCloud();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذر تحديث مدة التفعيل';
    }
  }

  Future<String?> deleteUser(String userId) async {
    if (!_isAdmin()) return 'غير مصرح لك بتنفيذ هذا الإجراء';
    try {
      await _supabase.rpc('admin_delete_user', params: {'p_user_id': userId});
      if (_currentUser?.id == userId) await _clearLocalActivation();
      await refreshFromCloud();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذر حذف المستخدم';
    }
  }

  Future<void> signOutDeveloper() async {
    _registeredUsers = [];
    _allowedCodes = [];
    notifyListeners();
    try {
      await _supabase.auth.signOut();
    } catch (_) {
      // Privileged data was already cleared locally. EmptyLocalStorage in
      // main.dart prevents the admin refresh token from surviving a restart.
    }
  }

  Future<String?> deactivateSelf() async {
    final userId = _currentUser?.id;
    if (userId == null || userId.isEmpty) {
      await _clearLocalActivation();
      notifyListeners();
      return null;
    }

    try {
      final deviceId = await _getDeviceId();
      final sessionToken = await _sessionStore.readToken();
      if (sessionToken == null || sessionToken.length < 48) {
        return 'تعذر التحقق من جلسة التفعيل. أعد فتح التطبيق وحاول مجدداً.';
      }
      final response = await _supabase.rpc(
        'deactivate_registration_v2',
        params: {'p_user_id': userId, 'p_device_id': deviceId, 'p_token': sessionToken},
      );
      final result = _object(response);
      if (result == null || result['ok'] != true) {
        return result?['message']?.toString() ?? 'تعذر حذف بيانات التفعيل من الخادم';
      }
    } on PostgrestException catch (e) {
      debugPrint('Deactivate RPC error: ${e.code} ${e.message}');
      return 'تعذر حذف الحساب من الخادم. تحقق من الاتصال وحاول مجدداً.';
    } catch (e) {
      debugPrint('Deactivate error: $e');
      return 'تعذر حذف الحساب من الخادم. تحقق من الاتصال وحاول مجدداً.';
    }

    await _clearLocalActivation();
    notifyListeners();
    return null;
  }

  Future<void> _clearLocalActivation() async {
    _isActivated = false;
    _currentUser = null;
    await _sessionStore.clear();
    await _saveStateLocally();
  }

  Future<void> _saveStateLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isActivatedKey, _isActivated);
      if (_currentUser != null) {
        await prefs.setString(_currentUserIdKey, _currentUser!.id);
      } else {
        await prefs.remove(_currentUserIdKey);
      }
    } catch (e) {
      debugPrint('Local activation save error: $e');
    }
  }

  @override
  void dispose() {
    _apiService.dispose();
    super.dispose();
  }
}
