class ArabicReshaper {
  static const Map<String, List<String>> _arabicMap = {
    // Normal Arabic letters: [Isolated, End/Final, Middle/Medial, Beginning/Initial]
    'ا': ['\uFE8D', '\uFE8E', '\uFE8E', '\uFE8D'],
    'أ': ['\uFE83', '\uFE84', '\uFE84', '\uFE83'],
    'إ': ['\uFE87', '\uFE88', '\uFE88', '\uFE87'],
    'آ': ['\uFE81', '\uFE82', '\uFE82', '\uFE81'],
    'ب': ['\uFE8F', '\uFE90', '\uFE92', '\uFE91'],
    'ت': ['\uFE95', '\uFE96', '\uFE98', '\uFE97'],
    'ث': ['\uFE99', '\uFE9A', '\uFE9C', '\uFE9B'],
    'ج': ['\uFE9D', '\uFE9E', '\uFEA0', '\uFE9F'],
    'ح': ['\uFEA1', '\uFEA2', '\uFEA4', '\uFEA3'],
    'خ': ['\uFEA5', '\uFEA6', '\uFEA8', '\uFEA7'],
    'د': ['\uFEA9', '\uFEAA', '\uFEAA', '\uFEA9'],
    'ذ': ['\uFEAB', '\uFEAC', '\uFEAC', '\uFEAB'],
    'ر': ['\uFEAD', '\uFEAE', '\uFEAE', '\uFEAD'],
    'ز': ['\uFEAF', '\uFEB0', '\uFEB0', '\uFEAF'],
    'س': ['\uFEB1', '\uFEB2', '\uFEB4', '\uFEB3'],
    'ش': ['\uFEB5', '\uFEB6', '\uFEB8', '\uFEB7'],
    'ص': ['\uFEB9', '\uFEBA', '\uFEBC', '\uFEBB'],
    'ض': ['\uFEBD', '\uFEBE', '\uFEC0', '\uFEBF'],
    'ط': ['\uFEC1', '\uFEC2', '\uFEC4', '\uFEC3'],
    'ظ': ['\uFEC5', '\uFEC6', '\uFEC8', '\uFEC7'],
    'ع': ['\uFEC9', '\uFECA', '\uFECC', '\uFECB'],
    'غ': ['\uFECD', '\uFECE', '\uFED0', '\uFECF'],
    'ف': ['\uFED1', '\uFED2', '\uFED4', '\uFED3'],
    'ق': ['\uFED5', '\uFED6', '\uFED8', '\uFED7'],
    'ك': ['\uFED9', '\uFEDA', '\uFEDC', '\uFEDB'],
    'ل': ['\uFEDD', '\uFEDE', '\uFEE0', '\uFEDF'],
    'م': ['\uFEE1', '\uFEE2', '\uFEE4', '\uFEE3'],
    'ن': ['\uFEE5', '\uFEE6', '\uFEE8', '\uFEE7'],
    'ه': ['\uFEE9', '\uFEEA', '\uFEEC', '\uFEEB'],
    'و': ['\uFEED', '\uFEEE', '\uFEEE', '\uFEED'],
    'ي': ['\uFEF1', '\uFEF2', '\uFEF4', '\uFEF3'],
    'ى': ['\uFEEF', '\uFEF0', '\uFEF0', '\uFEEF'],
    'ة': ['\uFE93', '\uFE94', '\uFE93', '\uFE93'],
    'ؤ': ['\uFE85', '\uFE86', '\uFE86', '\uFE85'],
    'ئ': ['\uFE89', '\uFE8A', '\uFE8C', '\uFE8B'],
    'ء': ['\uFE80', '\uFE80', '\uFE80', '\uFE80'],
  };

  // [isolated, final]. A Lam-Alef ligature can connect only to the letter
  // before it, never to the following letter.
  static const Map<String, List<String>> _lamAlefLigatures = {
    'لآ': ['\uFEF5', '\uFEF6'],
    'لأ': ['\uFEF7', '\uFEF8'],
    'لإ': ['\uFEF9', '\uFEFA'],
    'لا': ['\uFEFB', '\uFEFC'],
  };

  // Characters that cannot connect to the next character (left side)
  static const Set<String> _nonLeftConnecting = {
    'ا',
    'أ',
    'إ',
    'آ',
    'د',
    'ذ',
    'ر',
    'ز',
    'و',
    'ؤ',
    'ة',
    'ء',
    'ى',
  };

  static bool _isArabic(String char) {
    if (char.isEmpty) return false;
    final code = char.codeUnitAt(0);
    return (code >= 0x0600 && code <= 0x06FF) || (code >= 0x0750 && code <= 0x077F);
  }

  static bool _canConnectLeft(String char) {
    if (!_arabicMap.containsKey(char)) return false;
    return !_nonLeftConnecting.contains(char);
  }

  static bool _canConnectRight(String char) {
    return _arabicMap.containsKey(char) && char != 'ء';
  }

  static bool _isTransparentMark(String char) {
    if (char.isEmpty) return false;
    final code = char.codeUnitAt(0);
    return (code >= 0x0610 && code <= 0x061A) ||
        (code >= 0x064B && code <= 0x065F) ||
        code == 0x0670 ||
        (code >= 0x06D6 && code <= 0x06ED);
  }

  static int? _previousLetterIndex(List<String> chars, int index) {
    for (int i = index - 1; i >= 0; i--) {
      if (_isTransparentMark(chars[i])) continue;
      return _arabicMap.containsKey(chars[i]) ? i : null;
    }
    return null;
  }

  static int? _nextLetterIndex(List<String> chars, int index) {
    for (int i = index + 1; i < chars.length; i++) {
      if (_isTransparentMark(chars[i])) continue;
      return _arabicMap.containsKey(chars[i]) ? i : null;
    }
    return null;
  }

  /// Shapes Arabic text so that characters connect correctly and handles RTL display in PDF
  static String reshape(String text) {
    if (text.isEmpty) return text;

    final List<String> chars = text.split('');
    final List<String> reshaped = List.filled(chars.length, '');
    final List<bool> consumed = List.filled(chars.length, false);

    for (int i = 0; i < chars.length; i++) {
      if (consumed[i]) continue;
      final current = chars[i];

      if (_isTransparentMark(current) || !_isArabic(current)) {
        reshaped[i] = current;
        continue;
      }

      final previousIndex = _previousLetterIndex(chars, i);
      final nextIndex = _nextLetterIndex(chars, i);
      final hasRight =
          previousIndex != null &&
          _canConnectLeft(chars[previousIndex]) &&
          _canConnectRight(current);

      if (current == 'ل' && nextIndex != null) {
        final ligatureForms = _lamAlefLigatures['$current${chars[nextIndex]}'];
        if (ligatureForms != null) {
          reshaped[i] = ligatureForms[hasRight ? 1 : 0];
          consumed[nextIndex] = true;
          continue;
        }
      }

      final hasLeft =
          nextIndex != null && _canConnectRight(chars[nextIndex]) && _canConnectLeft(current);

      final forms = _arabicMap[current];
      if (forms == null) {
        reshaped[i] = current;
        continue;
      }

      if (hasRight && hasLeft) {
        reshaped[i] = forms[2]; // Medial
      } else if (hasRight) {
        reshaped[i] = forms[1]; // Final
      } else if (hasLeft) {
        reshaped[i] = forms[3]; // Initial
      } else {
        reshaped[i] = forms[0]; // Isolated
      }
    }

    return reshaped.join('');
  }
}
