import 'dart:ui';

import 'package:flutter/material.dart';

import 'lyrics_repository.dart';

class LyricsViewport extends StatefulWidget {
  const LyricsViewport({
    required this.document,
    required this.position,
    this.loading = false,
    required this.results,
    required this.providers,
    required this.onSeek,
    required this.onChooseProvider,
    required this.onToggleTranslation,
    required this.onRetry,
    required this.translationEnabled,
    super.key,
  });

  final LyricsDocument? document;
  final Duration position;
  final bool loading;
  final Map<String, LyricsProviderResult> results;
  final List<LyricsProvider> providers;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onChooseProvider;
  final VoidCallback onToggleTranslation;
  final VoidCallback onRetry;
  final bool translationEnabled;

  @override
  State<LyricsViewport> createState() => _LyricsViewportState();
}

class _LyricsViewportState extends State<LyricsViewport> {
  final ScrollController _scroll = ScrollController();
  int _lastActive = -1;
  bool _manualScrollActive = false;

  @override
  void didUpdateWidget(covariant LyricsViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _activeIndex;
    if (next >= 0 && next != _lastActive) {
      _lastActive = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients || !mounted) return;
        final target = (next * 66.0 - _scroll.position.viewportDimension * .42)
            .clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
        _scroll.animateTo(target, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
  }

  void _scrollToActive() {
    final index = _activeIndex;
    if (index < 0 || !_scroll.hasClients || !mounted) return;
    final target = (index * 66.0 - _scroll.position.viewportDimension * .42)
        .clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
    _scroll.jumpTo(target);
    _lastActive = index;
  }

  int get _activeIndex {
    final lines = widget.document?.lines ?? const <LyricsLine>[];
    if (widget.document?.synced != true) return -1;
    return lines.lastIndexWhere((line) => line.timeMs <= widget.position.inMilliseconds);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    if (doc == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.loading ? 'Searching lyrics…' : 'No lyrics found.',
              style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 15),
            ),
            if (!widget.loading) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
            ],
          ],
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRect(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: [0, .16, .82, 1],
              ).createShader(bounds),
              child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification &&
                    notification.dragDetails != null &&
                    !_manualScrollActive) {
                  setState(() => _manualScrollActive = true);
                } else if (notification is ScrollEndNotification &&
                    _manualScrollActive) {
                  setState(() => _manualScrollActive = false);
                }
                return false;
              },
              child: ListView.builder(
              controller: _scroll,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 42, 24, 112),
              itemCount: doc.lines.length,
              itemBuilder: (context, index) {
                final line = doc.lines[index];
                final active = index == _activeIndex;
                final nextLine = index + 1 < doc.lines.length ? doc.lines[index + 1] : null;
                final instrumentalGap = active && nextLine != null &&
                    nextLine.timeMs - line.timeMs >= 12000 &&
                    widget.position.inMilliseconds - line.timeMs >= 6000;
                final baseStyle = TextStyle(
                  color: Colors.white,
                  fontSize: active ? 31 : 27,
                  height: 1.22,
                  fontWeight: FontWeight.w700,
                );
                final lyricText = line.words.isEmpty
                    ? Text(line.text, textAlign: TextAlign.left, style: baseStyle)
                    : RichText(
                        textAlign: TextAlign.left,
                        text: TextSpan(
                          style: baseStyle,
                          children: [
                            for (final word in line.words)
                              TextSpan(
                                text: word.text,
                                style: TextStyle(
                                  color: active
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: .58),
                                ),
                              ),
                          ],
                        ),
                      );
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: doc.synced ? () => widget.onSeek(Duration(milliseconds: line.timeMs)) : null,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: active ? 1 : .34,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 240),
                      scale: active ? 1 : .96,
                      alignment: Alignment.centerLeft,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: active || _manualScrollActive ? 0 : 1.7,
                          sigmaY: active || _manualScrollActive ? 0 : 1.7,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            lyricText,
                            if (instrumentalGap)
                              const Padding(
                                padding: EdgeInsets.only(top: 10),
                                child: _InstrumentalDots(),
                              ),
                          ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
              ),
            ),
          ),
        ),
        ),
      ],
    );
  }
}

