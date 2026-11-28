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
class SettingsGroupCard extends StatelessWidget {
  const SettingsGroupCard({
    required this.children,
    super.key,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  List<Widget> _withDividers() {
    final result = <Widget>[];
    for (final child in children) {
      if (result.isNotEmpty &&
          result.last is! Divider &&
          child is! Divider) {
        result.add(const Divider(
          height: 1,
          thickness: 1,
          color: settingsDividerColor,
        ));
      }
      result.add(child);
    }
    return result;
  }

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
                  padding: padding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _withDividers(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Standard row for Settings content that does not need a specialised control.
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
        leading: leading,
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
