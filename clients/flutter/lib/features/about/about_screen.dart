import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/home_server_app_bar.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _version = '0.1.0';
  static const _buildNumber = '1';
  static const _sourceUrl = 'https://github.com/augztn/PocketLink';
  static const _developerUrl = 'https://github.com/augztn';

  Future<void> _openLink(BuildContext context, String value) async {
    final uri = Uri.parse(value);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this link.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this link.')),
        );
      }
    }
  }

  void _openLicenses(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LicensePage(
          applicationName: 'PocketLink',
          applicationVersion: '0.1.0+1',
          applicationLegalese: 'MIT License · © 2026 PocketLink contributors',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final architecture = Abi.current().toString().split('.').last;
    final platform = Platform.isAndroid
        ? 'Android'
        : Platform.isLinux
            ? 'Linux'
            : Platform.operatingSystem;

    return Scaffold(
      appBar: const HomeServerAppBar(title: Text('About PocketLink')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(18, 20, 18, 32 + MediaQuery.paddingOf(context).bottom),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(Icons.hub_rounded, size: 40, color: colors.onPrimaryContainer),
                ),
                const SizedBox(height: 14),
                Text('PocketLink', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text('Your files. Your devices. Your private server.', textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                const SizedBox(height: 14),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.45)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                    child: Text('Version $_version ($_buildNumber)', style: theme.textTheme.labelLarge),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text('APPLICATION', style: theme.textTheme.labelMedium?.copyWith(
            color: colors.primary, fontWeight: FontWeight.w800, letterSpacing: 1,
          )),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _AboutDetailTile(icon: Icons.info_outline_rounded, title: 'Application version', value: '$_version ($_buildNumber)'),
                const Divider(height: 1, indent: 56),
                _AboutDetailTile(icon: Icons.memory_rounded, title: 'Architecture', value: architecture),
                const Divider(height: 1, indent: 56),
                _AboutDetailTile(icon: Icons.devices_rounded, title: 'Platform', value: platform),
                const Divider(height: 1, indent: 56),
                _AboutDetailTile(icon: Icons.code_rounded, title: 'Framework', value: 'Flutter'),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text('PROJECT', style: theme.textTheme.labelMedium?.copyWith(
            color: colors.primary, fontWeight: FontWeight.w800, letterSpacing: 1,
          )),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: const Text('Developer'),
                  subtitle: const Text('augztn · GitHub profile'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => _openLink(context, _developerUrl),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.code_rounded),
                  title: const Text('Source code'),
                  subtitle: const Text('github.com/augztn/PocketLink'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => _openLink(context, _sourceUrl),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Open-source licenses'),
                  subtitle: const Text('MIT License and third-party notices'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openLicenses(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'PocketLink is an open-source project. See the source repository for project details, contributions and license information.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _AboutDetailTile extends StatelessWidget {
  const _AboutDetailTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    )),
  );
}
