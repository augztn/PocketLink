import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/pocketlink_scaffold.dart';

const Color settingsGroupColor = Color(0xFF1C1C1E);
const Color settingsDividerColor = Color(0x0FFFFFFF);

/// Shared uppercase section label used by every Settings category.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
            letterSpacing: 0,
          ),
        ),
      );
}

/// One Settings surface with consistent shape, fill and row separators.
class SettingsGroupCard extends StatefulWidget {
  const SettingsGroupCard({
    required this.children,
    super.key,
    this.padding = EdgeInsets.zero,
    this.searchQuery = '',
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final String searchQuery;

  @override
  State<SettingsGroupCard> createState() => _SettingsGroupCardState();
}

class _SettingsGroupCardState extends State<SettingsGroupCard> {
  final Map<int, GlobalKey> _rowKeys = {};
  int? _activeHighlightIndex;
  Timer? _highlightTimer;

  String _rowIdentity(int index, Widget child) =>
      '$index:${child.runtimeType}:${settingsSearchableText(child)}';

  GlobalKey _keyFor(int index, Widget child) =>
      _rowKeys.putIfAbsent(index, GlobalKey.new);

  bool _matches(Widget child) {
    final tokens = widget.searchQuery
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.isNotEmpty);
    if (tokens.isEmpty) return false;
    final corpus = settingsSearchableText(child).toLowerCase();
    return tokens.every(corpus.contains);
  }

  void _scrollToFirstMatch() {
    final query = widget.searchQuery.trim();
    if (query.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || widget.searchQuery.trim() != query) return;
      var matchIndex = -1;
      for (var index = 0; index < widget.children.length; index++) {
        if (_matches(widget.children[index])) {
          matchIndex = index;
          break;
        }
      }
      if (matchIndex < 0) return;

      // Match Mochy's page transition settling delay before revealing the selected row.
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (!mounted || widget.searchQuery.trim() != query) return;
      setState(() => _activeHighlightIndex = matchIndex);

      final target = _keyFor(matchIndex, widget.children[matchIndex]).currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          alignment: 0.18,
        );
      }

      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(milliseconds: 2400), () {
        if (mounted && _activeHighlightIndex == matchIndex) {
          setState(() => _activeHighlightIndex = null);
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _scrollToFirstMatch();
  }

  @override
  void didUpdateWidget(covariant SettingsGroupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _highlightTimer?.cancel();
      _activeHighlightIndex = null;
      _scrollToFirstMatch();
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  List<Widget> _animatedChildren(BuildContext context) => [
        for (var index = 0; index < widget.children.length; index++)
          AnimatedContainer(
            key: _keyFor(index, widget.children[index]),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: _activeHighlightIndex == index && _matches(widget.children[index])
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.13)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: _activeHighlightIndex == index && _matches(widget.children[index])
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.24),
                    )
                  : null,
            ),
            child: TweenAnimationBuilder<double>(
            key: ValueKey('settings-row-${_rowIdentity(index, widget.children[index])}'),
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              final progress = MediaQuery.of(context).disableAnimations ? 1.0 : value;
              return Opacity(
                opacity: progress,
                child: Transform.translate(
                  offset: Offset(0, 6 * (1 - progress)),
                  child: child,
                ),
              );
            },
            child: widget.children[index],
          ),
          ),
      ];

  @override
  Widget build(BuildContext context) => ListTileTheme(
        data: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 20),
          horizontalTitleGap: 16,
          minLeadingWidth: 32,
          minVerticalPadding: 14,
          titleTextStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          subtitleTextStyle: TextStyle(
            fontSize: 12,
            color: Color(0xFF9A9BA3),
          ),
        ),
        child: DividerTheme(
          data: const DividerThemeData(
            color: settingsDividerColor,
            thickness: 1,
            space: 1,
          ),
          child: Material(
            color: settingsGroupColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            clipBehavior: Clip.antiAlias,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Padding(
                  padding: widget.padding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _animatedChildren(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// A parent setting with visually nested dependent controls, matching Mochy's inset clusters.
class SettingsNestedGroup extends StatefulWidget {
  const SettingsNestedGroup({
    required this.parent,
    required this.children,
    this.expanded = true,
    this.searchQuery = '',
    super.key,
  });

  final Widget parent;
  final List<Widget> children;
  final bool expanded;
  final String searchQuery;

  @override
  State<SettingsNestedGroup> createState() => _SettingsNestedGroupState();
}

class _SettingsNestedGroupState extends State<SettingsNestedGroup> {
  final Map<String, GlobalKey> _rowKeys = {};
  Timer? _highlightTimer;
  int? _activeIndex;

  bool _matches(Widget child) {
    final tokens = widget.searchQuery
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.isNotEmpty);
    if (tokens.isEmpty) return false;
    final text = settingsSearchableText(child).toLowerCase();
    return tokens.every(text.contains);
  }

  GlobalKey _keyFor(int index, Widget child) {
    return _rowKeys.putIfAbsent(index, GlobalKey.new);
  }

  void _revealMatch() {
    final query = widget.searchQuery.trim();
    if (query.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || widget.searchQuery.trim() != query || !widget.expanded) return;
      var index = -1;
      for (var i = 0; i < widget.children.length; i++) {
        if (_matches(widget.children[i])) {
          index = i;
          break;
        }
      }
      if (index < 0) return;
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (!mounted || widget.searchQuery.trim() != query) return;
      setState(() => _activeIndex = index);
      final target = _keyFor(index, widget.children[index]).currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          alignment: 0.18,
        );
      }
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(milliseconds: 2400), () {
        if (mounted && _activeIndex == index) setState(() => _activeIndex = null);
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _revealMatch();
  }

  @override
  void didUpdateWidget(covariant SettingsNestedGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery ||
        oldWidget.expanded != widget.expanded) {
      _highlightTimer?.cancel();
      _activeIndex = null;
      _revealMatch();
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.parent,
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: widget.expanded
                ? Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF282830),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var index = 0; index < widget.children.length; index++)
                          AnimatedContainer(
                            key: _keyFor(index, widget.children[index]),
                            duration: const Duration(milliseconds: 450),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _activeIndex == index && _matches(widget.children[index])
                                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.13)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: TweenAnimationBuilder<double>(
                              key: ValueKey('nested-settings-row-${settingsSearchableText(widget.children[index])}-$index'),
                              tween: Tween<double>(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) {
                                final progress = MediaQuery.of(context).disableAnimations ? 1.0 : value;
                                return Opacity(
                                  opacity: progress,
                                  child: Transform.translate(
                                    offset: Offset(0, 6 * (1 - progress)),
                                    child: child,
                                  ),
                                );
                              },
                              child: widget.children[index],
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      );
}

/// Mochy-style monochrome icon well used by setting rows.
class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: Color(0xFFE5E5EA),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: const Color(0xFF1C1C1E), size: 16),
      );
}

