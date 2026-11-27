import 'package:material_ui/material_ui.dart';

class NowPlayingLyricsMode extends StatelessWidget {
  const NowPlayingLyricsMode({
    required this.progress,
    required this.background,
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
  final Widget background;
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
      child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final startRect = Rect.fromLTWH(0, 0, width, height * 0.46);
              final compactArtRect = Rect.fromLTWH(12, MediaQuery.paddingOf(context).top + 3, 48, 48);
              final artRect = Rect.lerp(startRect, compactArtRect, progress)!;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: background),
                  Positioned.fromRect(
                    rect: artRect,
                    child: GestureDetector(
                      onTap: onClose,
                      child: artwork,
                    ),
                  ),
                  Positioned(
                    top: MediaQuery.paddingOf(context).top,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onClose,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 5),
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 8),
                    child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 68, right: 12, top: 8),
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
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        const style = TextStyle(
                                          color: Colors.white60,
                                          fontSize: 12,
                                        );
                                        final painter = TextPainter(
                                          text: TextSpan(text: artistLabel, style: style),
                                          maxLines: 1,
                                          textDirection: Directionality.of(context),
                                        )..layout(maxWidth: constraints.maxWidth);
                                        final text = Text(
                                          artistLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: style,
                                        );
                                        if (!painter.didExceedMaxLines &&
                                            painter.width <= constraints.maxWidth) {
                                          return text;
                                        }
                                        return ShaderMask(
                                          blendMode: BlendMode.dstIn,
                                          shaderCallback: (bounds) => const LinearGradient(
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                            colors: [Colors.white, Colors.white, Colors.transparent],
                                            stops: [0, .78, 1],
                                          ).createShader(bounds),
                                          child: text,
                                        );
                                      },
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
                      if (providerLabel.isNotEmpty)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onChooseProvider,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
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
                        ),
                      footer,
                    ],
                    ),
                  ),
                ],
              );
            },
          ),
    );
  }
}
