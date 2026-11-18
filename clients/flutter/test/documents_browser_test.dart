import 'package:flutter_test/flutter_test.dart';
import 'package:pocketlink_client/features/files/documents_browser_screen.dart';

void main() {
  group('canonicalDocumentPath', () {
    test('normalizes separators and redundant path segments', () {
      expect(
        canonicalDocumentPath(r'folder\.\reports\..\notes\pocketlink-test.txt'),
        'folder/notes/pocketlink-test.txt',
      );
    });

    test('normalizes dot segments and leading separators', () {
      expect(
        canonicalDocumentPath('/./Documents//pocketlink-test.txt'),
        'Documents/pocketlink-test.txt',
      );
    });

    test('keeps identical relative paths stable', () {
      expect(
        canonicalDocumentPath('Documents/pocketlink-test.txt'),
        canonicalDocumentPath('Documents/pocketlink-test.txt'),
      );
    });
  });
}
