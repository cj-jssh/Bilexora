import 'package:flutter_test/flutter_test.dart';
import 'package:bilexora/core/storage/storage_service.dart';

void main() {
  group('formatBytes', () {
    test('bytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(500), '500 B');
    });
    test('KB', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(10 * 1024), '10.0 KB');
    });
    test('MB', () {
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(50 * 1024 * 1024), '50.0 MB');
    });
    test('GB', () {
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.00 GB');
    });
  });
}