import 'dart:io';
import 'package:dio/dio.dart';
import '../models/sticker_pack.dart';
import '../models/sticker.dart';

class ApiService {
  final Dio _dio;
  final String baseUrl;
  static final Dio _downloadDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 60),
  ));
  static final Map<String, Dio> _serverDioCache = {};

  static Dio _getServerDio(String serverAddr) {
    return _serverDioCache.putIfAbsent(serverAddr, () => Dio(BaseOptions(
      baseUrl: serverAddr,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    )));
  }

  ApiService({required this.baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
        ));

  /// Upload a sticker pack with images (supports custom VPS server)
  Future<UploadResult> uploadPack({
    required String name,
    required String description,
    required List<File> images,
    Function(int, int)? onSendProgress,
    String? customBaseUrl,
    String? authToken,
  }) async {
    final dio = customBaseUrl != null
        ? Dio(BaseOptions(
            baseUrl: customBaseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 120),
            headers: authToken != null ? {'X-Auth-Token': authToken} : null,
          ))
        : _dio;

    final formData = FormData.fromMap({
      'name': name,
      'description': description,
      'stickers': await Future.wait(
        images.map((f) async => MultipartFile.fromFile(
              f.path,
              filename: f.path.split(Platform.pathSeparator).last,
            )),
      ),
    });

    final response = await dio.post(
      '/api/packs',
      data: formData,
      onSendProgress: onSendProgress,
    );

    final packData = response.data['pack'];
    final stickersData = response.data['stickers'] as List;

    return UploadResult(
      pack: StickerPack.fromApiMap(packData),
      stickers: stickersData.map((s) => Sticker.fromApiMap(s)).toList(),
    );
  }

  /// 追加表情到已有表情包（分片上传用）
  Future<UploadResult> appendStickers({
    required String shareCode,
    required List<File> images,
    String? customBaseUrl,
    String? authToken,
    Function(int, int)? onSendProgress,
  }) async {
    final dio = customBaseUrl != null
        ? Dio(BaseOptions(
            baseUrl: customBaseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 120),
            headers: authToken != null ? {'X-Auth-Token': authToken} : null,
          ))
        : _dio;

    final formData = FormData.fromMap({
      'stickers': await Future.wait(
        images.map((f) async => MultipartFile.fromFile(
              f.path,
              filename: f.path.split(Platform.pathSeparator).last,
            )),
      ),
    });

    final response = await dio.post(
      '/api/packs/$shareCode/stickers',
      data: formData,
      onSendProgress: onSendProgress,
    );

    final packData = response.data['pack'];
    final stickersData = response.data['stickers'] as List;

    return UploadResult(
      pack: StickerPack.fromApiMap(packData),
      stickers: stickersData.map((s) => Sticker.fromApiMap(s)).toList(),
    );
  }

  /// Get pack info by share code
  Future<StickerPack> getPackByCode(String code) async {
    final response = await _dio.get('/api/packs/$code');
    return StickerPack.fromApiMap(response.data['pack']);
  }

  /// Get stickers in a pack by share code
  Future<List<StickerWithUrl>> getPackStickers(String code) async {
    final response = await _dio.get('/api/packs/$code/stickers');
    final stickers = response.data['stickers'] as List;
    return stickers
        .map((s) {
          final apiExt = s['extension'] as String?;
          final ext = (apiExt != null && apiExt.isNotEmpty)
              ? (apiExt.startsWith('.') ? apiExt : '.$apiExt')
              : '.png';
          return StickerWithUrl(
            id: s['id'],
            type: s['type'],
            fileUrl: '$baseUrl${s['file_url']}',
            width: s['width'] ?? 0,
            height: s['height'] ?? 0,
            sizeBytes: s['size_bytes'] ?? 0,
            extension: ext,
          );
        })
        .toList();
  }

  /// Download a sticker file to local path
  /// fileUrl should be a full URL (from serverAddr + file_url)
  Future<File> downloadSticker(String fileUrl, String savePath) async {
    await _downloadDio.download(fileUrl, savePath);
    return File(savePath);
  }

  /// Get pack info from a custom server
  Future<StickerPack> getPackByCodeFromServer(String code, String serverAddr) async {
    _validateServerAddr(serverAddr);
    final dio = _getServerDio(serverAddr);
    final response = await dio.get('/api/packs/$code');
    return StickerPack.fromApiMap(response.data['pack']);
  }

  /// Get stickers from a custom server
  Future<List<StickerWithUrl>> getPackStickersFromServer(String code, String serverAddr) async {
    _validateServerAddr(serverAddr);
    final dio = _getServerDio(serverAddr);
    final response = await dio.get('/api/packs/$code/stickers');
    final stickers = response.data['stickers'] as List;
    return stickers
        .map((s) {
          final apiExt = s['extension'] as String?;
          final ext = (apiExt != null && apiExt.isNotEmpty)
              ? (apiExt.startsWith('.') ? apiExt : '.$apiExt')
              : '.png';
          return StickerWithUrl(
            id: s['id'],
            type: s['type'] ?? 'image',
            fileUrl: s['file_url'].toString().startsWith('http')
                ? s['file_url']
                : '$serverAddr${s['file_url']}',
            width: s['width'] ?? 0,
            height: s['height'] ?? 0,
            sizeBytes: s['size_bytes'] ?? 0,
            extension: ext,
          );
        })
        .toList();
  }

  static void _validateServerAddr(String addr) {
    final uri = Uri.tryParse(addr);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw ArgumentError('无效的服务器地址: $addr');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError('服务器地址必须使用 http 或 https');
    }
  }
}

class UploadResult {
  final StickerPack pack;
  final List<Sticker> stickers;

  UploadResult({required this.pack, required this.stickers});
}

class StickerWithUrl {
  final String id;
  final String type;
  final String fileUrl;
  final int width;
  final int height;
  final int sizeBytes;
  final String extension;

  StickerWithUrl({
    required this.id,
    required this.type,
    required this.fileUrl,
    this.width = 0,
    this.height = 0,
    this.sizeBytes = 0,
    this.extension = '.png',
  });
}
