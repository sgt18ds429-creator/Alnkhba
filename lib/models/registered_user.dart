import 'dart:convert';

class RegisteredUser {
  final String id;
  final String fullName;
  final String activationCode;
  final int activatedAt;
  final int? expiresAt; // Timestamp in ms when activation expires. null/0 means unlimited.
  final String? deviceId;
  final bool pending;

  RegisteredUser({
    required this.id,
    required this.fullName,
    required this.activationCode,
    required this.activatedAt,
    this.expiresAt,
    this.deviceId,
    this.pending = false,
  });

  bool get isExpired {
    if (expiresAt == null || expiresAt == 0) return false;
    return DateTime.now().millisecondsSinceEpoch > expiresAt!;
  }

  int get remainingDays {
    if (expiresAt == null || expiresAt == 0) return 999999;
    final diff = expiresAt! - DateTime.now().millisecondsSinceEpoch;
    if (diff <= 0) return 0;
    return (diff / (1000 * 60 * 60 * 24)).ceil();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fullName': fullName,
      'activationCode': activationCode,
      'activatedAt': activatedAt,
      'expiresAt': expiresAt,
      'deviceId': deviceId,
      'pending': pending,
    };
  }

  factory RegisteredUser.fromMap(Map<String, dynamic> map) {
    return RegisteredUser(
      id: map['id']?.toString() ?? '',
      fullName: map['fullName']?.toString() ?? '',
      activationCode: map['activationCode']?.toString() ?? '',
      activatedAt: (map['activatedAt'] as num?)?.toInt() ?? 0,
      expiresAt: (map['expiresAt'] as num?)?.toInt(),
      deviceId: map['deviceId']?.toString(),
      pending: map['pending'] == true,
    );
  }

  String toJson() => json.encode(toMap());

  factory RegisteredUser.fromJson(String source) => RegisteredUser.fromMap(json.decode(source));
}
