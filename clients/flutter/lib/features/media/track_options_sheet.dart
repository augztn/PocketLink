import 'package:material_ui/material_ui.dart';

enum TrackOptionAction {
  favorite,
  download,
  share,
  playNext,
  addToQueue,
  showInFolder,
  fileInfo,
  sleepTimer,
  removeFromCache,
}

class TrackOptionsSheet {
  const TrackOptionsSheet._();

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<TrackOptionAction> onAction,
    required bool isFavorite,
    required bool isCached,
    bool serverActionsEnabled = true,
  }) {
    return showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierLabel: 'Track options',
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.64),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final size = MediaQuery.sizeOf(dialogContext);
        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: size.width * 0.72,
              height: size.height - 24,
              margin: const EdgeInsets.only(top: 12, bottom: 12, right: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 32,
                    offset: Offset(-8, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: Column(
                  children: [
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          _TopAction(
                            icon: isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                            label: 'Favorite',
                            onTap: () => _select(
                              dialogContext,
                              onAction,
                              TrackOptionAction.favorite,
                            ),
                          ),
                          if (serverActionsEnabled) _TopAction(
                            icon: Icons.download_rounded,
                            label: 'Download',
                            onTap: () => _select(
                              dialogContext,
                              onAction,
                              TrackOptionAction.download,
                            ),
                          ),
                          if (serverActionsEnabled) _TopAction(
                            icon: Icons.ios_share_rounded,
                            label: 'Share',
                            onTap: () => _select(
                              dialogContext,
                              onAction,
                              TrackOptionAction.share,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 18, 18, 12),
                      child: Divider(height: 1, color: Color(0x22FFFFFF)),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
                        children: [
                          _ActionTile(
                            Icons.skip_next_rounded,
                            'Play next',
                            () => _select(dialogContext, onAction, TrackOptionAction.playNext),
                          ),
                          _ActionTile(
                            Icons.queue_music_rounded,
                            'Add to queue',
                            () => _select(dialogContext, onAction, TrackOptionAction.addToQueue),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Divider(height: 1, color: Color(0x22FFFFFF)),
                          ),
                          if (serverActionsEnabled) _ActionTile(
                            Icons.folder_open_rounded,
                            'Show in folder',
                            () => _select(dialogContext, onAction, TrackOptionAction.showInFolder),
                          ),
                          if (serverActionsEnabled) _ActionTile(
                            Icons.info_outline_rounded,
                            'File info',
                            () => _select(dialogContext, onAction, TrackOptionAction.fileInfo),
                          ),
                          _ActionTile(
                            Icons.bedtime_outlined,
                            'Sleep timer',
                            () => _select(dialogContext, onAction, TrackOptionAction.sleepTimer),
                          ),
                          if (isCached)
                            _ActionTile(
                              Icons.delete_sweep_outlined,
                              'Remove from cache',
                              () => _select(dialogContext, onAction, TrackOptionAction.removeFromCache),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  static void _select(
    BuildContext context,
    ValueChanged<TrackOptionAction> callback,
    TrackOptionAction action,
  ) {
    Navigator.of(context).pop();
    callback(action);
  }
}

class _TopAction extends StatelessWidget {
  const _TopAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 23, color: Colors.white70),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    minLeadingWidth: 24,
    horizontalTitleGap: 12,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    leading: Icon(icon, size: 20, color: Colors.white70),
    title: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
    onTap: onTap,
  );
}
