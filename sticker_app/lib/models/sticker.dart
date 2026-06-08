class Sticker {
  final String id;
  final String packId;
  final String type; // 'image' or 'gif'
  final int width;
  final int height;
  final int sizeBytes;
  final String extension;
  final DateTime createdAt;
  final String? localPath;

  Sticker({
    required this.id,
    required this.packId,
    required this.type,
    this.width = 0,
    this.height = 0,
    this.sizeBytes = 0,
    this.extension = '.png',
    DateTime? createdAt,
    this.localPath,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pack_id': packId,
      'type': type,
      'width': width,
      'height': height,
      'size_bytes': sizeBytes,
      'extension': extension,
      'created_at': createdAt.toIso8601String(),
      'local_path': localPath,
    };
  }

  factory Sticker.fromMap(Map<String, dynamic> map) {
    return Sticker(
      id: map['id'],
      packId: map['pack_id'],
      type: map['type'],
      width: map['width'] ?? 0,
      height: map['height'] ?? 0,
      sizeBytes: map['size_bytes'] ?? 0,
      extension: map['extension'] ?? '.png',
      createdAt: DateTime.parse(map['created_at']),
      localPath: map['local_path'],
    );
  }

  factory Sticker.fromApiMap(Map<String, dynamic> map) {
    final fileUrl = map['file_url'] as String? ?? '';
    final ext = fileUrl.contains('.') ? '.${fileUrl.split('.').last}' : '.png';
    return Sticker(
      id: map['id'],
      packId: '',
      type: map['type'] ?? 'image',
      width: map['width'] ?? 0,
      height: map['height'] ?? 0,
      sizeBytes: map['size_bytes'] ?? 0,
      extension: ext,
    );
  }
}
