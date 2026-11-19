import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import '../../core/network/server_api.dart';
import 'photo_favorites_store.dart';
import '../../core/widgets/pocketlink_app_bar.dart';
import '../../core/widgets/feathered_glass_header.dart';
import '../../core/widgets/smoked_glass_popover_menu.dart';

class _Photo {
  const _Photo(this.file, this.path, this.volume);
  final FileEntry file;
  final String path;
  final String? volume;
  String get id => '${volume ?? 'internal'}:$path';
  DateTime get date => DateTime.tryParse(file.modified)?.toLocal() ?? DateTime(1970);
  String get album {
    final parts = path.split('/');
    if (parts.length < 2) return volume == null ? 'Internal storage' : 'USB / OTG';
    final folder = parts[parts.length - 2];
    if (folder.toLowerCase() == 'dcim') return 'Camera';
    if (folder.toLowerCase().contains('screenshot')) return 'Screenshots';
    if (folder.toLowerCase() == 'pictures') return 'Pictures';
    if (folder.toLowerCase() == 'download') return 'Downloads';
    return folder;
  }
}

class PhotoGalleryScreen extends StatefulWidget {
  const PhotoGalleryScreen({required this.api, this.showSearch = true, this.initialTab = 0, super.key});
  final ServerApi api;
  final bool showSearch;
  final int initialTab;
  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
  static const extensions = {'jpg','jpeg','png','webp','gif','bmp','heic','heif','avif'};
  final search = TextEditingController();
  final favorites = <String>{};
  final selected = <String>{};
  PhotoFavoritesStore? _favoritesStore;
  List<_Photo> photos = [];
  List<StorageVolume> volumes = [];
  bool loading = true;
  bool searchOpen = false;
  String? error;
  String? source;
  int tab = 0;
  int dateMode = 0;
  int gridColumns = 3;
  bool _viewMenuOpen = false;

  @override
  void initState() { super.initState(); tab = widget.initialTab.clamp(0, 2).toInt(); _initialize(); }

