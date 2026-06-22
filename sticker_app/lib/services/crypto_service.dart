import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class ShareLinkInfo {
  final String serverAddr;
  final String packId;
  final String shareCode;
  final Uint8List? key; // null = 无加密（原图）

  ShareLinkInfo({
    required this.serverAddr,
    required this.packId,
    required this.shareCode,
    this.key,
  });

  bool get isEncrypted => key != null;
}

class CryptoService {
  /// 生成 32 字节随机 AES 密钥
  static Uint8List generateKey() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
  }

  /// AES-256-GCM 加密，返回 nonce(12) + tag(16) + ciphertext
  static Uint8List encryptData(Uint8List plaintext, Uint8List key) {
    final nonce = _randomBytes(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final ciphertext = cipher.process(plaintext);
    // ciphertext 末尾 16 字节就是 tag
    final tag = ciphertext.sublist(ciphertext.length - 16);
    final body = ciphertext.sublist(0, ciphertext.length - 16);
    final result = Uint8List(12 + 16 + body.length);
    result.setRange(0, 12, nonce);
    result.setRange(12, 28, tag);
    result.setRange(28, result.length, body);
    return result;
  }

  /// AES-256-GCM 解密，输入 nonce(12) + tag(16) + ciphertext
  static Uint8List decryptData(Uint8List data, Uint8List key) {
    if (data.length < 28) throw ArgumentError('data too short');
    final nonce = data.sublist(0, 12);
    final tag = data.sublist(12, 28);
    final body = data.sublist(28);
    // pointycastle GCM 需要 ciphertext + tag 拼接
    final cipherWithTag = Uint8List(body.length + 16);
    cipherWithTag.setRange(0, body.length, body);
    cipherWithTag.setRange(body.length, cipherWithTag.length, tag);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    return cipher.process(cipherWithTag);
  }

  /// 生成分享链接: sticker://share/{base64url(server|packId|code)} 或带 #{base64url(key)}
  static String buildShareLink({
    required String serverAddr,
    required String packId,
    required String shareCode,
    Uint8List? key,
  }) {
    serverAddr = serverAddr.replaceAll(RegExp(r'/+$'), '');
    final payload = '$serverAddr|$packId|$shareCode';
    final encodedPayload = base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
    if (key == null) {
      return 'sticker://share/$encodedPayload';
    }
    final encodedKey = base64Url.encode(key).replaceAll('=', '');
    return 'sticker://share/$encodedPayload#$encodedKey';
  }

  /// 解析分享链接（支持有密钥和无密钥两种格式）
  static ShareLinkInfo? parseShareLink(String link) {
    link = link.trim();
    if (!link.startsWith('sticker://share/')) return null;
    final body = link.substring('sticker://share/'.length);
    final hashIdx = body.indexOf('#');
    try {
      String encodedPayload;
      Uint8List? key;
      if (hashIdx >= 0) {
        encodedPayload = body.substring(0, hashIdx);
        key = Uint8List.fromList(base64Url.decode(_pad(body.substring(hashIdx + 1))));
        if (key.length != 32) return null;
      } else {
        encodedPayload = body;
      }
      final payload = utf8.decode(base64Url.decode(_pad(encodedPayload)));
      final parts = payload.split('|');
      if (parts.length != 3) return null;
      // 清理可能的隐藏字符（零宽空格、换行等）
      final serverAddr = parts[0].replaceAll(RegExp(r'[\s​‌‍﻿]+'), '').replaceAll(RegExp(r'/+$'), '');
      return ShareLinkInfo(serverAddr: serverAddr, packId: parts[1].trim(), shareCode: parts[2].trim(), key: key);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }

  static String _pad(String s) {
    final r = s.length % 4;
    return r == 0 ? s : s + '=' * (4 - r);
  }
}
