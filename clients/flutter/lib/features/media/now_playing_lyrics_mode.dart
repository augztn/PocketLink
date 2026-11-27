import 'package:material_ui/material_ui.dart';

class NowPlayingLyricsMode extends StatelessWidget {
  const NowPlayingLyricsMode({
    required this.progress,
    required this.artwork,
    required this.trackTitle,
    required this.artistLabel,
    required this.actions,
    required this.onClose,
    required this.lyricsContent,
    required this.providerLabel,
    required this.onChooseProvider,
    required this.footer,
    super.key,
  });

  final double progress;
  final Widget artwork;
  final String trackTitle;
  final String artistLabel;
  final Widget actions;
  final VoidCallback onClose;
  final Widget lyricsContent;
  final String providerLabel;
  final VoidCallback onChooseProvider;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: progress < 0.02,
      child: SafeArea(
        child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final startRect = Rect.fromLTWH(0, 0, width, height * 0.46);
              const compactArtRect = Rect.fromLTWH(12, 3, 48, 48);
              final artRect = Rect.lerp(startRect, compactArtRect, progress)!;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0x9E000000)),
                  ),
                  Positioned.fromRect(
                    rect: artRect,
                    child: GestureDetector(
                      onTap: onClose,
                      child: artwork,
                    ),
                  ),
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 68, right: 12),
                        child: SizedBox(
                          height: 54,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      trackTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      artistLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              actions,
                            ],
                          ),
                        ),
                      ),
                      Expanded(child: lyricsContent),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onChooseProvider,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            providerLabel,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.white54,
                            ),
                          ),
                        ),
                      ),
                      footer,
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
