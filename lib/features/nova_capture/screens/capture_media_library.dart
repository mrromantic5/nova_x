// lib/features/nova_capture/screens/capture_media_library.dart
//
// Screenshots and recordings saved by NOVA X: grid or list, sort, filter,
// search (name or date), favourites and folders. Lists only NOVA X's own
// folders through MediaStore — no broad storage access.

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/capture_controller.dart';
import '../models/media_asset.dart';
import '../services/media_library_service.dart';
import '../widgets/capture_flows.dart';
import '../widgets/capture_thumb.dart';
import '../widgets/capture_ui.dart';
import 'media_actions.dart';

class CaptureMediaLibrary extends StatefulWidget {
  const CaptureMediaLibrary({super.key, this.initialFilter = MediaFilter.all});
  final MediaFilter initialFilter;

  @override
  State<CaptureMediaLibrary> createState() => _CaptureMediaLibraryState();
}

class _CaptureMediaLibraryState extends State<CaptureMediaLibrary> {
  final _lib = MediaLibraryService.instance;
  final _c = CaptureController.instance;
  final _search = TextEditingController();
  late MediaLibraryQuery _q = MediaLibraryQuery(filter: widget.initialFilter);
  List<MediaAsset> _all = const [];
  bool _grid = true;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _c.libraryVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _c.libraryVersion.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _c.init();
      final items = await _lib.list();
      if (!mounted) return;
      setState(() {
        _all = items;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  List<MediaAsset> get _shown =>
      MediaLibrary.apply(_all, _q, favorites: _lib.favorites, categories: _lib.categories);

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
        title: Text('My captures', style: captureText(18, weight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: _grid ? 'Show as list' : 'Show as grid',
            icon: Icon(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded, color: AppTheme.textPrimary),
            onPressed: () => setState(() => _grid = !_grid),
          ),
          PopupMenuButton<MediaSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort_rounded, color: AppTheme.textPrimary),
            initialValue: _q.sort,
            onSelected: (s) => setState(() => _q = _q.copyWith(sort: s)),
            itemBuilder: (_) => const [
              PopupMenuItem(value: MediaSort.newest, child: Text('Newest first')),
              PopupMenuItem(value: MediaSort.oldest, child: Text('Oldest first')),
              PopupMenuItem(value: MediaSort.name, child: Text('Name')),
              PopupMenuItem(value: MediaSort.size, child: Text('File size')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _q = _q.copyWith(search: v)),
            style: captureText(14),
            decoration: InputDecoration(
              hintText: 'Search by name or date (e.g. “oct 2026”)',
              hintStyle: captureText(13.5, color: AppTheme.textHint),
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textHint),
              suffixIcon: _q.search.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded, color: AppTheme.textHint),
                      onPressed: () => setState(() {
                        _search.clear();
                        _q = _q.copyWith(search: '');
                      }),
                    ),
              filled: true,
              fillColor: AppTheme.bgInput,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final f in MediaFilter.values) _chip(_filterLabel(f), _q.filter == f, () => setState(() => _q = _q.copyWith(filter: f))),
              for (final folder in _lib.folders)
                _chip('📁 $folder', _q.category == folder, () => setState(() =>
                    _q = _q.category == folder ? _q.copyWith(clearCategory: true) : _q.copyWith(category: folder))),
            ],
          ),
        ),
        Expanded(child: _body(shown)),
      ]),
    );
  }

  String _filterLabel(MediaFilter f) => switch (f) {
        MediaFilter.all => 'All',
        MediaFilter.screenshots => 'Screenshots',
        MediaFilter.recordings => 'Recordings',
        MediaFilter.favorites => 'Favourites',
      };

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(
          label: Text(label, style: captureText(12.5, color: selected ? Colors.black : AppTheme.textPrimary)),
          selected: selected,
          onSelected: (_) => onTap(),
          selectedColor: AppTheme.accentCyan,
          backgroundColor: AppTheme.bgCard,
          side: const BorderSide(color: AppTheme.glassBorder),
        ),
      );

  Widget _body(List<MediaAsset> shown) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_error) {
      return _empty(Icons.error_outline_rounded, "Your captures couldn't be read right now.", retry: true);
    }
    if (_all.isEmpty) {
      return _empty(Icons.photo_library_outlined,
          'No captures yet.\nScreenshots and recordings you make with NOVA X appear here.');
    }
    if (shown.isEmpty) return _empty(Icons.search_off_rounded, 'Nothing matches.');
    return RefreshIndicator(
      onRefresh: _load,
      child: _grid
          ? GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.72,
              ),
              itemCount: shown.length,
              itemBuilder: (context, i) => _gridItem(shown[i]),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: shown.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) => _listItem(shown[i]),
            ),
    );
  }

  Widget _empty(IconData icon, String text, {bool retry = false}) => ListView(children: [
        const SizedBox(height: 80),
        Icon(icon, size: 56, color: AppTheme.textHint),
        const SizedBox(height: 14),
        Text(text, textAlign: TextAlign.center, style: captureText(14, color: AppTheme.textSecondary)),
        if (retry) Center(child: TextButton(onPressed: _load, child: const Text('Try again'))),
      ]);

  String _semantic(MediaAsset a) =>
      '${a.isVideo ? 'Recording' : 'Screenshot'} ${a.name}, ${formatCaptureDate(a.created)}, ${formatBytes(a.sizeBytes)}'
      '${a.isVideo && a.durationMs > 0 ? ', ${formatDuration(Duration(milliseconds: a.durationMs))}' : ''}'
      '${_lib.isFavorite(a.uri) ? ', favourite' : ''}';

  Widget _gridItem(MediaAsset a) => Semantics(
        button: true,
        label: _semantic(a),
        onLongPressHint: 'More actions',
        child: GestureDetector(
          onTap: () => CaptureFlows.openPreview(context, a),
          onLongPress: () => MediaActions.sheet(context, a),
          child: ExcludeSemantics(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: CaptureThumb(asset: a, favorite: _lib.isFavorite(a.uri))),
              const SizedBox(height: 6),
              Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: captureText(11.5)),
              Text(formatBytes(a.sizeBytes), style: captureText(10.5, color: AppTheme.textHint)),
            ]),
          ),
        ),
      );

  Widget _listItem(MediaAsset a) => Material(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          onTap: () => CaptureFlows.openPreview(context, a),
          onLongPress: () => MediaActions.sheet(context, a),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          leading: SizedBox(width: 56, height: 56, child: CaptureThumb(asset: a, radius: 10, favorite: _lib.isFavorite(a.uri))),
          title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: captureText(13.5, weight: FontWeight.w600)),
          subtitle: Text(
            '${formatCaptureDate(a.created)} · ${formatBytes(a.sizeBytes)}'
            '${a.isVideo && a.durationMs > 0 ? ' · ${formatDuration(Duration(milliseconds: a.durationMs))}' : ''}',
            style: captureText(12, color: AppTheme.textSecondary),
          ),
          trailing: IconButton(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary),
            onPressed: () => MediaActions.sheet(context, a),
          ),
        ),
      );
}
