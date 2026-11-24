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
  final bool translationEnabled;

  @override
  State<LyricsViewport> createState() => _LyricsViewportState();
}

class _LyricsViewportState extends State<LyricsViewport> {
  final ScrollController _scroll = ScrollController();
  int _lastActive = -1;

  @override
  void didUpdateWidget(covariant LyricsViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _activeIndex;
    if (next >= 0 && next != _lastActive) {
      _lastActive = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients || !mounted) return;
        final target = (next * 66.0 - _scroll.position.viewportDimension * .42)
            .clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.animateTo(target, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
      });
    }
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
        child: Text(
          widget.loading ? 'Searching lyrics…' : 'No matching lyrics were found.',
          style: TextStyle(color: Colors.white.withValues(alpha: .62), fontSize: 15),
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
              stops: [0, .09, .88, 1],
            ).createShader(bounds),
            child: ListView.builder(
              controller: _scroll,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 84),
              itemCount: doc.lines.length,
              itemBuilder: (context, index) {
                final line = doc.lines[index];
                final active = index == _activeIndex;
                final past = _activeIndex >= 0 && index < _activeIndex;
                final nextLine = index + 1 < doc.lines.length ? doc.lines[index + 1] : null;
                final instrumentalGap = active && nextLine != null &&
                    nextLine.timeMs - line.timeMs >= 12000 &&
                    widget.position.inMilliseconds - line.timeMs >= 6000;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: doc.synced ? () => widget.onSeek(Duration(milliseconds: line.timeMs)) : null,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: active ? 1 : past ? .42 : .48,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 240),
                      scale: active ? 1.015 : 1,
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                          line.text,
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: active ? 27 : 24,
                            height: 1.28,
                            fontWeight: FontWeight.w700,
                            shadows: active
                                ? [Shadow(color: Colors.white.withValues(alpha: .18), blurRadius: 16)]
                                : const [],
                          ),
                            ),
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
                );
              },
            ),
          ),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: _LyricsFloatingButton(
            icon: Icons.language_rounded,
            tooltip: 'Choose lyrics provider',
            onTap: widget.onChooseProvider,
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: _LyricsFloatingButton(
            icon: Icons.translate_rounded,
            tooltip: 'Toggle translation / romanization',
            selected: widget.translationEnabled,
            onTap: widget.onToggleTranslation,
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

class _LyricsFloatingButton extends StatelessWidget {
  const _LyricsFloatingButton({required this.icon, required this.tooltip, required this.onTap, this.selected = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Material(
        color: Colors.white.withValues(alpha: selected ? .20 : .09),
        shape: const CircleBorder(side: BorderSide(color: Colors.white24)),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          icon: Icon(icon, color: Colors.white, size: 21),
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
