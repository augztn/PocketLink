import 'package:flutter_test/flutter_test.dart';
import 'package:homeserver_client/features/files/documents_browser_screen.dart';

void main() {
  group('canonicalDocumentPath', () {
    test('normalizes separators and redundant path segments', () {
      expect(
        canonicalDocumentPath(r'folder\.\reports\..\notes\homeserver-test.txt'),
        'folder/notes/homeserver-test.txt',
      );
    });

    test('normalizes dot segments and leading separators', () {
      expect(
        canonicalDocumentPath('/./Documents//homeserver-test.txt'),
        'Documents/homeserver-test.txt',
      );
    });

    test('keeps identical relative paths stable', () {
      expect(
        canonicalDocumentPath('Documents/homeserver-test.txt'),
        canonicalDocumentPath('Documents/homeserver-test.txt'),
      );
    });
  });
}
