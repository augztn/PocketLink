import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/core/widgets/pocketlink_file_icon.dart';

void main() {
  const light = ColorScheme.light(
    primary: Color(0xFF4760FA),
    onSurfaceVariant: Color(0xFF525A74),
  );
  const dark = ColorScheme.dark(
    primary: Color(0xFF8C9EFF),
    onSurfaceVariant: Color(0xFFA0A7BA),
  );

  group('PocketLinkFileVisuals', () {
    test('uses the theme primary for directories', () {
      final visual = PocketLinkFileVisuals.resolve(
        name: 'Documents',
        isDirectory: true,
        colors: light,
      );

      expect(visual.icon, Icons.folder_rounded);
      expect(visual.color, light.primary);
    });

    test('maps media, documents and archives to semantic icons', () {
      final cases = <(String, IconData)>[
        ('photo.JPG', Icons.image_outlined),
        ('movie.mp4', Icons.video_file_outlined),
        ('track.FLAC', Icons.audio_file_rounded),
        ('report.pdf', Icons.picture_as_pdf_rounded),
        ('notes.docx', Icons.description_outlined),
        ('backup.zip', Icons.archive_rounded),
      ];

      for (final (name, expectedIcon) in cases) {
        final visual = PocketLinkFileVisuals.resolve(
          name: name,
          isDirectory: false,
          colors: dark,
        );
        expect(visual.icon, expectedIcon, reason: name);
      }
    });

    test('uses accessible theme-specific accent colors', () {
      final lightImage = PocketLinkFileVisuals.resolve(
        name: 'photo.jpg',
        isDirectory: false,
        colors: light,
      );
      final darkImage = PocketLinkFileVisuals.resolve(
        name: 'photo.jpg',
        isDirectory: false,
        colors: dark,
      );

      expect(lightImage.color, const Color(0xFFD97706));
      expect(darkImage.color, const Color(0xFFF4B544));
    });

    test('uses the theme variant color for unknown files', () {
      final visual = PocketLinkFileVisuals.resolve(
        name: 'README',
        isDirectory: false,
        colors: light,
      );

      expect(visual.icon, Icons.insert_drive_file_outlined);
      expect(visual.color, light.onSurfaceVariant);
    });
  });
}
