import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class GalleryService {
  /// Pick multiple images/GIFs from gallery
  /// Returns list of File paths
  Future<List<File>> pickImages({int maxCount = 50}) async {
    // Request permission
    final status = await Permission.photos.request();
    if (!status.isGranted) {
      throw Exception('Photo permission denied');
    }

    final List<AssetEntity>? assets = await AssetPicker.pickAssets(
      navigatorKey.currentContext!,
      pickerConfig: AssetPickerConfig(
        maxAssets: maxCount,
        requestType: RequestType.image,
        filterOptions: FilterOptionGroup(),
      ),
    );

    if (assets == null || assets.isEmpty) return [];

    final files = <File>[];
    for (final asset in assets) {
      final file = await asset.file;
      if (file != null) {
        files.add(File(file.path));
      }
    }
    return files;
  }
}

// Global navigator key for wechat_assets_picker
final navigatorKey = GlobalKey<NavigatorState>();
