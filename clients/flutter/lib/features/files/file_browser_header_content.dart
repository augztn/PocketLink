import 'package:material_ui/material_ui.dart';

import 'file_browser_header_controls.dart';

/// Search, breadcrumb, filter, and request-status controls for the file browser.
/// The owning screen retains all state and navigation behavior.
class FileBrowserHeaderContent extends StatelessWidget {
  const FileBrowserHeaderContent({
    required this.searchExpanded,
    required this.searchController,
    required this.path,
    required this.storageLabel,
    required this.selectedCategory,
    required this.categoryCounts,
    required this.loading,
    required this.hasListing,
    required this.error,
    required this.colors,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onNavigate,
    required this.onCategorySelected,
    super.key,
  });

  final bool searchExpanded;
  final TextEditingController searchController;
  final String path;
  final String storageLabel;
  final String selectedCategory;
  final Map<String, int> categoryCounts;
  final bool loading;
  final bool hasListing;
  final String? error;
  final ColorScheme colors;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (searchExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: searchController,
                autofocus: true,
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search this folder',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    onPressed: onClearSearch,
                    icon: const Icon(Icons.close_rounded),
                  ),
                  filled: true,
                  fillColor: colors.surfaceContainerLow.withValues(alpha: 0.92),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          FileBrowserBreadcrumbs(
            path: path,
            storageLabel: storageLabel,
            onNavigate: onNavigate,
          ),
          FileCategoryFilter(
            selectedCategory: selectedCategory,
            counts: categoryCounts,
            onSelected: onCategorySelected,
          ),
          if (loading && hasListing)
            const LinearProgressIndicator(minHeight: 2),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Material(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: colors.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error!,
                          style: TextStyle(color: colors.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
