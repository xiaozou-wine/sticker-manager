import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../storage_service.dart';
import '../../models/sticker_pack.dart';
import '../../models/sticker.dart';
import 'lan_models.dart';

typedef OnTransferRequest = Future<bool> Function(LanTransferRequest request);
typedef OnTransferProgress = void Function(double progress);
typedef OnTransferComplete = void Function(String packName, int receivedCount);

class LanTransferService {
  static const int _port = 53320;
  // 上传 token 有效期（秒），/send 被接受后生成，超时失效
  static const int _tokenTtlSeconds = 60;

  HttpServer? _server;
  final StorageService storageService;
  final OnTransferRequest onRequestReceived;
  final OnTransferComplete? onTransferComplete;
  final String senderAlias;
  final String senderFingerprint;
  bool _isBusy = false;
  // 存储待使用的上传 token: token -> 过期时间
  final Map<String, DateTime> _pendingTokens = {};

  LanTransferService({
    required this.storageService,
    required this.onRequestReceived,
    required this.senderAlias,
    required this.senderFingerprint,
    this.onTransferComplete,
  });

  bool get isRunning => _server != null;

  /// Ping 检测目标设备是否在线（静态方法，不需要实例）
  static Future<bool> pingDevice(String ip, {int port = _port}) async {
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 3), receiveTimeout: const Duration(seconds: 3)));
      final resp = await dio.get('http://$ip:$port/api/sticker/ping');
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
    _server!.listen(_handleRequest);
  }

  void stop() {
    _server?.close();
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    if (path == '/api/sticker/ping' && request.method == 'GET') {
      request.response..statusCode = HttpStatus.ok..write('ok');
      await request.response.close();
      return;
    }
    if (path == '/api/sticker/send' && request.method == 'POST') {
      await _handleSendRequest(request);
      return;
    }
    if (path == '/api/sticker/upload' && request.method == 'POST') {
      await _handleUpload(request);
      return;
    }
    request.response..statusCode = HttpStatus.notFound..write('not found');
    await request.response.close();
  }

  /// 清理过期的上传 token
  void _cleanExpiredTokens() {
    final now = DateTime.now();
    _pendingTokens.removeWhere((_, expiry) => now.isAfter(expiry));
  }

  /// 校验上传 token 是否有效（来自 query 参数）
  bool _validateToken(String? token) {
    if (token == null || token.isEmpty) return false;
    _cleanExpiredTokens();
    final expiry = _pendingTokens.remove(token);
    if (expiry == null) return false;
    return DateTime.now().isBefore(expiry);
  }

  Future<void> _handleSendRequest(HttpRequest request) async {
    if (_isBusy) {
      request.response..statusCode = HttpStatus.conflict
        ..write(jsonEncode({'error': 'busy'}));
      await request.response.close();
      return;
    }
    try {
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final transferReq = LanTransferRequest.fromJson(json);
      final accepted = await onRequestReceived(transferReq);
      if (accepted) {
        // 用户接受后生成一次性上传 token，60 秒有效
        final token = const Uuid().v4();
        _pendingTokens[token] = DateTime.now().add(const Duration(seconds: _tokenTtlSeconds));
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'status': 'accepted', 'token': token}));
      } else {
        request.response
          ..statusCode = HttpStatus.forbidden
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'status': 'declined'}));
      }
      await request.response.close();
    } catch (e) {
      request.response..statusCode = HttpStatus.badRequest
        ..write(jsonEncode({'error': 'invalid request'}));
      await request.response.close();
    }
  }

  Future<void> _handleUpload(HttpRequest request) async {
    // 校验一次性上传 token（必须由 /send 流程生成）
    final token = request.uri.queryParameters['token'];
    if (!_validateToken(token)) {
      request.response..statusCode = HttpStatus.forbidden
        ..write(jsonEncode({'error': 'invalid or expired token, call /send first'}));
      await request.response.close();
      return;
    }
    if (_isBusy) {
      request.response..statusCode = HttpStatus.conflict
        ..write(jsonEncode({'error': 'busy'}));
      await request.response.close();
      return;
    }
    _isBusy = true;
    int receivedCount = 0;
    int failedCount = 0;
    try {
      final contentType = request.headers.contentType;
      if (contentType == null || contentType.mimeType != 'multipart/form-data') {
        request.response..statusCode = HttpStatus.badRequest
          ..write(jsonEncode({'error': 'expected multipart/form-data'}));
        await request.response.close();
        return;
      }
      final boundary = contentType.parameters['boundary'];
      if (boundary == null) {
        request.response..statusCode = HttpStatus.badRequest
          ..write(jsonEncode({'error': 'no boundary'}));
        await request.response.close();
        return;
      }
      String? packName;
      String? packId;
      final List<List<int>> fileBytesList = [];
      final transformer = MimeMultipartTransformer(boundary);
      final parts = transformer.bind(request);
      await for (final part in parts) {
        final headers = part.headers;
        final disposition = headers['content-disposition'] ?? '';
        final nameMatch = RegExp(r'name="([^"]+)"').firstMatch(disposition);
        final fieldName = nameMatch?.group(1) ?? '';
        final bytes = await part.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
        if (fieldName == 'packName') {
          packName = utf8.decode(bytes);
        } else if (fieldName == 'packId') {
          packId = utf8.decode(bytes);
        } else if (fieldName.startsWith('file')) {
          fileBytesList.add(bytes);
        }
      }
      if (packName == null || packId == null || fileBytesList.isEmpty) {
        request.response..statusCode = HttpStatus.badRequest
          ..write(jsonEncode({'error': 'missing packName, packId, or files'}));
        await request.response.close();
        return;
      }
      // packId 只允许字母数字、下划线、短横线，防止路径穿越
      if (!RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(packId)) {
        request.response..statusCode = HttpStatus.badRequest
          ..write(jsonEncode({'error': 'invalid packId'}));
        await request.response.close();
        return;
      }
      final pack = StickerPack(id: packId, name: packName, source: 'lan', stickerCount: fileBytesList.length);
      await storageService.insertPack(pack);
      final appDir = await getApplicationDocumentsDirectory();
      final packDir = Directory(p.join(appDir.path, 'stickers', packId));
      if (!await packDir.exists()) await packDir.create(recursive: true);
      final stickers = <Sticker>[];
      for (int i = 0; i < fileBytesList.length; i++) {
        try {
          var fileData = fileBytesList[i];
          var ext = _guessExtension(fileData);
          // WebP 转 PNG，与项目其他导入路径保持一致
          if (ext == '.webp') {
            final converted = _convertWebpToPng(Uint8List.fromList(fileData));
            if (converted != null) {
              fileData = converted;
              ext = '.png';
            }
          }
          final stickerId = '${packId}_$i';
          final localPath = p.join(packDir.path, '$stickerId$ext');
          await File(localPath).writeAsBytes(fileData);
          stickers.add(Sticker(id: stickerId, packId: packId, type: 'image',
            sizeBytes: fileData.length, extension: ext, localPath: localPath));
          receivedCount++;
        } catch (e) {
          failedCount++;
        }
      }
      if (stickers.isNotEmpty) {
        await storageService.insertStickers(stickers);
        await storageService.updatePackStickerCount(packId);
        pack.coverLocal = stickers.first.localPath;
        await storageService.updatePack(pack);
      }
      request.response..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': true, 'receivedCount': receivedCount, 'failedCount': failedCount}));
      await request.response.close();
      // 通知 UI 接收完成
      onTransferComplete?.call(packName, receivedCount);
    } catch (e) {
      try {
        request.response..statusCode = HttpStatus.internalServerError
          ..write(jsonEncode({'error': e.toString()}));
        await request.response.close();
      } catch (_) {}
    } finally {
      _isBusy = false;
    }
  }

  Future<LanTransferResult> sendPack({
    required LanDevice device,
    required StickerPack pack,
    OnTransferProgress? onProgress,
  }) async {
    final stickers = await storageService.getStickersByPackId(pack.id);
    final files = stickers
        .where((s) => s.localPath != null && File(s.localPath!).existsSync())
        .map((s) => File(s.localPath!))
        .toList();
    if (files.isEmpty) {
      return LanTransferResult(success: false, receivedCount: 0, failedCount: 0);
    }
    final totalSize = files.fold<int>(0, (sum, f) => sum + f.lengthSync());
    final baseUrl = 'http://${device.ip}:${device.port}';
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 30)));
    String? uploadToken;
    try {
      final resp = await dio.post('$baseUrl/api/sticker/send', data: {
        'packName': pack.name, 'packId': pack.id,
        'stickerCount': files.length, 'totalSizeBytes': totalSize,
        'senderName': senderAlias, 'senderFingerprint': senderFingerprint,
      });
      if (resp.statusCode != 200) {
        return LanTransferResult(success: false, receivedCount: 0, failedCount: 0);
      }
      // 提取一次性上传 token
      final respData = resp.data;
      if (respData is Map<String, dynamic>) {
        uploadToken = respData['token'] as String?;
      }
      if (uploadToken == null || uploadToken.isEmpty) {
        return LanTransferResult(success: false, receivedCount: 0, failedCount: 0);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        return LanTransferResult(success: false, receivedCount: 0, failedCount: files.length);
      }
      rethrow;
    }
    final formData = FormData.fromMap({
      'packName': pack.name, 'packId': pack.id,
      for (int i = 0; i < files.length; i++)
        'file_$i': await MultipartFile.fromFile(files[i].path, filename: p.basename(files[i].path)),
    });
    final uploadDio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(minutes: 10)));
    final resp = await uploadDio.post('$baseUrl/api/sticker/upload?token=$uploadToken', data: formData,
      onSendProgress: (sent, total) {
        if (total > 0 && onProgress != null) onProgress(sent / total);
      },
    );
    return LanTransferResult.fromJson(resp.data as Map<String, dynamic>);
  }

  String _guessExtension(List<int> data) {
    if (data.length >= 4) {
      if (data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47) return '.png';
      if (data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x38) return '.gif';
      if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) return '.jpg';
      if (data.length >= 12 &&
          data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 &&
          data[8] == 0x57 && data[9] == 0x45 && data[10] == 0x42 && data[11] == 0x50) return '.webp';
    }
    return '.png';
  }

  /// WebP 转 PNG，返回 null 表示转换失败（保留原始 WebP）
  List<int>? _convertWebpToPng(Uint8List webpData) {
    try {
      final decoded = img.decodeImage(webpData);
      if (decoded == null) return null;
      return img.encodePng(decoded);
    } catch (_) {
      return null;
    }
  }
}
