import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/feathered_glass_header.dart';
import '../../../core/widgets/liquid_glass_pill.dart';
import 'music_library_header_title.dart';
import 'music_more_actions_menu.dart';
import 'music_selection_toolbar.dart';

class MusicLibraryHeader extends StatelessWidget {
  const MusicLibraryHeader({
    required this.topInset,
    required this.foreground,
    required this.searchExpanded,
    required this.selectionMode,
    required this.selectedCount,
    required this.searchController,
    required this.searchQuery,
    required this.menuOpen,
    required this.subtitle,
    required this.viewItems,
    required this.onSearchChanged,
    required this.onSearchClearOrClose,
    required this.onSearchToggle,
    required this.onFilter,
    required this.onViewSelected,
    required this.onMenuOpenChanged,
    required this.onShuffle,
    required this.onSelect,
    required this.onScan,
    required this.onSettings,
    required this.onHome,
    required this.onSelectionDone,
    super.key,
  });

  final double topInset;
  final Color foreground;
  final bool searchExpanded;
  final bool selectionMode;
  final int selectedCount;
  final TextEditingController searchController;
  final String searchQuery;
  final bool menuOpen;
  final String subtitle;
  final List<SmokedGlassPopoverMenuItem<String>> viewItems;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClearOrClose;
  final VoidCallback onSearchToggle;
  final VoidCallback onFilter;
  final ValueChanged<String> onViewSelected;
  final ValueChanged<bool> onMenuOpenChanged;
  final VoidCallback? onShuffle;
  final VoidCallback onSelect;
  final VoidCallback onScan;
  final VoidCallback onSettings;
  final VoidCallback onHome;
  final VoidCallback onSelectionDone;

  Widget _iconAction(IconData icon, String tooltip, VoidCallback onPressed) =>
      SizedBox(
        width: 36,
        height: 36,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          onPressed: onPressed,
          icon: Icon(icon, size: 18, color: foreground),
        ),
      );

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topInset + 88,
            child: const IgnorePointer(
              child: FeatheredGlassHeaderBackground(
                contentHeight: 44,
                darkTint: [
                  Color(0xD9000000),
                  Color(0x66000000),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Positioned(
            top: topInset + 10,
            left: 16,
            right: 16,
            height: 44,
            child: Row(
              children: [
                if (!searchExpanded)
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      size: 20,
                      color: foreground,
                    ),
                  ),
                if (searchExpanded)
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: LiquidGlassSurface(
                        radius: BorderRadius.circular(22),
                        refractive: true,
                        lightRefractive: true,
                        child: Row(
                          children: [
                            const SizedBox(width: 14),
                            Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: foreground.withValues(alpha: 0.72),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: searchController,
                                autofocus: true,
                                onChanged: onSearchChanged,
                                textInputAction: TextInputAction.search,
                                style: TextStyle(
                                  color: foreground,
                                  fontSize: 14,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Search songs or folders',
                                  hintStyle: TextStyle(
                                    color: Color(0xFF8E939E),
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: searchQuery.isEmpty
                                  ? 'Close search'
                                  : 'Clear search',
                              onPressed: onSearchClearOrClose,
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: foreground.withValues(alpha: 0.72),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: TitleDropdownPopover<String>(
                      tooltip: 'Choose music view',
                      onOpenChanged: onMenuOpenChanged,
                      items: viewItems,
                      onSelected: onViewSelected,
                      child: MusicLibraryHeaderTitle(
                        subtitle: subtitle,
                        menuOpen: menuOpen,
                        titleColor: foreground,
                      ),
                    ),
                  ),
                if (!searchExpanded) const SizedBox(width: 12),
                if (!searchExpanded && !selectionMode)
                  SizedBox(
                    height: 44,
                    child: LiquidGlassSurface(
                      radius: BorderRadius.circular(22),
                      refractive: true,
                      lightRefractive: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _iconAction(
                              Icons.search_rounded,
                              'Search',
                              onSearchToggle,
                            ),
                            _iconAction(
                              Icons.tune_rounded,
                              'Sort and filter',
                              onFilter,
                            ),
                            MusicMoreActionsMenu(
                              onShuffle: onShuffle,
                              onSelect: onSelect,
                              onScan: onScan,
                              onSettings: onSettings,
                              onHome: onHome,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (selectionMode)
                  MusicSelectionToolbar(
                    selectedCount: selectedCount,
                    foreground: foreground,
                    onDone: onSelectionDone,
                  ),
              ],
            ),
          ),
        ],
      );
}
