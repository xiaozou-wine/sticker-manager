import 'dart:io';
import 'package:dio/dio.dart';
import '../models/sticker_pack.dart';
import '../models/sticker.dart';

class ApiService {
  final Dio _dio;
  final String baseUrl;

  ApiService({required this.baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
        ));

  /// Upload a sticker pack with images
  /// Returns the created pack and list of uploaded stickers
  Future<UploadResult> uploadPack({
    required String name,
    required String description,
    required List<File> images,
    Function(int, int)? onSendProgress,
  }) async {
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

    final response = await _dio.post(
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
        .map((s) => StickerWithUrl(
              id: s['id'],
              type: s['type'],
              fileUrl: '$baseUrl${s['file_url']}',
              width: s['width'] ?? 0,
              height: s['height'] ?? 0,
              sizeBytes: s['size_bytes'] ?? 0,
            ))
        .toList();
  }

  /// Download a sticker file to local path
  Future<File> downloadSticker(String fileUrl, String savePath) async {
    await _dio.download(fileUrl, savePath);
    return File(savePath);
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

  StickerWithUrl({
    required this.id,
    required this.type,
    required this.fileUrl,
    this.width = 0,
    this.height = 0,
    this.sizeBytes = 0,
  });
}
