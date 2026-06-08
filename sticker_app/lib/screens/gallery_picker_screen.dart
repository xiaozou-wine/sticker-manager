import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class GalleryPickerScreen extends StatefulWidget {
  final String? targetPackId;

  const GalleryPickerScreen({super.key, this.targetPackId});

  @override
  State<GalleryPickerScreen> createState() => _GalleryPickerScreenState();
}

class _GalleryPickerScreenState extends State<GalleryPickerScreen> {
  List<AssetEntity> _selectedAssets = [];
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择表情包'),
        actions: [
          if (_selectedAssets.isNotEmpty)
            TextButton(
              onPressed: _isProcessing ? null : _confirmSelection,
              child: Text(
                '确定 (${_selectedAssets.length})',
                style: const TextStyle(fontSize: 16),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isProcessing)
            const LinearProgressIndicator()
          else if (_selectedAssets.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.photo_library_outlined,
                        size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('点击下方按钮选择图片或 GIF',
                        style: TextStyle(color: Colors.grey, fontSize: 16)),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _pickAssets,
                      icon: const Icon(Icons.add_photo_alternate),
                      label: const Text('从相册选择'),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: _selectedAssets.length,
                itemBuilder: (context, index) {
                  final asset = _selectedAssets[index];
                  return _buildAssetTile(asset, index);
                },
              ),
            ),
        ],
      ),
      floatingActionButton: _selectedAssets.isNotEmpty
          ? FloatingActionButton(
              onPressed: _pickAssets,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildAssetTile(AssetEntity asset, int index) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AssetEntityImage(
            asset,
            isOriginal: false,
            fit: BoxFit.cover,
            thumbnailSize: const ThumbnailSize(200, 200),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedAssets.removeAt(index);
              });
            },
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
        if (asset.type == AssetType.video)
          const Positioned(
            bottom: 4,
            left: 4,
            child: Icon(Icons.gif_box, color: Colors.white, size: 20),
          ),
      ],
    );
  }

  Future<void> _pickAssets() async {
    // BUG-1: Check permission before opening picker
    final status = await Permission.photos.request();
    if (!status.isGranted && !status.isLimited) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('需要相册权限才能选择图片'),
            action: SnackBarAction(label: '去设置', onPressed: () => openAppSettings()),
          ),
        );
      }
      return;
    }

    try {
      final List<AssetEntity>? assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: AssetPickerConfig(
          maxAssets: 50,
          requestType: RequestType.image,
          selectedAssets: _selectedAssets,
          filterOptions: FilterOptionGroup(),
        ),
      );

      if (assets != null) {
        setState(() {
          _selectedAssets = assets;
        });
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('PermissionState.denied')
            ? '相册权限被拒绝，请在设置中开启'
            : '选择图片失败，请重试';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            action: e.toString().contains('PermissionState.denied')
                ? SnackBarAction(label: '去设置', onPressed: () => openAppSettings())
                : null,
          ),
        );
      }
    }
  }

  Future<void> _confirmSelection() async {
    if (_selectedAssets.isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      final files = <File>[];
      for (final asset in _selectedAssets) {
        final file = await asset.file;
        if (file != null) {
          files.add(File(file.path));
        }
      }

      if (mounted) {
        Navigator.pop(context, files);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('处理图片失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
}