  Future<void> _initialize() async {
    try {
      _favoritesStore = await PhotoFavoritesStore.inApplicationSupportDirectory();
      favorites.addAll(await _favoritesStore!.load());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load photo favourites: $e')),
        );
      }
    }
    if (mounted) await scan();
  }

  Future<void> _persistFavorites() async {
    final store = _favoritesStore;
    if (store == null) return;
    try {
      await store.save(favorites);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save photo favourites: $e')),
        );
      }
    }
  }

  void _toggleFavorite(_Photo photo) {
    setState(() {
      if (!favorites.add(photo.id)) favorites.remove(photo.id);
    });
    _persistFavorites();
  }

  @override
  void dispose() { search.dispose(); super.dispose(); }

  Future<List<_Photo>> _readIndexedPhotos() async {
    final found = <_Photo>[];
    var offset = 0;
    while (true) {
      final page = await widget.api.indexedMedia(
        'photo', limit: 500, offset: offset,
      );
      if (!mounted) break;
      found.addAll(page.items.map((item) => _Photo(
        item.toFileEntry(),
        item.path,
        item.volume == 'internal' ? null : item.volume,
      )));
      if (page.items.length < 500) break;
      offset += page.items.length;
    }
    found.sort((a, b) => b.date.compareTo(a.date));
    return found;
  }

  Future<void> scan({bool refresh = false}) async {
    if (refresh) {
      widget.api.invalidateDirectoryCache();
      try {
        await widget.api.startMediaIndexScan();
      } catch (_) {
        if (!mounted) return;
        await _scanLegacy(refresh: refresh);
        return;
      }
    }
    if (!mounted) return;
    setState(() { loading = true; error = null; photos = []; selected.clear(); });
    try {
      volumes = await widget.api.listStorageVolumes();
      if (!mounted) return;
      var found = await _readIndexedPhotos();
      if (!mounted) return;
      var status = await widget.api.mediaIndexStatus();
      if (!mounted) return;
      if (mounted) setState(() => photos = List.unmodifiable(found));
      final wasScanning = status.isScanning;
      while (mounted && status.isScanning) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        status = await widget.api.mediaIndexStatus();
      }
      if (!mounted) return;
      if (wasScanning && status.state != 'failed') {
        found = await _readIndexedPhotos();
      }
      if ((status.state == 'failed' || status.state == 'partial') && found.isEmpty) {
        await _scanLegacy();
        return;
      }
      if (mounted) {
        setState(() {
          photos = List.unmodifiable(found);
          loading = false;
          error = status.state == 'partial' && found.isEmpty
              ? status.lastError
              : null;
        });
      }
    } catch (_) {
      await _scanLegacy(refresh: refresh);
    }
  }

  Future<void> _scanLegacy({bool refresh = false}) async {
    if (!mounted) return;
    if (refresh) widget.api.invalidateDirectoryCache();
    setState(() { loading = true; error = null; photos = []; selected.clear(); });
    final found = <_Photo>[];
    final pending = <({String path, String? volume, int depth})>[];
    final visited = <String>{};
    try {
      try {
        volumes = await widget.api.listStorageVolumes();
        for (final v in volumes.where((v) => v.available)) {
          pending.add((path: '', volume: v.id, depth: 0));
        }
      } catch (_) {}
      for (final root in const ['DCIM','Pictures','Download']) {
        pending.add((path: root, volume: null, depth: 0));
      }
      var cursor = 0;
      while (mounted && cursor < pending.length && visited.length < 3000) {
        final current = pending[cursor++];
        final key = '${current.volume ?? 'internal'}:${current.path}';
        if (!visited.add(key)) continue;
        try {
          final listing = current.volume == null
              ? await widget.api.listDirectory(current.path)
              : await widget.api.listStorageDirectory(current.volume!, current.path);
          if (!mounted) return;
          for (final item in listing.items) {
            final path = current.path.isEmpty ? item.name : '${current.path}/${item.name}';
            if (item.isDirectory) {
              if (current.depth < 24) pending.add((path: path, volume: current.volume, depth: current.depth + 1));
            } else {
              final ext = item.name.contains('.') ? item.name.split('.').last.toLowerCase() : '';
              if (extensions.contains(ext)) found.add(_Photo(item, path, current.volume));
            }
          }
        } catch (_) {}
        if (mounted && cursor % 10 == 0) setState(() => photos = List.of(found));
      }
      found.sort((a,b) => b.date.compareTo(a.date));
    } catch (e) {
      error = 'Could not scan photos: $e';
    } finally {
      if (mounted) setState(() { photos = List.unmodifiable(found); loading = false; });
    }
  }

  List<_Photo> get visible => photos.where((p) {
    final q = search.text.trim().toLowerCase();
    final matches = q.isEmpty || p.file.name.toLowerCase().contains(q) ||
        p.path.toLowerCase().contains(q) || p.album.toLowerCase().contains(q);
    return matches && (source == null || (source == 'internal' ? p.volume == null : p.volume == source)) &&
        (tab != 2 || favorites.contains(p.id));
  }).toList();

  Map<String,List<_Photo>> groupByAlbum(List<_Photo> items) {
    final result = <String,List<_Photo>>{};
    for (final p in items) { result.putIfAbsent(p.album, () => []).add(p); }
    return result;
  }

  String month(int m) => const ['January','February','March','April','May','June','July','August','September','October','November','December'][m-1];
  String group(_Photo p) {
    if (p.date.year == 1970) return 'Date unavailable';
    if (dateMode == 2) return '${p.date.year}';
    if (dateMode == 1) return '${month(p.date.month)} ${p.date.year}';
    return '${month(p.date.month)} ${p.date.day}, ${p.date.year}';
  }

  Widget image(_Photo p) => Image.network(
    widget.api.mediaStreamUrl(p.path, volume: p.volume),
    headers: widget.api.mediaHeaders, fit: BoxFit.cover, cacheWidth: 480,
    gaplessPlayback: true,
    errorBuilder: (_,__,___) => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.broken_image_outlined),
    ),
  );

  void openViewer(List<_Photo> items, int index) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => _PhotoViewer(
      photos: items, index: index, api: widget.api,
      favorite: (p) => favorites.contains(p.id),
      onFavorite: _toggleFavorite,
    )));
  }

  Widget grid(List<_Photo> items, {bool shrinkWrap = false}) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (!width.isFinite || width <= 0) return const SizedBox.shrink();
      return GridView.builder(
    shrinkWrap: shrinkWrap,
    physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
    padding: EdgeInsets.fromLTRB(
      2, 2, 2, shrinkWrap ? 0 : 104 + MediaQuery.paddingOf(context).bottom,
    ),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: gridColumns.clamp(2, 5), crossAxisSpacing: 2, mainAxisSpacing: 2),
    itemCount: items.length,
    itemBuilder: (_,i) {
      final p = items[i]; final isSelected = selected.contains(p.id);
      return GestureDetector(
        onTap: () => selected.isNotEmpty
            ? setState(() { if (!selected.add(p.id)) selected.remove(p.id); })
            : openViewer(items,i),
        onLongPress: () => setState(() { if (!selected.add(p.id)) selected.remove(p.id); }),
        child: Stack(fit: StackFit.expand, children: [
          image(p),
          if (isSelected) ColoredBox(color: Theme.of(context).colorScheme.primary.withValues(alpha: .35)),
          if (favorites.contains(p.id)) const Positioned(top:5,right:5,child:Icon(Icons.favorite,color:Colors.white,size:17)),
          if (isSelected) Positioned(top:5,right:5,child:Icon(Icons.check_circle,color:Theme.of(context).colorScheme.primary)),
        ]),
      );
    },
      );
    },
  );

  Widget photosTab(List<_Photo> items) {
    if (items.isEmpty) return empty('No photos found in internal or connected USB storage.');
    if (dateMode == 3) return grid(items);
    final groups = <String,List<_Photo>>{};
    for (final p in items) { groups.putIfAbsent(group(p), () => []).add(p); }
    return ListView(padding: EdgeInsets.only(bottom: 104 + MediaQuery.paddingOf(context).bottom), children: [
      for (final entry in groups.entries) ...[
        Padding(padding: const EdgeInsets.fromLTRB(16,18,16,8),
          child: Row(children: [
            Expanded(child: Text(entry.key,style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w700))),
            Text('${entry.value.length}'),
          ])),
        grid(entry.value, shrinkWrap: true),
      ],
      const SizedBox(height:24),
    ]);
  }

  Widget albumsTab(List<_Photo> items) {
    final albums = groupByAlbum(items).entries.toList()..sort((a,b)=>a.key.compareTo(b.key));
    if (albums.isEmpty) return empty('Albums will appear when photos are found.');
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 104 + MediaQuery.paddingOf(context).bottom),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:2,crossAxisSpacing:12,mainAxisSpacing:16,childAspectRatio:.92),
      itemCount: albums.length,
      itemBuilder: (_,i) {
        final a=albums[i];
        return InkWell(
          borderRadius:BorderRadius.circular(16),
          onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>_PhotoAlbum(
            title:a.key,photos:a.value,api:widget.api,onOpen:(index)=>openViewer(a.value,index)))),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Expanded(child:ClipRRect(borderRadius:BorderRadius.circular(16),child:SizedBox.expand(child:image(a.value.first)))),
            const SizedBox(height:8),
            Text(a.key,maxLines:1,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight:FontWeight.w700)),
            Text('${a.value.length} items',style:Theme.of(context).textTheme.bodySmall),
          ]),
        );
      },
    );
  }

  Widget discoverTab(List<_Photo> items) {
    final memories=<String,List<_Photo>>{};
    for(final p in items) {
      final key=p.date.year==1970?'Recently added':'${month(p.date.month)} ${p.date.year}';
      memories.putIfAbsent(key,()=>[]).add(p);
    }
    final featured=memories.entries.take(8).toList();
    final albums=groupByAlbum(items);
    return ListView(padding:EdgeInsets.fromLTRB(16,16,16,104 + MediaQuery.paddingOf(context).bottom),children:[
      Text('Memories',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w800)),
      const SizedBox(height:4),
      Text('Moments grouped by the dates stored with your photos.',style:Theme.of(context).textTheme.bodySmall),
      const SizedBox(height:14),
      SizedBox(height:190,child:featured.isEmpty?empty('Your memories will appear here.'):ListView.separated(
        scrollDirection:Axis.horizontal,itemCount:featured.length,separatorBuilder:(_,__)=>const SizedBox(width:12),
        itemBuilder:(_,i){
          final m=featured[i];
          return SizedBox(width:260,child:InkWell(
            onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>_PhotoAlbum(
              title:m.key,photos:m.value,api:widget.api,onOpen:(index)=>openViewer(m.value,index)))),
            child:ClipRRect(borderRadius:BorderRadius.circular(18),child:Stack(fit:StackFit.expand,children:[
              image(m.value.first),
              const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(
                begin:Alignment.topCenter,end:Alignment.bottomCenter,
                colors:[Colors.transparent,Color(0xCC000000)]))),
              Positioned(left:14,bottom:14,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(m.key,style:const TextStyle(color:Colors.white,fontSize:17,fontWeight:FontWeight.w700)),
                Text('${m.value.length} photos',style:const TextStyle(color:Colors.white70)),
              ])),
            ])),
          ));
        },
      )),
      const SizedBox(height:26),
      Text('Smart albums',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w800)),
      for(final name in ['Camera','Screenshots','Pictures','Downloads'])
        if(albums.containsKey(name))
          ListTile(
            contentPadding:EdgeInsets.zero,
            leading:ClipRRect(borderRadius:BorderRadius.circular(12),child:SizedBox(width:54,height:54,child:image(albums[name]!.first))),
            title:Text(name),subtitle:Text('${albums[name]!.length} items'),
            trailing:const Icon(Icons.chevron_right),
            onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>_PhotoAlbum(
              title:name,photos:albums[name]!,api:widget.api,onOpen:(index)=>openViewer(albums[name]!,index)))),
          ),
    ]);
  }

  Widget empty(String text) => Center(child:Padding(
    padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Icon(Icons.photo_library_outlined,size:52,color:Theme.of(context).colorScheme.outline),
      const SizedBox(height:12),Text(text,textAlign:TextAlign.center),
    ]),
  ));

  Future<void> deleteSelected() async {
    final count=selected.length;
    final ok=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
      title:Text('Delete $count selected photos?'),
      content:const Text('This permanently deletes the selected files from PocketLink storage.'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Delete')),
      ],
    ));
    if(ok!=true)return;
    final targets=photos.where((p)=>selected.contains(p.id)).toList();
    var deleted=0;
    final deletedIds = <String>{};
    for(final p in targets){
      try{
        if(p.volume==null){await widget.api.deleteItem(p.path);}
        else{await widget.api.deleteStorageItem(p.volume!,p.path);}
        deleted++;
        deletedIds.add(p.id);
      }catch(_){}
    }
    if(!mounted)return;
    setState((){
      photos=photos.where((p)=>!deletedIds.contains(p.id)).toList();
      favorites.removeAll(deletedIds);selected.clear();
    });
    if (deletedIds.isNotEmpty) await _persistFavorites();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Deleted $deleted of $count photos.')));
  }

  Future<void> favoriteSelected() async {
    setState(() {
      for (final p in photos.where((p) => selected.contains(p.id))) {
        if (!favorites.add(p.id)) favorites.remove(p.id);
      }
      selected.clear();
    });
    await _persistFavorites();
  }

  Future<void> _showFilters() async {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colors.surfaceContainerLow,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Photo view', style: theme.textTheme.titleLarge?.copyWith(
                  color: colors.onSurface, fontWeight: FontWeight.w800,
                )),
                const SizedBox(height: 16),
                Text('Grouping', style: theme.textTheme.titleSmall?.copyWith(color: colors.onSurfaceVariant)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final option in const [(0, 'Days'), (1, 'Months'), (2, 'Years'), (3, 'Grid')])
                      ChoiceChip(
                        label: Text(option.$2),
                        selected: dateMode == option.$1,
                        onSelected: (_) {
                          setState(() => dateMode = option.$1);
                          setSheetState(() {});
                        },
                        backgroundColor: colors.surfaceContainer,
                        selectedColor: colors.primaryContainer,
                        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.68)),
                        labelStyle: TextStyle(
                          color: dateMode == option.$1
                              ? colors.onPrimaryContainer
                              : colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: Text('Grid density', style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant))),
                    Text('$gridColumns columns', style: theme.textTheme.labelLarge?.copyWith(color: colors.onSurface)),
                  ],
                ),
                Slider(
                  min: 2,
                  max: 5,
                  divisions: 3,
                  value: gridColumns.toDouble(),
                  onChanged: (value) {
                    setState(() => gridColumns = value.round());
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 12),
                Text('Storage source', style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: source ?? 'all',
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: colors.surfaceContainer,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.68)),
                    ),
                  ),
                  dropdownColor: colors.surfaceContainerHigh,
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All storage')),
                    const DropdownMenuItem(value: 'internal', child: Text('Internal storage')),
                    ...volumes.map((volume) => DropdownMenuItem(
                      value: volume.id,
                      enabled: volume.available,
                      child: Text(volume.name),
                    )),
                  ],
                  onChanged: (value) {
                    setState(() => source = value == null || value == 'all' ? null : value);
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = visible;
    final selecting = selected.isNotEmpty;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF0F172A);
    final title = selecting ? '${selected.length} selected' : const ['Photos', 'Albums', 'Favorites'][tab];
    final albumCount = groupByAlbum(photos).length;
    final favoriteCount = photos.where((p) => favorites.contains(p.id)).length;
    final counts = [photos.length, albumCount, favoriteCount];
    final headerTop = MediaQuery.paddingOf(context).top;
    final contentTop = headerTop + 76;

    Widget viewRow(int index) {
      final active = tab == index;
      return InkWell(
        onTap: () => setState(() { tab = index; _viewMenuOpen = false; selected.clear(); }),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Expanded(child: Text(
              const ['Photos', 'Albums', 'Favorites'][index],
              style: TextStyle(color: active ? foreground : const Color(0xFFA1A7B3),
                fontWeight: active ? FontWeight.w700 : FontWeight.w500, fontSize: 15),
            )),
            Text('${counts[index]}', style: const TextStyle(
              color: Color(0xFFA1A7B3), fontSize: 12,
              fontFamily: 'monospace', fontFeatures: [ui.FontFeature.tabularFigures()],
            )),
            if (active) ...[
              const SizedBox(width: 10),
              Icon(Icons.check_rounded, color: foreground, size: 19),
            ],
          ]),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(children: [
            SizedBox(height: contentTop),
            if (widget.showSearch && searchOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: search,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search photos, folders or dates',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      onPressed: () { search.clear(); setState(() {}); },
                      icon: const Icon(Icons.clear),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerLow,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  ),
                ),
              ),
            if (loading) const LinearProgressIndicator(minHeight: 2),
            if (error != null)
              Padding(padding: const EdgeInsets.all(12),
                child: Text(error!, style: TextStyle(color: theme.colorScheme.error))),
            Expanded(
              child: error != null
                  ? Center(child: FilledButton(onPressed: scan, child: const Text('Retry scan')))
                  : loading && photos.isEmpty
                      ? const Center(child: Text('Scanning photos…'))
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOutCubic,
                          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                          child: KeyedSubtree(
                            key: ValueKey<int>(tab),
                            child: tab == 1
                                ? albumsTab(items)
                                : items.isEmpty
                                    ? empty(tab == 2 ? 'No favourite photos yet.' : 'No photos found in internal or connected USB storage.')
                                    : photosTab(items),
                          ),
                        ),
            ),
          ]),
          Positioned(
            top: 0, left: 0, right: 0, height: headerTop + 88,
            child: const IgnorePointer(child: FeatheredGlassHeaderBackground()),
          ),
          Positioned(
            top: headerTop + 8, left: 16, right: 16, height: 52,
            child: Row(children: [
              if (selecting)
                GlassCircleButton(tooltip: 'Clear selection', onPressed: () => setState(selected.clear),
                  child: const Icon(Icons.close_rounded))
              else
                Expanded(child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _viewMenuOpen = !_viewMenuOpen),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(
                          color: foreground, fontSize: 28, fontWeight: FontWeight.w800,
                          letterSpacing: -0.7,
                        ))),
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: _viewMenuOpen ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: Icon(Icons.keyboard_arrow_down_rounded, color: foreground, size: 27),
                        ),
                      ]),
                    ),
                  ),
                )),
              if (selecting)
                Text('${selected.length} selected', style: TextStyle(color: foreground, fontWeight: FontWeight.w700))
              else ...[
              ],
              const SizedBox(width: 8),
              SmokedGlassPopoverMenu<String>(
                tooltip: 'More photo actions',
                items: [
                  if (widget.showSearch) SmokedGlassPopoverMenuItem(value: 'search', label: searchOpen ? 'Close search' : 'Search photos', icon: searchOpen ? Icons.close_rounded : Icons.search_rounded),
                  const SmokedGlassPopoverMenuItem(
                    value: 'filter',
                    label: 'Filter & layout',
                    icon: Icons.tune_rounded,
                  ),
                  const SmokedGlassPopoverMenuItem(
                    value: 'select',
                    label: 'Select all / clear',
                    icon: Icons.checklist_rounded,
                    dividerBefore: true,
                  ),
                  SmokedGlassPopoverMenuItem(
                    value: 'scan',
                    label: 'Scan again',
                    icon: Icons.refresh_rounded,
                    enabled: !loading,
                  ),
                  const SmokedGlassPopoverMenuItem(
                    value: 'transfers',
                    label: 'Transfers',
                    icon: Icons.swap_vert_rounded,
                    dividerBefore: true,
                  ),
                ],
                onSelected: (value) {
                  if (value == 'search') setState(() => searchOpen = !searchOpen);
                  if (value == 'filter') _showFilters();
                  if (value == 'scan') scan(refresh: true);
                  if (value == 'transfers') {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const TransferManagerScreen(),
                    ));
                  }
                  if (value == 'select') setState(() {
                    if (selected.isEmpty) selected.addAll(items.map((p) => p.id));
                    else selected.clear();
                  });
                },
                child: GlassCircleButton(tooltip: 'More actions', onPressed: null,
                  child: const Icon(Icons.more_vert_rounded)),
              ),
            ]),
          ),
          if (_viewMenuOpen) ...[
            Positioned.fill(
              top: headerTop + 64,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _viewMenuOpen = false),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            Positioned(
              top: headerTop + 64, left: 16, width: 220,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.92, end: 1),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                builder: (context, scale, child) => Opacity(
                  opacity: ((scale - 0.92) / 0.08).clamp(0, 1),
                  child: Transform.scale(alignment: Alignment.topLeft, scale: scale, child: child),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xE51A1C22) : const Color(0xEEF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isDark
                          ? Colors.white.withValues(alpha: 0.16)
                          : const Color(0xFF94A3B8).withValues(alpha: 0.32)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          for (var i = 0; i < 3; i++) viewRow(i),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: selecting
          ? SafeArea(child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: favoriteSelected,
                  icon: const Icon(Icons.favorite_border), label: const Text('Favourite'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton.icon(onPressed: deleteSelected,
                  icon: const Icon(Icons.delete_outline), label: const Text('Delete'))),
              ]),
            ))
          : null,
    );
  }

}