/// Standard row for Settings content that does not need a specialised control.
String settingsSearchableText(Widget widget) {
  if (widget is SettingsNestedGroup) {
    return '${settingsSearchableText(widget.parent)} '
        '${widget.children.map(settingsSearchableText).join(' ')}';
  }
  if (widget is SettingsTile) return '${widget.title} ${widget.subtitle ?? ''}';
  if (widget is Text) return widget.data ?? '';
  if (widget is ListTile) {
    return '${settingsSearchableText(widget.title ?? const SizedBox.shrink())} '
        '${settingsSearchableText(widget.subtitle ?? const SizedBox.shrink())}';
  }
  if (widget is SwitchListTile) {
    return '${settingsSearchableText(widget.title ?? const SizedBox.shrink())} '
        '${settingsSearchableText(widget.subtitle ?? const SizedBox.shrink())}';
  }
  if (widget is Padding && widget.child != null) return settingsSearchableText(widget.child!);
  if (widget is Container && widget.child != null) return settingsSearchableText(widget.child!);
  if (widget is SizedBox && widget.child != null) return settingsSearchableText(widget.child!);
  if (widget is Align && widget.child != null) return settingsSearchableText(widget.child!);
  if (widget is Column) return widget.children.map(settingsSearchableText).join(' ');
  if (widget is Row) return widget.children.map(settingsSearchableText).join(' ');
  return '';
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    required this.title,
    super.key,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: contentPadding,
        enabled: enabled,
        leading: leading is Icon
            ? Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFE5E5EA),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: IconTheme(
                  data: const IconThemeData(
                    color: Color(0xFF1C1C1E),
                    size: 16,
                  ),
                  child: leading!,
                ),
              )
            : leading,
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: trailing,
        onTap: onTap,
      );
}

/// Settings pages sit above the app-level mini-player, not the home dock.
double settingsListBottomPadding(
  BuildContext context, {
  bool? miniPlayerVisible,
}) {
  final media = MediaQuery.of(context);
  final visible = miniPlayerVisible ??
      LayoutInsetsScope.maybeOf(context)?.hasActiveMiniPlayer ??
      false;
  return media.padding.bottom + (visible ? pocketLinkMiniPlayerHeight + 24.0 : 24.0);
}

EdgeInsets settingsListPadding(
  BuildContext context, {
  double horizontal = 16,
}) =>
    EdgeInsets.fromLTRB(
      horizontal,
      16,
      horizontal,
      settingsListBottomPadding(context),
    );