class _InstrumentalDots extends StatefulWidget {
  const _InstrumentalDots();
  @override
  State<_InstrumentalDots> createState() => _InstrumentalDotsState();
}

class _InstrumentalDotsState extends State<_InstrumentalDots> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();
  @override
  void dispose() { _pulse.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        final phase = (_pulse.value * 3 - index).clamp(0.0, 1.0).toDouble();
        return Padding(
          padding: const EdgeInsets.only(right: 5),
          child: Opacity(
            opacity: .28 + phase * .72,
            child: const Text('•', style: TextStyle(color: Colors.white70, fontSize: 19)),
          ),
        );
      }),
    ),
  );
}

class LyricsTranslationControlPill extends StatelessWidget {
  const LyricsTranslationControlPill({
    required this.translationEnabled,
    required this.onChooseProvider,
    required this.onToggleTranslation,
  });

  final bool translationEnabled;
  final VoidCallback onChooseProvider;
  final VoidCallback onToggleTranslation;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: 34,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: .16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LyricsPillAction(
                  icon: Icons.language_rounded,
                  tooltip: 'Choose lyrics provider',
                  onTap: onChooseProvider,
                ),
                Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  color: Colors.white.withValues(alpha: .18),
                ),
                _LyricsPillAction(
                  icon: Icons.translate_rounded,
                  tooltip: translationEnabled
                      ? 'Disable translation / romanization'
                      : 'Enable translation / romanization',
                  selected: translationEnabled,
                  onTap: onToggleTranslation,
                ),
              ],
            ),
          ),
        ),
      );
}

class _LyricsPillAction extends StatelessWidget {
  const _LyricsPillAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: selected
              ? Colors.white.withValues(alpha: .16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: SizedBox(
              width: 28,
              height: 28,
              child: Icon(
                icon,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
      );
}

Future<String?> showLyricsProviderSheet(
  BuildContext context, {
  required List<LyricsProvider> providers,
  required Map<String, LyricsProviderResult> results,
  required String? activeProvider,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * .72),
            decoration: BoxDecoration(
              color: const Color(0xFF17181D).withValues(alpha: .91),
              border: Border.all(color: Colors.white.withValues(alpha: .10)),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(4))),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Choose lyrics provider', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                    children: [
                      for (final provider in providers)
                        _ProviderTile(
                          provider: provider,
                          result: results[provider.id],
                          active: activeProvider == provider.id,
                          onTap: results[provider.id]?.status == LyricsLookupStatus.found
                              ? () => Navigator.pop(sheetContext, provider.id)
                              : null,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({required this.provider, required this.result, required this.active, required this.onTap});
  final LyricsProvider provider;
  final LyricsProviderResult? result;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status = result?.status ?? LyricsLookupStatus.loading;
    final found = status == LyricsLookupStatus.found;
    final loading = status == LyricsLookupStatus.loading;
    final label = active
        ? 'Current provider'
        : found
            ? 'Lyrics found · Tap to use'
            : loading
                ? 'Searching…'
                : status == LyricsLookupStatus.error
                    ? 'Provider unavailable'
                    : 'Lyrics not found';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          enabled: onTap != null,
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: active ? Colors.white24 : Colors.white10)),
          leading: CircleAvatar(
            radius: 17,
            backgroundColor: Colors.white.withValues(alpha: .08),
            child: loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                : Icon(found ? Icons.check_rounded : Icons.close_rounded, size: 18, color: found ? Colors.white : Colors.white38),
          ),
          title: Text(provider.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          subtitle: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          trailing: active ? const Icon(Icons.radio_button_checked_rounded, color: Colors.white) : null,
        ),
      ),
    );
  }
}
