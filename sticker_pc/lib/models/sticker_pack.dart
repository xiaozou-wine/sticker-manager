class StickerPack {
  final String id;
  String name;
  String description;
  String? coverUrl;
  String? coverLocal;
  String source; // 'gallery', 'link', 'manual'
  String? shareCode;
  bool isUploaded;
  int stickerCount;
  int sortOrder;
  final DateTime createdAt;
  DateTime updatedAt;

  StickerPack({
    required this.id,
    required this.name,
    this.description = '',
    this.coverUrl,
    this.coverLocal,
    this.source = 'gallery',
    this.shareCode,
    this.isUploaded = false,
    this.stickerCount = 0,
    this.sortOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'cover_url': coverUrl,
      'cover_local': coverLocal,
      'source': source,
      'share_code': shareCode,
      'is_uploaded': isUploaded ? 1 : 0,
      'sticker_count': stickerCount,
      'sort_order': sortOrder,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory StickerPack.fromMap(Map<String, dynamic> map) {
    return StickerPack(
      id: map['id'],
      name: map['name'],
      description: map['description'] ?? '',
      coverUrl: map['cover_url'],
      coverLocal: map['cover_local'],
      source: map['source'] ?? 'gallery',
      shareCode: map['share_code'],
      isUploaded: map['is_uploaded'] == 1,
      stickerCount: map['sticker_count'] ?? 0,
      sortOrder: map['sort_order'] ?? 0,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  factory StickerPack.fromApiMap(Map<String, dynamic> map) {
    return StickerPack(
      id: map['id'],
      name: map['name'],
      description: map['description'] ?? '',
      coverUrl: map['cover_url'],
      shareCode: map['share_code'],
      stickerCount: map['sticker_count'] ?? 0,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : DateTime.now(),
    );
  }
}
