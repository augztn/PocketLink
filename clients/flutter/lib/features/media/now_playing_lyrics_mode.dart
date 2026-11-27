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
    required this.translationControl,
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
  final Widget translationControl;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: progress < 0.02,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final topInset = MediaQuery.paddingOf(context).top;
          const headerTopSpacing = 8.0;
          const handleHeight = 4.5;
          const handleToHeaderGap = 12.0;
          final compactArtRect = Rect.fromLTWH(
            24,
            topInset + headerTopSpacing + handleHeight + handleToHeaderGap,
            48,
            48,
          );
          final startRect = Rect.fromLTWH(0, 0, width, height * 0.56);
          final artRect = Rect.lerp(startRect, compactArtRect, progress)!;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: background),
              Positioned.fromRect(
                rect: artRect,
                child: GestureDetector(
                  key: const ValueKey('lyrics-mode-artwork'),
                  onTap: onClose,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: artwork,
                  ),
                ),
              ),
              Positioned(
                top: topInset + headerTopSpacing,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onClose,
                      child: Container(
                        key: const ValueKey('lyrics-mode-grab-handle'),
                        width: 40,
                        height: handleHeight,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: handleToHeaderGap),
                    Padding(
                      key: const ValueKey('lyrics-mode-compact-header'),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: SizedBox(
                        height: 48,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(width: 48),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    trackTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    artistLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
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
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: topInset + headerTopSpacing + handleHeight +
                    handleToHeaderGap + 48 + 12,
                bottom: 0,
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRect(child: lyricsContent),
                    ),
                    if (providerLabel.isNotEmpty || translationControl is! SizedBox)
                      Padding(
                        key: const ValueKey('lyrics-mode-attribution-footer'),
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: providerLabel.isEmpty
                                  ? const SizedBox.shrink()
                                  : GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: onChooseProvider,
                                      child: Text(
                                        providerLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.72),
                                          fontSize: 13,
                                          decoration: TextDecoration.underline,
                                          decorationColor: Colors.white.withValues(alpha: 0.54),
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            translationControl,
                          ],
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
