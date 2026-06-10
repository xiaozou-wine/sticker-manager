import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';

/// 从指定相册批量导入全部照片。
/// 展示相册列表 → 选择相册 → 加载全部照片 → 全选/取消 → 返回 List<File>
class AlbumPickerScreen extends StatefulWidget {
  const AlbumPickerScreen({super.key});

  @override
  State<AlbumPickerScreen> createState() => _AlbumPickerScreenState();
}

class _AlbumPickerScreenState extends State<AlbumPickerScreen> {
  List<AssetPathEntity> _albums = [];
  bool _loading = true;
  String? _error;

  // 当前选中的相册
  AssetPathEntity? _selectedAlbum;
  List<AssetEntity> _assets = [];
  final Set<String> _selectedIds = {};
  bool _loadingAssets = false;
  bool _allSelected = false;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    final status = await Permission.photos.request();
    if (!status.isGranted && !status.isLimited) {
      setState(() {
        _error = '需要相册权限，请在设置中授权';
        _loading = false;
      });
      return;
    }

    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
      );
      if (mounted) {
        setState(() {
          _albums = albums;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载相册失败';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadAlbumAssets(AssetPathEntity album) async {
    setState(() {
      _selectedAlbum = album;
      _loadingAssets = true;
      _assets = [];
      _selectedIds.clear();
      _allSelected = false;
    });

    final count = await album.assetCountAsync;
    final assets = await album.getAssetListPaged(page: 0, size: count);

    if (mounted) {
      setState(() {
        _assets = assets;
        _loadingAssets = false;
      });
    }
  }

  void _toggleSelect(AssetEntity asset) {
    setState(() {
      if (_selectedIds.contains(asset.id)) {
        _selectedIds.remove(asset.id);
      } else {
        _selectedIds.add(asset.id);
      }
      _allSelected = _selectedIds.length == _assets.length;
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_allSelected) {
        _selectedIds.clear();
        _allSelected = false;
      } else {
        for (final a in _assets) {
          _selectedIds.add(a.id);
        }
        _allSelected = true;
      }
    });
  }

  Future<void> _confirmSelection() async {
    if (_selectedIds.isEmpty) return;

    setState(() => _loadingAssets = true);

    try {
      final files = <File>[];
      for (final asset in _assets) {
        if (_selectedIds.contains(asset.id)) {
          final file = await asset.file;
          if (file != null) files.add(File(file.path));
        }
      }
      if (mounted) Navigator.pop(context, files);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('处理图片失败，请重试')),
        );
        setState(() => _loadingAssets = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedAlbum?.name ?? '选择相册'),
        leading: _selectedAlbum != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _selectedAlbum = null;
                  _assets = [];
                  _selectedIds.clear();
                  _allSelected = false;
                }),
              )
            : null,
        actions: [
          if (_selectedAlbum != null && _assets.isNotEmpty) ...[
            TextButton(
              onPressed: _toggleSelectAll,
              child: Text(_allSelected ? '取消全选' : '全选'),
            ),
            if (_selectedIds.isNotEmpty)
              TextButton(
                onPressed: _confirmSelection,
                child: Text('确定 (${_selectedIds.length})'),
              ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => openAppSettings(),
              child: const Text('去设置'),
            ),
          ],
        ),
      );
    }

    // 显示相册中的照片
    if (_selectedAlbum != null) {
      if (_loadingAssets) return const Center(child: CircularProgressIndicator());
      if (_assets.isEmpty) return const Center(child: Text('该相册没有图片'));

      return GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
        ),
        itemCount: _assets.length,
        itemBuilder: (context, index) {
          final asset = _assets[index];
          final selected = _selectedIds.contains(asset.id);
          return _AssetTile(
            asset: asset,
            selected: selected,
            onTap: () => _toggleSelect(asset),
          );
        },
      );
    }

    // 显示相册列表
    if (_albums.isEmpty) return const Center(child: Text('没有找到相册'));

    return ListView.builder(
      itemCount: _albums.length,
      itemBuilder: (context, index) {
        final album = _albums[index];
        return FutureBuilder<int>(
          future: album.assetCountAsync,
          builder: (ctx, snap) {
            final count = snap.data ?? 0;
            return ListTile(
              leading: _AlbumThumbnail(album: album),
              title: Text(album.name, style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text('$count 张'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _loadAlbumAssets(album),
            );
          },
        );
      },
    );
  }
}

class _AlbumThumbnail extends StatelessWidget {
  final AssetPathEntity album;
  const _AlbumThumbnail({required this.album});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AssetEntity>>(
      future: album.getAssetListPaged(page: 0, size: 1),
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return Container(
            width: 48, height: 48,
            color: Colors.grey[200],
            child: const Icon(Icons.photo_library, color: Colors.grey),
          );
        }
        return FutureBuilder<File?>(
          future: snap.data!.first.file,
          builder: (ctx2, fileSnap) {
            if (!fileSnap.hasData || fileSnap.data == null) {
              return Container(
                width: 48, height: 48,
                color: Colors.grey[200],
                child: const Icon(Icons.photo, color: Colors.grey),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(
                fileSnap.data!,
                width: 48, height: 48,
                fit: BoxFit.cover,
              ),
            );
          },
        );
      },
    );
  }
}

class _AssetTile extends StatelessWidget {
  final AssetEntity asset;
  final bool selected;
  final VoidCallback onTap;

  const _AssetTile({
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<File?>(
            future: asset.file,
            builder: (ctx, snap) {
              if (!snap.hasData || snap.data == null) {
                return Container(color: Colors.grey[200]);
              }
              return Image.file(snap.data!, fit: BoxFit.cover);
            },
          ),
          if (selected)
            Container(
              color: Colors.blue.withValues(alpha: 0.3),
              child: const Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.check_circle, color: Colors.white, size: 22),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
