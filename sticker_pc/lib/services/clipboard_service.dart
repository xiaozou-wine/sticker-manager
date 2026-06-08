import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart';
import 'dart:ffi';

class ClipboardService {
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
      await _imageBytesToClipboard(bytes, filePath);
    }
  }

  static Future<void> _imageBytesToClipboard(Uint8List imageBytes, String filePath) async {
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
    final registerClipboardFormat = user32.lookupFunction<
        Uint32 Function(Pointer<Utf16> lpszFormat),
        int Function(Pointer<Utf16> lpszFormat)>('RegisterClipboardFormatW');
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

    // Register PNG clipboard format
    final pngFormatName = 'PNG'.toNativeUtf16();
    final cfPng = registerClipboardFormat(pngFormatName);
    malloc.free(pngFormatName);

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

    // Build BGRA pixels (top-down, matching positive biHeight bottom-up convention)
    // With positive biHeight, DIB stores rows from bottom to top
    // So reverse row order: source row 0 (top) -> DIB row h-1 (bottom)
    final bgra = Uint8List(pixelSize);
    for (int y = 0; y < h; y++) {
      final srcRow = (h - 1 - y) * w * 4;
      final dstRow = y * w * 4;
      for (int x = 0; x < w; x++) {
        final si = srcRow + x * 4;
        final di = dstRow + x * 4;
        bgra[di] = pixels[si + 2];     // B
        bgra[di + 1] = pixels[si + 1]; // G
        bgra[di + 2] = pixels[si];     // R
        bgra[di + 3] = pixels[si + 3]; // A
      }
    }

    if (openClipboard(0) == 0) return;
    try {
      emptyClipboard();

      // 1. CF_DIB (positive biHeight = bottom-up, standard)
      {
        final hMem = globalAlloc(gmMoveable, totalSize);
        if (hMem == 0) return;
        final ptr = Pointer<Uint8>.fromAddress(globalLock(hMem));
        if (ptr.address == 0) { globalFree(hMem); return; }

        final header = ByteData.view(ptr.asTypedList(totalSize).buffer);
        header.setUint32(0, headerSize, Endian.little);
        header.setInt32(4, w, Endian.little);
        header.setInt32(8, h, Endian.little);  // positive = bottom-up (standard)
        header.setUint16(12, 1, Endian.little);
        header.setUint16(14, 32, Endian.little);
        header.setUint32(16, 0, Endian.little);
        header.setUint32(20, pixelSize, Endian.little);

        ptr.asTypedList(totalSize).setRange(headerSize, totalSize, bgra);
        globalUnlock(hMem);

        if (setClipboardData(cfDib, hMem) == 0) {
          globalFree(hMem);
        }
      }

      // 2. CF_PNG (raw PNG bytes) — for QQ and other apps
      if (cfPng != 0) {
        final pngBytes = imageBytes; // original PNG
        final hMem = globalAlloc(gmMoveable, pngBytes.length);
        if (hMem != 0) {
          final ptr = Pointer<Uint8>.fromAddress(globalLock(hMem));
          if (ptr.address != 0) {
            ptr.asTypedList(pngBytes.length).setAll(0, pngBytes);
            globalUnlock(hMem);
            if (setClipboardData(cfPng, hMem) == 0) {
              globalFree(hMem);
            }
          } else {
            globalFree(hMem);
          }
        }
      }

      // 3. Also set CF_HDROP for the file itself (fallback)
      {
        const structSize = 20;
        final pathUnits = filePath.codeUnits;
        final dropSize = structSize + pathUnits.length * 2 + 2;
        final hMem = globalAlloc(gmMoveable, dropSize);
        if (hMem != 0) {
          final ptr = Pointer<Uint8>.fromAddress(globalLock(hMem));
          if (ptr.address != 0) {
            final data = ptr.asTypedList(dropSize);
            final hdr = ByteData.view(data.buffer, 0, structSize);
            hdr.setUint32(0, structSize, Endian.little);
            hdr.setUint32(4, 0, Endian.little);
            hdr.setUint32(8, 0, Endian.little);
            hdr.setUint32(12, 0, Endian.little);
            hdr.setUint32(16, 1, Endian.little);
            for (int i = 0; i < pathUnits.length; i++) {
              data[structSize + i * 2] = pathUnits[i] & 0xFF;
              data[structSize + i * 2 + 1] = (pathUnits[i] >> 8) & 0xFF;
            }
            data[structSize + pathUnits.length * 2] = 0;
            data[structSize + pathUnits.length * 2 + 1] = 0;
            globalUnlock(hMem);
            if (setClipboardData(15 /* CF_HDROP */, hMem) == 0) {
              globalFree(hMem);
            }
          } else {
            globalFree(hMem);
          }
        }
      }
    } finally {
      closeClipboard();
    }
  }

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

      const structSize = 20;
      final pathUnits = filePath.codeUnits;
      final totalSize = structSize + pathUnits.length * 2 + 2;

      final hMem = globalAlloc(gmMoveable, totalSize);
      if (hMem == 0) return;

      final ptr = Pointer<Uint8>.fromAddress(globalLock(hMem));
      if (ptr.address == 0) {
        globalFree(hMem);
        return;
      }

      final data = ptr.asTypedList(totalSize);
      final header = ByteData.view(data.buffer, 0, structSize);
      header.setUint32(0, structSize, Endian.little);
      header.setUint32(4, 0, Endian.little);
      header.setUint32(8, 0, Endian.little);
      header.setUint32(12, 0, Endian.little);
      header.setUint32(16, 1, Endian.little);

      for (int i = 0; i < pathUnits.length; i++) {
        data[structSize + i * 2] = pathUnits[i] & 0xFF;
        data[structSize + i * 2 + 1] = (pathUnits[i] >> 8) & 0xFF;
      }
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
