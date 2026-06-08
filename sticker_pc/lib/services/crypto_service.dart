import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class ShareLinkInfo {
  final String serverAddr;
  final String packId;
  final String shareCode;
  final Uint8List key;

  ShareLinkInfo({
    required this.serverAddr,
    required this.packId,
    required this.shareCode,
    required this.key,
  });
}

class CryptoService {
  static Uint8List generateKey() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
  }

  static Uint8List encryptData(Uint8List plaintext, Uint8List key) {
    final nonce = _randomBytes(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final ciphertext = cipher.process(plaintext);
    final tag = ciphertext.sublist(ciphertext.length - 16);
    final body = ciphertext.sublist(0, ciphertext.length - 16);
    final result = Uint8List(12 + 16 + body.length);
    result.setRange(0, 12, nonce);
    result.setRange(12, 28, tag);
    result.setRange(28, result.length, body);
    return result;
  }

  static Uint8List decryptData(Uint8List data, Uint8List key) {
    if (data.length < 28) throw ArgumentError('data too short');
    final nonce = data.sublist(0, 12);
    final tag = data.sublist(12, 28);
    final body = data.sublist(28);
    final cipherWithTag = Uint8List(body.length + 16);
    cipherWithTag.setRange(0, body.length, body);
    cipherWithTag.setRange(body.length, cipherWithTag.length, tag);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    return cipher.process(cipherWithTag);
  }

  static String buildShareLink({
    required String serverAddr,
    required String packId,
    required String shareCode,
    required Uint8List key,
  }) {
    serverAddr = serverAddr.replaceAll(RegExp(r'/+$'), '');
    final payload = '$serverAddr|$packId|$shareCode';
    final encodedPayload = base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
    final encodedKey = base64Url.encode(key).replaceAll('=', '');
    return 'sticker://share/$encodedPayload#$encodedKey';
  }

  static ShareLinkInfo? parseShareLink(String link) {
    link = link.trim();
    if (!link.startsWith('sticker://share/')) return null;
    final body = link.substring('sticker://share/'.length);
    final hashIdx = body.indexOf('#');
    if (hashIdx < 0) return null;
    try {
      final payload = utf8.decode(base64Url.decode(_pad(body.substring(0, hashIdx))));
      final key = Uint8List.fromList(base64Url.decode(_pad(body.substring(hashIdx + 1))));
      if (key.length != 32) return null;
      final parts = payload.split('|');
      if (parts.length != 3) return null;
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
