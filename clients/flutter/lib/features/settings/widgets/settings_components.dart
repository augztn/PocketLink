import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/pocketlink_scaffold.dart';

const Color settingsSectionColor = Color(0xFFB8C4FF);
const Color settingsGroupColor = Color(0xFF15161B);
const Color settingsDividerColor = Color(0x0FFFFFFF);

/// Shared uppercase section label used by every Settings category.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: settingsSectionColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
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
          titleTextStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          subtitleTextStyle: TextStyle(
            fontSize: 13.5,
            color: Color(0xFF9A9BA3),
          ),
        ),
        child: DividerTheme(
          data: const DividerThemeData(
            color: settingsDividerColor,
            thickness: 1,
            space: 1,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: settingsGroupColor,
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
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
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16),
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
