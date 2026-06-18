class LanDevice {
  final String fingerprint;
  final String alias;
  final String deviceModel;
  final String deviceType;
  final int port;
  final String ip;
  DateTime lastSeen;

  LanDevice({
    required this.fingerprint,
    required this.alias,
    required this.deviceModel,
    required this.deviceType,
    required this.port,
    required this.ip,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  bool get isExpired => DateTime.now().difference(lastSeen).inSeconds > 15;

  factory LanDevice.fromJson(Map<String, dynamic> json, String ip) {
    return LanDevice(
      fingerprint: json['fingerprint'] as String,
      alias: json['alias'] as String? ?? 'Unknown',
      deviceModel: json['deviceModel'] as String? ?? '',
      deviceType: json['deviceType'] as String? ?? 'mobile',
      port: json['port'] as int? ?? 53320,
      ip: ip,
    );
  }

  Map<String, dynamic> toJson() => {
    'alias': alias,
    'deviceModel': deviceModel,
    'deviceType': deviceType,
    'fingerprint': fingerprint,
    'port': port,
    'appName': 'StickerApp',
    'version': '1.0',
  };
}

class LanTransferRequest {
  final String packName;
  final String packId;
  final int stickerCount;
  final int totalSizeBytes;
  final String senderName;
  final String senderFingerprint;

  LanTransferRequest({
    required this.packName,
    required this.packId,
    required this.stickerCount,
    required this.totalSizeBytes,
    required this.senderName,
    required this.senderFingerprint,
  });

  factory LanTransferRequest.fromJson(Map<String, dynamic> json) {
    return LanTransferRequest(
      packName: json['packName'] as String,
      packId: json['packId'] as String,
      stickerCount: json['stickerCount'] as int,
      totalSizeBytes: json['totalSizeBytes'] as int? ?? 0,
      senderName: json['senderName'] as String? ?? 'Unknown',
      senderFingerprint: json['senderFingerprint'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'packName': packName,
    'packId': packId,
    'stickerCount': stickerCount,
    'totalSizeBytes': totalSizeBytes,
    'senderName': senderName,
    'senderFingerprint': senderFingerprint,
  };
}

class LanTransferResult {
  final bool success;
  final int receivedCount;
  final int failedCount;

  LanTransferResult({
    required this.success,
    required this.receivedCount,
    required this.failedCount,
  });

  factory LanTransferResult.fromJson(Map<String, dynamic> json) {
    return LanTransferResult(
      success: json['success'] as bool? ?? false,
      receivedCount: json['receivedCount'] as int? ?? 0,
      failedCount: json['failedCount'] as int? ?? 0,
    );
  }
}
