import 'package:appnukba/services/arabic_reshaper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArabicReshaper', () {
    test('uses isolated and connected Lam-Alef ligatures', () {
      expect(ArabicReshaper.reshape('لا'), '\uFEFB');
      expect(ArabicReshaper.reshape('بلا'), '\uFE91\uFEFC');
      expect(ArabicReshaper.reshape('لأ لإ لآ'), '\uFEF7 \uFEF9 \uFEF5');
    });

    test('keeps diacritics without breaking neighbouring connections', () {
      expect(ArabicReshaper.reshape('بَت'), '\uFE91َ\uFE96');
    });

    test('does not connect letters across spaces or digits', () {
      expect(ArabicReshaper.reshape('ب ت'), '\uFE8F \uFE95');
      expect(ArabicReshaper.reshape('ب1ت'), '\uFE8F1\uFE95');
    });
  });
}
