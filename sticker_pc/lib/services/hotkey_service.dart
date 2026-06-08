import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'settings_service.dart';

// ── Key maps (forward + reverse) ──────────────────────────────────────────────

const _labelToKey = <String, PhysicalKeyboardKey>{
  // Letters A-Z
  'keya': PhysicalKeyboardKey.keyA,
  'keyb': PhysicalKeyboardKey.keyB,
  'keyc': PhysicalKeyboardKey.keyC,
  'keyd': PhysicalKeyboardKey.keyD,
  'keye': PhysicalKeyboardKey.keyE,
  'keyf': PhysicalKeyboardKey.keyF,
  'keyg': PhysicalKeyboardKey.keyG,
  'keyh': PhysicalKeyboardKey.keyH,
  'keyi': PhysicalKeyboardKey.keyI,
  'keyj': PhysicalKeyboardKey.keyJ,
  'keyk': PhysicalKeyboardKey.keyK,
  'keyl': PhysicalKeyboardKey.keyL,
  'keym': PhysicalKeyboardKey.keyM,
  'keyn': PhysicalKeyboardKey.keyN,
  'keyo': PhysicalKeyboardKey.keyO,
  'keyp': PhysicalKeyboardKey.keyP,
  'keyq': PhysicalKeyboardKey.keyQ,
  'keyr': PhysicalKeyboardKey.keyR,
  'keys': PhysicalKeyboardKey.keyS,
  'keyt': PhysicalKeyboardKey.keyT,
  'keyu': PhysicalKeyboardKey.keyU,
  'keyv': PhysicalKeyboardKey.keyV,
  'keyw': PhysicalKeyboardKey.keyW,
  'keyx': PhysicalKeyboardKey.keyX,
  'keyy': PhysicalKeyboardKey.keyY,
  'keyz': PhysicalKeyboardKey.keyZ,
  // Digits 0-9
  'digit0': PhysicalKeyboardKey.digit0,
  'digit1': PhysicalKeyboardKey.digit1,
  'digit2': PhysicalKeyboardKey.digit2,
  'digit3': PhysicalKeyboardKey.digit3,
  'digit4': PhysicalKeyboardKey.digit4,
  'digit5': PhysicalKeyboardKey.digit5,
  'digit6': PhysicalKeyboardKey.digit6,
  'digit7': PhysicalKeyboardKey.digit7,
  'digit8': PhysicalKeyboardKey.digit8,
  'digit9': PhysicalKeyboardKey.digit9,
  // Function keys
  'f1': PhysicalKeyboardKey.f1,
  'f2': PhysicalKeyboardKey.f2,
  'f3': PhysicalKeyboardKey.f3,
  'f4': PhysicalKeyboardKey.f4,
  'f5': PhysicalKeyboardKey.f5,
  'f6': PhysicalKeyboardKey.f6,
  'f7': PhysicalKeyboardKey.f7,
  'f8': PhysicalKeyboardKey.f8,
  'f9': PhysicalKeyboardKey.f9,
  'f10': PhysicalKeyboardKey.f10,
  'f11': PhysicalKeyboardKey.f11,
  'f12': PhysicalKeyboardKey.f12,
  // Special keys
  'space': PhysicalKeyboardKey.space,
  'tab': PhysicalKeyboardKey.tab,
  'backspace': PhysicalKeyboardKey.backspace,
  'escape': PhysicalKeyboardKey.escape,
};

/// Reverse map: PhysicalKeyboardKey -> config label (e.g. "keyS").
final Map<PhysicalKeyboardKey, String> _keyToLabel = {
  for (final e in _labelToKey.entries) e.value: e.key,
};

/// Modifier keys we recognize as hotkey modifiers.
const _modifierKeys = <PhysicalKeyboardKey>[
  PhysicalKeyboardKey.controlLeft,
  PhysicalKeyboardKey.controlRight,
  PhysicalKeyboardKey.shiftLeft,
  PhysicalKeyboardKey.shiftRight,
  PhysicalKeyboardKey.altLeft,
  PhysicalKeyboardKey.altRight,
];

/// Convert a modifier key to its config label.
String? _modifierKeyToLabel(PhysicalKeyboardKey key) {
  if (key == PhysicalKeyboardKey.controlLeft ||
      key == PhysicalKeyboardKey.controlRight) {
    return 'ctrl';
  }
  if (key == PhysicalKeyboardKey.shiftLeft ||
      key == PhysicalKeyboardKey.shiftRight) {
    return 'shift';
  }
  if (key == PhysicalKeyboardKey.altLeft ||
      key == PhysicalKeyboardKey.altRight) {
    return 'alt';
  }
  return null;
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Register a system-wide hotkey from the given config.
/// Unregisters all previously registered hotkeys first.
Future<HotKey> registerHotkey(HotkeyConfig config) async {
  await hotKeyManager.unregisterAll();

  final key = resolvePhysicalKey(config.keyLabel);
  if (key == null) {
    throw Exception('Unknown key: ${config.keyLabel}');
  }

  final modifiers = config.modifiers.map((m) {
    switch (m) {
      case 'ctrl':
        return HotKeyModifier.control;
      case 'shift':
        return HotKeyModifier.shift;
      case 'alt':
        return HotKeyModifier.alt;
      default:
        return HotKeyModifier.control;
    }
  }).toList();

  final hotKey = HotKey(
    key: key,
    modifiers: modifiers,
    scope: HotKeyScope.system,
  );

  await hotKeyManager.register(
    hotKey,
    keyDownHandler: (hotKey) async {
      if (await windowManager.isVisible()) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    },
  );

  return hotKey;
}

/// Resolve a config keyLabel (e.g. "keyS") to a [PhysicalKeyboardKey].
PhysicalKeyboardKey? resolvePhysicalKey(String label) {
  return _labelToKey[label.toLowerCase()];
}

/// Convert a [PhysicalKeyboardKey] to a config keyLabel (e.g. "keyS").
/// Returns null for modifier keys and unknown keys.
String? physicalKeyToConfigLabel(PhysicalKeyboardKey key) {
  // Modifier keys are not valid standalone hotkey keys.
  if (_modifierKeys.contains(key)) return null;
  final lower = _keyToLabel[key];
  if (lower == null) return null;
  // Config format: capitalize the letter/digit portion.
  // "keys" -> "keyS", "digit1" -> "digit1", "f1" -> "f1"
  if (lower.startsWith('key') && lower.length == 4) {
    return 'key${lower[3].toUpperCase()}';
  }
  return lower;
}

/// Returns true if the key is a modifier (Ctrl/Shift/Alt).
bool isModifierKey(PhysicalKeyboardKey key) {
  return _modifierKeys.contains(key);
}

/// Convert a modifier [PhysicalKeyboardKey] to its config label.
String? modifierKeyToConfigLabel(PhysicalKeyboardKey key) {
  return _modifierKeyToLabel(key);
}
