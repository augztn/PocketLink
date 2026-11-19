import 'package:material_ui/material_ui.dart';

class PocketLinkFileVisual {
  const PocketLinkFileVisual({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}

class PocketLinkFileVisuals {
  static const _images = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp', 'avif',
  };
  static const _videos = {
    'mp4', 'mkv', 'mov', 'avi', 'webm', 'm4v', '3gp', 'wmv', 'mpeg', 'mpg',
  };
  static const _audio = {
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'wma', 'aiff', 'alac',
  };
  static const _documents = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'odt',
    'ods', 'csv', 'md',
  };
  static const _archives = {'zip', '7z', 'rar', 'tar', 'gz', 'bz2'};

  static PocketLinkFileVisual resolve({
    required String name,
    required bool isDirectory,
    required ColorScheme colors,
  }) {
    if (isDirectory) {
      return PocketLinkFileVisual(icon: Icons.folder_rounded, color: colors.primary);
    }

    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    final isDark = colors.brightness == Brightness.dark;
    if (_images.contains(extension)) {
      return PocketLinkFileVisual(icon: Icons.image_outlined,
        color: isDark ? const Color(0xFFF4B544) : const Color(0xFFD97706));
    }
    if (_videos.contains(extension)) {
      return PocketLinkFileVisual(icon: Icons.video_file_outlined,
        color: isDark ? const Color(0xFF2BBEAE) : const Color(0xFF0D9488));
    }
    if (_audio.contains(extension)) {
      return PocketLinkFileVisual(icon: Icons.audio_file_rounded,
        color: isDark ? const Color(0xFF9A83F5) : const Color(0xFF6D4AFF));
    }
    if (extension == 'pdf') {
      return PocketLinkFileVisual(icon: Icons.picture_as_pdf_rounded,
        color: isDark ? const Color(0xFFF16B6B) : const Color(0xFFDC2626));
    }
    if (_documents.contains(extension)) {
      return PocketLinkFileVisual(icon: Icons.description_outlined,
        color: isDark ? const Color(0xFF64A5F5) : const Color(0xFF2563EB));
    }
    if (_archives.contains(extension)) {
      return PocketLinkFileVisual(icon: Icons.archive_rounded,
        color: isDark ? const Color(0xFFF09A48) : const Color(0xFFB45309));
    }
    return PocketLinkFileVisual(icon: Icons.insert_drive_file_outlined,
      color: colors.onSurfaceVariant);
  }
}

class PocketLinkFileIcon extends StatelessWidget {
  const PocketLinkFileIcon({
    required this.name,
    this.isDirectory = false,
    this.size = 44,
    super.key,
  });

  final String name;
  final bool isDirectory;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visual = PocketLinkFileVisuals.resolve(
      name: name,
      isDirectory: isDirectory,
      colors: colors,
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Icon(visual.icon, color: visual.color, size: size * 0.52),
    );
  }
}
