import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart';
import 'dart:ffi';

/// Windows image clipboard service using Win32 API via FFI.
/// Supports copying PNG/JPG/BMP images as CF_DIB, and GIF as CF_HDROP (file path).
class ClipboardService {
  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static Future<void> copyImage(String filePath) async {
    if (Platform.isWindows) {
      return _copyImageWindows(filePath);
    }
  }

  static Future<void> _copyImageWindows(String filePath) async {
    final ext = filePath.split('.').last.toLowerCase();
    if (ext == 'gif') {
      await _copyFileToClipboard(filePath);
    } else {
      final bytes = await File(filePath).readAsBytes();
      await _imageBytesToClipboard(bytes);
    }
  }

  /// Copy image bytes to Windows clipboard as CF_DIB.
  static Future<void> _imageBytesToClipboard(Uint8List imageBytes) async {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final user32 = DynamicLibrary.open('user32.dll');

    final openClipboard = user32.lookupFunction<
        Uint32 Function(IntPtr hwnd),
        int Function(int hwnd)>('OpenClipboard');
    final closeClipboard =
        user32.lookupFunction<Void Function(), void Function()>('CloseClipboard');
    final emptyClipboard =
        user32.lookupFunction<Void Function(), void Function()>('EmptyClipboard');
    final setClipboardData = user32.lookupFunction<
        IntPtr Function(Uint32 uFormat, IntPtr hMem),
        int Function(int uFormat, int hMem)>('SetClipboardData');
    final globalAlloc = kernel32.lookupFunction<
        IntPtr Function(Uint32 uFlags, IntPtr dwBytes),
        int Function(int uFlags, int dwBytes)>('GlobalAlloc');
    final globalLock = kernel32.lookupFunction<
        IntPtr Function(IntPtr hMem),
        int Function(int hMem)>('GlobalLock');
    final globalUnlock = kernel32.lookupFunction<
        Int32 Function(IntPtr hMem),
        int Function(int hMem)>('GlobalUnlock');
    final globalFree = kernel32.lookupFunction<
        IntPtr Function(IntPtr hMem),
        int Function(int hMem)>('GlobalFree');

    const cfDib = 8;
    const gmMoveable = 0x0002;

    // Decode image
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return;

    final w = image.width;
    final h = image.height;
    final pixels = byteData.buffer.asUint8List();
    const headerSize = 40;
    final pixelSize = w * h * 4;
    final totalSize = headerSize + pixelSize;

    // Convert RGBA → BGRA (bottom-up DIB)
    final bgra = Uint8List(pixelSize);
    for (int y = 0; y < h; y++) {
      final srcRow = (h - 1 - y) * w * 4;
      final dstRow = y * w * 4;
      for (int x = 0; x < w; x++) {
        final si = srcRow + x * 4;
        final di = dstRow + x * 4;
        bgra[di] = pixels[si + 2];     // B ← R
        bgra[di + 1] = pixels[si + 1]; // G
        bgra[di + 2] = pixels[si];     // R ← B
        bgra[di + 3] = pixels[si + 3]; // A
      }
    }

    if (openClipboard(0) == 0) return;
    try {
      emptyClipboard();

      final hMem = globalAlloc(gmMoveable, totalSize);
      if (hMem == 0) return;

      final ptr = Pointer<Uint8>.fromAddress(globalLock(hMem));
      if (ptr.address == 0) {
        globalFree(hMem);
        return;
      }

      // Write BITMAPINFOHEADER
      final header = ByteData.view(ptr.asTypedList(totalSize).buffer);
      header.setUint32(0, headerSize, Endian.little);   // biSize
      header.setInt32(4, w, Endian.little);              // biWidth
      header.setInt32(8, -h, Endian.little);             // biHeight (negative = top-down)
      header.setUint16(12, 1, Endian.little);            // biPlanes
      header.setUint16(14, 32, Endian.little);           // biBitCount
      header.setUint32(16, 0, Endian.little);            // biCompression (BI_RGB)
      header.setUint32(20, pixelSize, Endian.little);    // biSizeImage

      // Write pixel data after header
      ptr.asTypedList(totalSize).setRange(headerSize, totalSize, bgra);

      globalUnlock(hMem);

      if (setClipboardData(cfDib, hMem) == 0) {
        globalFree(hMem);
      }
      // On success: Windows owns hMem, do NOT free
    } finally {
      closeClipboard();
    }
  }

  /// Copy a file path to clipboard as CF_HDROP (for GIF animated stickers).
  static Future<void> _copyFileToClipboard(String filePath) async {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final user32 = DynamicLibrary.open('user32.dll');

    final openClipboard = user32.lookupFunction<
        Uint32 Function(IntPtr hwnd),
        int Function(int hwnd)>('OpenClipboard');
    final closeClipboard =
        user32.lookupFunction<Void Function(), void Function()>('CloseClipboard');
    final emptyClipboard =
        user32.lookupFunction<Void Function(), void Function()>('EmptyClipboard');
    final setClipboardData = user32.lookupFunction<
        IntPtr Function(Uint32 uFormat, IntPtr hMem),
        int Function(int uFormat, int hMem)>('SetClipboardData');
    final globalAlloc = kernel32.lookupFunction<
        IntPtr Function(Uint32 uFlags, IntPtr dwBytes),
        int Function(int uFlags, int dwBytes)>('GlobalAlloc');
    final globalLock = kernel32.lookupFunction<
        IntPtr Function(IntPtr hMem),
        int Function(int hMem)>('GlobalLock');
    final globalUnlock = kernel32.lookupFunction<
        Int32 Function(IntPtr hMem),
        int Function(int hMem)>('GlobalUnlock');
    final globalFree = kernel32.lookupFunction<
        IntPtr Function(IntPtr hMem),
        int Function(int hMem)>('GlobalFree');

    const cfHdrop = 15;
    const gmMoveable = 0x0002;

    if (openClipboard(0) == 0) return;
    try {
      emptyClipboard();

      // DROPFILES struct: 20 bytes, then double-null-terminated UTF-16 path
      const structSize = 20;
      final pathUnits = filePath.codeUnits;
      final pathWideLen = pathUnits.length * 2 + 2; // +2 for null terminator
      final totalSize = structSize + pathWideLen;

      final hMem = globalAlloc(gmMoveable, totalSize);
      if (hMem == 0) return;

      final ptr = Pointer<Uint8>.fromAddress(globalLock(hMem));
      if (ptr.address == 0) {
        globalFree(hMem);
        return;
      }

      final data = ptr.asTypedList(totalSize);
      // Write DROPFILES header
      final header = ByteData.view(data.buffer, 0, structSize);
      header.setUint32(0, structSize, Endian.little); // pFiles
      header.setUint32(4, 0, Endian.little);          // pt.x
      header.setUint32(8, 0, Endian.little);          // pt.y
      header.setUint32(12, 0, Endian.little);         // fNC
      header.setUint32(16, 1, Endian.little);         // fWide (Unicode)

      // Write UTF-16LE file path
      for (int i = 0; i < pathUnits.length; i++) {
        data[structSize + i * 2] = pathUnits[i] & 0xFF;
        data[structSize + i * 2 + 1] = (pathUnits[i] >> 8) & 0xFF;
      }
      // Null terminator (2 bytes)
      data[structSize + pathUnits.length * 2] = 0;
      data[structSize + pathUnits.length * 2 + 1] = 0;

      globalUnlock(hMem);

      if (setClipboardData(cfHdrop, hMem) == 0) {
        globalFree(hMem);
      }
    } finally {
      closeClipboard();
    }
  }
}
