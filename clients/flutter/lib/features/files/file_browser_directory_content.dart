import 'package:material_ui/material_ui.dart';

import '../../core/network/server_api.dart';
import '../../core/widgets/pocketlink_skeleton.dart';

/// Renders the directory's empty, loading, list, and grid states.
/// File operations and directory state remain owned by FileManagerScreen.
class FileBrowserDirectoryContent extends StatelessWidget {
  const FileBrowserDirectoryContent({
    required this.allItemsEmpty,
    required this.items,
    required this.initialLoading,
    required this.error,
    required this.gridView,
    required this.scrollController,
    required this.topInset,
    required this.bottomInset,
    required this.colors,
    required this.textTheme,
    required this.onRefresh,
    required this.itemBuilder,
    super.key,
  });

  final bool allItemsEmpty;
  final List<FileEntry> items;
  final bool initialLoading;
  final String? error;
  final bool gridView;
  final ScrollController scrollController;
  final double topInset;
  final double bottomInset;
  final ColorScheme colors;
  final TextTheme textTheme;
  final Future<void> Function() onRefresh;
  final Widget Function(FileEntry item, bool grid) itemBuilder;

  Widget _emptyList(String message, {Widget? action}) {
    return ListView(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, topInset, 16, bottomInset),
      children: [
        SizedBox(
          height: 150,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 12),
                  action,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (error != null) {
      content = _emptyList(
        error!,
        action: FilledButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    } else if (initialLoading) {
      final padding = EdgeInsets.fromLTRB(16, topInset, 16, bottomInset);
      content = gridView
          ? PocketLinkSkeleton.fileGrid(padding: padding)
          : PocketLinkSkeleton.fileList(padding: padding);
    } else if (items.isEmpty) {
      content = _emptyList(
        allItemsEmpty ? 'This folder is empty' : 'No matching files',
      );
    } else if (gridView) {
      content = GridView.builder(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, topInset, 16, bottomInset),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          mainAxisExtent: 156,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) => itemBuilder(items[index], true),
      );
    } else {
      content = ListView.separated(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, topInset, 16, bottomInset),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => itemBuilder(items[index], false),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: content,
    );
  }
}
