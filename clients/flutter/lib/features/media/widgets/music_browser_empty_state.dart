import 'package:material_ui/material_ui.dart';

class MusicBrowserEmptyState extends StatelessWidget {
  const MusicBrowserEmptyState({
    required this.error,
    required this.loading,
    required this.favoritesView,
    required this.onRetry,
    required this.topPadding,
    required this.bottomPadding,
    super.key,
  });

  final String? error;
  final bool loading;
  final bool favoritesView;
  final VoidCallback onRetry;
  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(0, topPadding, 0, bottomPadding),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: Center(
              child: error != null
                  ? FilledButton(
                      onPressed: onRetry,
                      child: const Text('Retry scan'),
                    )
                  : loading
                      ? PocketLinkSkeleton.musicList(rows: 5)
                      : Text(
                          favoritesView
                              ? 'No favourite tracks yet.'
                              : 'No music found. Scan storage to find tracks.',
                        ),
            ),
          ),
        ],
      );
}