class _PhotoAlbum extends StatelessWidget {
  const _PhotoAlbum({required this.title,required this.photos,required this.api,required this.onOpen});
  final String title;final List<_Photo> photos;final ServerApi api;final ValueChanged<int> onOpen;
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:PocketLinkAppBar(title:Text(title)),
    body:GridView.builder(
      padding:const EdgeInsets.all(2),
      gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:3,crossAxisSpacing:2,mainAxisSpacing:2),
      itemCount:photos.length,
      itemBuilder:(_,i)=>GestureDetector(onTap:()=>onOpen(i),child:Image.network(
        api.mediaStreamUrl(photos[i].path,volume:photos[i].volume),headers:api.mediaHeaders,fit:BoxFit.cover,cacheWidth:480,
        errorBuilder:(_,__,___)=>const ColoredBox(color:Color(0xFFE5E5E5),child:Icon(Icons.broken_image_outlined)),
      )),
    ),
  );
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.photos,required this.index,required this.api,required this.favorite,required this.onFavorite});
  final List<_Photo> photos;final int index;final ServerApi api;
  final bool Function(_Photo) favorite;final ValueChanged<_Photo> onFavorite;
  @override
  State<_PhotoViewer> createState()=>_PhotoViewerState();
}
class _PhotoViewerState extends State<_PhotoViewer>{
  late final PageController controller;late int index;bool controls=true;
  @override
  void initState(){super.initState();index=widget.index;controller=PageController(initialPage:index);}
  @override
  void dispose(){controller.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){
    final p=widget.photos[index];
    return Scaffold(
      backgroundColor:Colors.black,
      appBar:controls?PocketLinkAppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(p.file.name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:15)),
          Text('${index+1} / ${widget.photos.length}',style:const TextStyle(fontSize:11,color:Colors.white70)),
        ]),
        actions:[
          PocketLinkAppBarAction(
            label: widget.favorite(p) ? 'Remove favorite' : 'Add favorite',
            icon: widget.favorite(p) ? Icons.favorite : Icons.favorite_border,
            onPressed: () => setState(() => widget.onFavorite(p)),
          ),
        ],
      ):null,
      body:GestureDetector(
        onTap:()=>setState(()=>controls=!controls),
        child:PageView.builder(
          controller:controller,itemCount:widget.photos.length,
          onPageChanged:(i)=>setState(()=>index=i),
          itemBuilder:(_,i){final photo=widget.photos[i];return Center(child:InteractiveViewer(
            minScale:.8,maxScale:5,
            child:Image.network(widget.api.mediaStreamUrl(photo.path,volume:photo.volume),
              headers:widget.api.mediaHeaders,fit:BoxFit.contain,
              errorBuilder:(_,__,___)=>const Icon(Icons.broken_image_outlined,color:Colors.white70,size:56)),
          ));},
        ),
      ),
      bottomNavigationBar:controls?SafeArea(child:Padding(padding:const EdgeInsets.all(12),child:Text(
        '${p.album} · ${p.date.day}/${p.date.month}/${p.date.year} · ${p.file.size} bytes',
        textAlign:TextAlign.center,style:const TextStyle(color:Colors.white70,fontSize:12),
      ))):null,
    );
  }
}
