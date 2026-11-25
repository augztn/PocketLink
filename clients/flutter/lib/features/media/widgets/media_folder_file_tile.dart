import 'package:flutter/material.dart';

class MediaFolderFileTile extends StatelessWidget {
  const MediaFolderFileTile({
    required this.title,
    required this.subtitle,
    required this.isMusic,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool isMusic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          isMusic ? Icons.audio_file_outlined : Icons.movie_outlined,
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.play_arrow_rounded),
        onTap: onTap,
      ),
    );
  }
}
