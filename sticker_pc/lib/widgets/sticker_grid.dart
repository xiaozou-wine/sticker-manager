import 'package:flutter/material.dart';
import '../models/sticker.dart';
import 'sticker_tile.dart';

class StickerGrid extends StatelessWidget {
  final List<Sticker> stickers;
  final Function(Sticker)? onStickerTap;
  final Function(Sticker)? onStickerLongPress;
  final String? baseUrl;

  const StickerGrid({
    super.key,
    required this.stickers,
    this.onStickerTap,
    this.onStickerLongPress,
    this.baseUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (stickers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_emotions_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('还没有表情包', style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 110).floor().clamp(3, 16);
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: stickers.length,
          itemBuilder: (context, index) {
            final sticker = stickers[index];
            return StickerTile(
              localPath: sticker.localPath,
              imageUrl: baseUrl != null ? '$baseUrl/api/stickers/${sticker.id}/file' : null,
              onTap: onStickerTap != null ? () => onStickerTap!(sticker) : null,
              onLongPress: onStickerLongPress != null ? () => onStickerLongPress!(sticker) : null,
            );
          },
        );
      },
    );
  }
}
