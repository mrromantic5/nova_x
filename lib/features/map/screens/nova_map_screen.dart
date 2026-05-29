// lib/features/map/screens/nova_map_screen.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nova_x/core/services/map_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Custom NOVA X dark map style ─────────────────────────────────────────────
const String _kMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#07101E"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8BA7C7"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#07101E"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#1E293B"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#9AA3AF"}]},
  {"featureType":"administrative.province","elementType":"labels.text.fill","stylers":[{"color":"#9AA3AF"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#0B1A2B"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#0D1F2D"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#5D8AA8"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#091F30"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#3D8C5C"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1A2E45"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#8AACCA"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#22375A"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#1B4F72"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#00D4FF40"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#00D4FF"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#11263B"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#00D4FF"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#030D1A"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3A6B9C"}]}
]''';

enum _BottomMode { none, nearby, place, directions }
enum _TravelMode { driving, walking, cycling, transit }

class NovaMapScreen extends StatefulWidget {
  const NovaMapScreen({super.key});
  @override State<NovaMapScreen> createState() => _NovaMapScreenState();
}

class _NovaMapScreenState extends State<NovaMapScreen>
    with TickerProviderStateMixin {

  // ── Controllers & state ───────────────────────────────────────────────────
  final _searchCtrl  = TextEditingController();
  final _focusNode   = FocusNode();
  GoogleMapController? _mapCtrl;

  LatLng?          _currentLoc;
  LatLng?          _destLoc;
  Set<Marker>      _markers    = {};
  Set<Polyline>    _polylines  = {};
  MapType          _mapType    = MapType.normal;
  _BottomMode      _mode       = _BottomMode.none;
  _TravelMode      _travelMode = _TravelMode.driving;

  List<PlaceAutocomplete> _suggestions = [];
  List<NearbyPlace>       _nearby      = [];
  PlaceDetails?           _selectedPlace;
  DirectionsResult?       _directions;

  bool _locating        = false;
  bool _loadingNearby   = false;
  bool _loadingDirs     = false;
  bool _showSearch      = false;
  String _selectedCat   = 'restaurant';

  late AnimationController _fabAnim;
  late AnimationController _sheetAnim;

  final _sheetCtrl = DraggableScrollableController();

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _fabAnim   = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 400));
    _sheetAnim = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 300));
    _locateUser();
  }

  @override
  void dispose() {
    _mapCtrl?.dispose();
    _searchCtrl.dispose();
    _focusNode.dispose();
    _fabAnim.dispose();
    _sheetAnim.dispose();
    super.dispose();
  }

  // ── Location ──────────────────────────────────────────────────────────────
  Future<void> _locateUser() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        _snack('Location permission denied. Enable in Settings.');
        setState(() => _locating = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8));
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _currentLoc = loc;
        _locating   = false;
        _markers    = {
          Marker(
            markerId: const MarkerId('my_location'),
            position: loc,
            icon: BitmapDescriptor.defaultMarkerWithHue(180),
            infoWindow: const InfoWindow(title: 'You are here'),
          ),
        };
      });
      _mapCtrl?.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: loc, zoom: 15)));
      _loadNearby(_selectedCat);
    } catch (e) {
      setState(() => _locating = false);
      _snack('Could not get location: $e');
    }
  }

  // ── Nearby places ─────────────────────────────────────────────────────────
  Future<void> _loadNearby(String type) async {
    if (_currentLoc == null) return;
    setState(() { _loadingNearby = true; _selectedCat = type; });
    final places = await MapService.getNearbyPlaces(_currentLoc!, type);
    if (!mounted) return;

    // Add markers for nearby places
    final Set<Marker> m = {
      Marker(
        markerId: const MarkerId('my_location'),
        position: _currentLoc!,
        icon: BitmapDescriptor.defaultMarkerWithHue(180),
        infoWindow: const InfoWindow(title: 'You are here'),
      ),
    };
    for (final p in places) {
      m.add(Marker(
        markerId: MarkerId(p.placeId),
        position: p.location,
        icon: BitmapDescriptor.defaultMarkerWithHue(
            _catHue(_selectedCat)),
        infoWindow: InfoWindow(title: p.name, snippet: p.vicinity),
        onTap: () => _selectNearbyPlace(p),
      ));
    }
    setState(() {
      _nearby       = places;
      _markers      = m;
      _loadingNearby = false;
      _mode         = _BottomMode.nearby;
    });
  }

  // ── Search ────────────────────────────────────────────────────────────────
  Timer? _debounce;
  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final results = await MapService.searchPlaces(q,
          location: _currentLoc);
      if (mounted) setState(() => _suggestions = results);
    });
  }

  Future<void> _selectSuggestion(PlaceAutocomplete s) async {
    _focusNode.unfocus();
    setState(() { _suggestions = []; _showSearch = false; _loadingDirs = true; });
    final details = await MapService.getPlaceDetails(s.placeId,
        currentLocation: _currentLoc);
    if (!mounted) return;
    setState(() => _loadingDirs = false);
    if (details == null) { _snack('Could not load place details'); return; }
    _showPlaceDetails(details);
  }

  // ── Select place (from nearby or map tap) ─────────────────────────────────
  Future<void> _selectNearbyPlace(NearbyPlace np) async {
    setState(() => _loadingDirs = true);
    final details = await MapService.getPlaceDetails(np.placeId,
        currentLocation: _currentLoc);
    setState(() => _loadingDirs = false);
    if (details == null) return;
    _showPlaceDetails(details);
  }

  void _showPlaceDetails(PlaceDetails d) {
    setState(() {
      _selectedPlace = d;
      _mode          = _BottomMode.place;
      _destLoc       = d.location;
    });
    // Highlight on map
    final Set<Marker> m = {};
    if (_currentLoc != null) {
      m.add(Marker(
        markerId: const MarkerId('my_location'),
        position: _currentLoc!,
        icon: BitmapDescriptor.defaultMarkerWithHue(180),
        infoWindow: const InfoWindow(title: 'You are here'),
      ));
    }
    m.add(Marker(
      markerId: MarkerId(d.placeId),
      position: d.location,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(title: d.name),
    ));
    setState(() => _markers = m);
    _mapCtrl?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: d.location, zoom: 16)));
    try { _sheetCtrl.animateTo(0.45,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut); } catch (_) {}
  }

  // ── Directions ────────────────────────────────────────────────────────────
  Future<void> _getDirections({PlaceDetails? to}) async {
    final dest = to ?? _selectedPlace;
    if (_currentLoc == null || dest == null) {
      _snack('Location not available'); return;
    }
    setState(() { _loadingDirs = true; _mode = _BottomMode.directions; });

    final modeStr = switch (_travelMode) {
      _TravelMode.driving  => 'driving',
      _TravelMode.walking  => 'walking',
      _TravelMode.cycling  => 'bicycling',
      _TravelMode.transit  => 'transit',
    };

    final result = await MapService.getDirections(
      origin:      _currentLoc!,
      destination: dest.location,
      mode:        modeStr,
    );

    if (!mounted) return;
    if (result == null) {
      setState(() => _loadingDirs = false);
      _snack('No route found'); return;
    }

    final polyline = Polyline(
      polylineId: const PolylineId('route'),
      points:  result.polylinePoints,
      color:   AppTheme.accentCyan,
      width:   5,
      startCap: Cap.roundCap,
      endCap:   Cap.roundCap,
    );

    setState(() {
      _directions  = result;
      _polylines   = {polyline};
      _loadingDirs = false;
    });

    _mapCtrl?.animateCamera(
        CameraUpdate.newLatLngBounds(result.bounds, 80));

    try { _sheetCtrl.animateTo(0.5,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut); } catch (_) {}
  }

  void _clearDirections() {
    setState(() {
      _directions = null;
      _polylines  = {};
      _mode       = _selectedPlace != null
          ? _BottomMode.place : _BottomMode.nearby;
    });
  }

  // ── Map tap ───────────────────────────────────────────────────────────────
  Future<void> _onMapTap(LatLng pos) async {
    if (_showSearch) {
      setState(() { _showSearch = false; _suggestions = []; });
      _focusNode.unfocus();
      return;
    }
    final addr = await MapService.getAddressFromLocation(pos);
    if (!mounted) return;
    final Set<Marker> m = {};
    if (_currentLoc != null) {
      m.add(Marker(
        markerId: const MarkerId('my_location'),
        position: _currentLoc!,
        icon: BitmapDescriptor.defaultMarkerWithHue(180),
      ));
    }
    m.add(Marker(
      markerId: const MarkerId('tapped'),
      position: pos,
      infoWindow: InfoWindow(title: addr ?? 'Selected Location'),
    ));
    setState(() {
      _markers = m;
      _destLoc = pos;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Stack(children: [

        // ── Google Map ───────────────────────────────────────────────────────
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _currentLoc ?? const LatLng(5.603717, -0.186964), // Accra default
            zoom: _currentLoc != null ? 14 : 10,
          ),
          mapType:     _mapType,
          markers:     _markers,
          polylines:   _polylines,
          style:       _kMapStyle,
          myLocationEnabled:        false,
          myLocationButtonEnabled:  false,
          zoomControlsEnabled:      false,
          mapToolbarEnabled:        false,
          compassEnabled:           true,
          tiltGesturesEnabled:      true,
          rotateGesturesEnabled:    true,
          onMapCreated: (c) {
            _mapCtrl = c;
            _fabAnim.forward();
          },
          onTap: _onMapTap,
        ),

        // ── Safe area overlay ────────────────────────────────────────────────
        SafeArea(child: Column(children: [

          // ── Search bar ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Column(children: [
              // Main bar
              Container(
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 20, offset: const Offset(0, 4))],
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Row(children: [
                  // Back / menu button
                  IconButton(
                    icon: Icon(
                      _mode == _BottomMode.directions
                          ? Icons.arrow_back_ios_new_rounded
                          : Icons.arrow_back_ios_new_rounded,
                      color: AppTheme.textSecondary, size: 18),
                    onPressed: () {
                      if (_mode == _BottomMode.directions) {
                        _clearDirections();
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                  // Search input
                  Expanded(child: TextField(
                    controller: _searchCtrl,
                    focusNode:  _focusNode,
                    style: GoogleFonts.inter(
                        color: AppTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search NOVA Map…',
                      hintStyle: GoogleFonts.inter(
                          color: AppTheme.textHint, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) {
                      setState(() => _showSearch = v.isNotEmpty);
                      _onSearchChanged(v);
                    },
                    onTap: () => setState(() => _showSearch = true),
                  )),
                  // Clear / search icon
                  if (_searchCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          color: AppTheme.textHint, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() { _suggestions = []; _showSearch = false; });
                        _focusNode.unfocus();
                      },
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: ShaderMask(
                        shaderCallback: (r) =>
                            AppTheme.primaryGradient.createShader(r),
                        child: const Icon(Icons.search_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                ]),
              ),

              // Search suggestions
              if (_suggestions.isNotEmpty && _showSearch)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.divider),
                    boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 16)],
                  ),
                  child: Column(
                    children: _suggestions.take(6).map((s) =>
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined,
                            color: AppTheme.accentCyan, size: 18),
                        title: Text(s.mainText, style: GoogleFonts.inter(
                            color: AppTheme.textPrimary, fontSize: 13,
                            fontWeight: FontWeight.w600)),
                        subtitle: Text(s.secondaryText,
                            style: GoogleFonts.inter(
                                color: AppTheme.textHint, fontSize: 11)),
                        onTap: () => _selectSuggestion(s),
                      ),
                    ).toList(),
                  ),
                ),
            ]),
          ),
        ])),

        // ── Floating action buttons ───────────────────────────────────────────
        Positioned(right: 12, bottom: _mode == _BottomMode.none ? 24 : 360,
          child: AnimatedBuilder(
            animation: _fabAnim,
            builder: (_, __) => Column(children: [
              // Map type toggle
              _fab(Icons.layers_rounded, () {
                setState(() => _mapType = _mapType == MapType.normal
                    ? MapType.satellite : MapType.normal);
              }, AppTheme.accentPurple),
              const SizedBox(height: 10),
              // My location
              _fab(
                _locating ? Icons.gps_not_fixed_rounded : Icons.gps_fixed_rounded,
                _locating ? null : _locateUser,
                AppTheme.accentCyan,
                loading: _locating,
              ),
            ]),
          ),
        ),

        // ── Loading overlay ───────────────────────────────────────────────────
        if (_loadingDirs)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(child: CircularProgressIndicator(
                  color: AppTheme.accentCyan)),
            ),
          ),

        // ── Bottom sheet ──────────────────────────────────────────────────────
        if (_mode != _BottomMode.none)
          DraggableScrollableSheet(
            controller:      _sheetCtrl,
            initialChildSize: 0.42,
            minChildSize:    0.2,
            maxChildSize:    0.92,
            snap: true,
            snapSizes: const [0.2, 0.42, 0.7, 0.92],
            builder: (_, scroll) => Container(
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24)),
                boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 20)],
              ),
              child: Column(children: [
                // Handle
                Center(child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2)))),

                // Content
                Expanded(child: _buildBottomContent(scroll)),
              ]),
            ),
          ),
      ]),
    );
  }

  // ── Bottom sheet content ──────────────────────────────────────────────────
  Widget _buildBottomContent(ScrollController scroll) {
    switch (_mode) {
      case _BottomMode.nearby:     return _buildNearbyPanel(scroll);
      case _BottomMode.place:      return _buildPlacePanel(scroll);
      case _BottomMode.directions: return _buildDirectionsPanel(scroll);
      default:                     return const SizedBox.shrink();
    }
  }

  // ── Nearby panel ─────────────────────────────────────────────────────────
  Widget _buildNearbyPanel(ScrollController scroll) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Category chips
      SizedBox(height: 44, child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: MapService.categories.length,
        itemBuilder: (_, i) {
          final cat = MapService.categories[i];
          final sel = _selectedCat == cat.type;
          return GestureDetector(
            onTap: () => _loadNearby(cat.type),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: sel ? AppTheme.primaryGradient : null,
                color:    sel ? null : AppTheme.bgElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: sel ? Colors.transparent : AppTheme.divider),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(cat.emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 5),
                Text(cat.label, style: GoogleFonts.inter(
                    color: sel ? Colors.white : AppTheme.textSecondary,
                    fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
          );
        },
      )),
      const SizedBox(height: 12),
      // Section header
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('Nearby ${_catName(_selectedCat)}',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontSize: 15,
                fontWeight: FontWeight.w800)),
      ),
      const SizedBox(height: 8),
      // List
      Expanded(child: _loadingNearby
          ? const Center(child: CircularProgressIndicator(
              color: AppTheme.accentCyan))
          : _nearby.isEmpty
              ? _emptyState('No ${_catName(_selectedCat)} found nearby')
              : ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _nearby.length,
                  itemBuilder: (_, i) => _nearbyCard(_nearby[i]),
                )),
    ],
  );

  Widget _nearbyCard(NearbyPlace p) => GestureDetector(
    onTap: () => _selectNearbyPlace(p),
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(children: [
        Container(width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppTheme.accentCyan.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppTheme.accentCyan.withOpacity(0.2))),
          child: Icon(_catIcon(_selectedCat),
              color: AppTheme.accentCyan, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.name, style: GoogleFonts.inter(
              color: AppTheme.textPrimary, fontSize: 13,
              fontWeight: FontWeight.w700),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(p.vicinity, style: GoogleFonts.inter(
              color: AppTheme.textHint, fontSize: 11),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (p.rating != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.star_rounded,
                  color: Color(0xFFFFB300), size: 13),
              const SizedBox(width: 3),
              Text('${p.rating!.toStringAsFixed(1)}',
                  style: GoogleFonts.inter(
                      color: AppTheme.textSecondary, fontSize: 11)),
              if (p.openNow != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: (p.openNow! ? AppTheme.success : AppTheme.danger)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4)),
                  child: Text(p.openNow! ? 'Open' : 'Closed',
                      style: GoogleFonts.inter(
                          color: p.openNow! ? AppTheme.success : AppTheme.danger,
                          fontSize: 9, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ],
        ])),
        const Icon(Icons.chevron_right_rounded,
            color: AppTheme.textHint, size: 18),
      ]),
    ),
  );

  // ── Place details panel ───────────────────────────────────────────────────
  Widget _buildPlacePanel(ScrollController scroll) {
    final p = _selectedPlace;
    if (p == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Name + rating
        Text(p.name, style: GoogleFonts.spaceGrotesk(
            color: AppTheme.textPrimary, fontSize: 20,
            fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Row(children: [
          if (p.rating != null) ...[
            const Icon(Icons.star_rounded,
                color: Color(0xFFFFB300), size: 16),
            const SizedBox(width: 4),
            Text('${p.rating!.toStringAsFixed(1)}',
                style: GoogleFonts.inter(
                    color: AppTheme.textPrimary, fontSize: 13,
                    fontWeight: FontWeight.w700)),
            if (p.userRatingsTotal != null) ...[
              const SizedBox(width: 4),
              Text('(${p.userRatingsTotal})',
                  style: GoogleFonts.inter(
                      color: AppTheme.textHint, fontSize: 12)),
            ],
            const SizedBox(width: 10),
          ],
          if (p.openNow != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (p.openNow! ? AppTheme.success : AppTheme.danger)
                    .withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
              child: Text(p.openNow! ? 'Open Now' : 'Closed',
                  style: GoogleFonts.inter(
                      color: p.openNow! ? AppTheme.success : AppTheme.danger,
                      fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          if (p.distanceKm != null) ...[
            const Spacer(),
            Text('${p.distanceKm!.toStringAsFixed(1)} km',
                style: GoogleFonts.inter(
                    color: AppTheme.textHint, fontSize: 12)),
          ],
        ]),
        const SizedBox(height: 4),
        Text(p.address, style: GoogleFonts.inter(
            color: AppTheme.textHint, fontSize: 12)),
        const SizedBox(height: 16),

        // Action buttons
        Row(children: [
          _actionBtn(Icons.directions_rounded, 'Directions',
              AppTheme.accentCyan, () => _getDirections()),
          const SizedBox(width: 8),
          if (p.phoneNumber != null)
            _actionBtn(Icons.call_rounded, 'Call',
                AppTheme.success, () => _call(p.phoneNumber!)),
          const SizedBox(width: 8),
          if (p.website != null)
            _actionBtn(Icons.language_rounded, 'Website',
                AppTheme.accentPurple, () => _openWeb(p.website!)),
          const SizedBox(width: 8),
          _actionBtn(Icons.share_outlined, 'Share',
              AppTheme.warning, () => _sharePlace(p)),
        ]),
        const SizedBox(height: 16),

        // Opening hours
        if (p.openingHours != null) ...[
          _infoRow(Icons.schedule_outlined, 'Hours', p.openingHours!),
          const SizedBox(height: 10),
        ],

        // Phone
        if (p.phoneNumber != null) ...[
          _infoRow(Icons.phone_outlined, 'Phone', p.phoneNumber!),
          const SizedBox(height: 10),
        ],

        // Address
        _infoRow(Icons.place_outlined, 'Address', p.address),
      ]),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color c, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(width: 52, height: 52,
            decoration: BoxDecoration(
              color: c.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.withOpacity(0.25))),
            child: Icon(icon, color: c, size: 22)),
          const SizedBox(height: 5),
          Text(label, style: GoogleFonts.inter(
              color: AppTheme.textHint, fontSize: 10,
              fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _infoRow(IconData icon, String label, String value) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppTheme.accentCyan, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inter(
              color: AppTheme.textHint, fontSize: 10,
              fontWeight: FontWeight.w700)),
          Text(value, style: GoogleFonts.inter(
              color: AppTheme.textSecondary, fontSize: 12, height: 1.5)),
        ])),
      ]);

  // ── Directions panel ──────────────────────────────────────────────────────
  Widget _buildDirectionsPanel(ScrollController scroll) => Column(
    children: [
      // Travel mode selector
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: _TravelMode.values.map((m) {
          final sel = _travelMode == m;
          return Expanded(child: GestureDetector(
            onTap: () {
              setState(() => _travelMode = m);
              if (_selectedPlace != null) _getDirections();
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                gradient: sel ? AppTheme.primaryGradient : null,
                color:    sel ? null : AppTheme.bgElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: sel ? Colors.transparent : AppTheme.divider)),
              child: Column(children: [
                Icon(_travelIcon(m),
                    color: sel ? Colors.white : AppTheme.textHint, size: 20),
                const SizedBox(height: 2),
                Text(_travelLabel(m), style: GoogleFonts.inter(
                    color: sel ? Colors.white : AppTheme.textHint,
                    fontSize: 9, fontWeight: FontWeight.w700)),
              ]),
            ),
          ));
        }).toList()),
      ),
      const SizedBox(height: 12),

      // Route summary
      if (_directions != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.accentCyan.withOpacity(0.08),
                         AppTheme.accentPurple.withOpacity(0.05)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppTheme.accentCyan.withOpacity(0.25))),
            child: Row(children: [
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_directions!.distance, style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.accentCyan, fontSize: 22,
                    fontWeight: FontWeight.w900)),
                Text(_directions!.durationInTraffic.isNotEmpty
                    ? _directions!.durationInTraffic
                    : _directions!.duration,
                    style: GoogleFonts.inter(
                        color: AppTheme.textPrimary, fontSize: 14,
                        fontWeight: FontWeight.w700)),
                if (_directions!.summary.isNotEmpty)
                  Text('via ${_directions!.summary}',
                      style: GoogleFonts.inter(
                          color: AppTheme.textHint, fontSize: 11)),
              ])),
              GestureDetector(
                onTap: _clearDirections,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppTheme.danger.withOpacity(0.3))),
                  child: const Icon(Icons.close_rounded,
                      color: AppTheme.danger, size: 18),
                ),
              ),
            ]),
          ),
        ),
      const SizedBox(height: 12),

      // Steps
      if (_directions != null)
        Expanded(child: ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: _directions!.steps.length,
          itemBuilder: (_, i) {
            final s = _directions!.steps[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.accentCyan.withOpacity(0.1),
                    shape: BoxShape.circle),
                  child: Center(child: Text('${i+1}',
                      style: GoogleFonts.spaceGrotesk(
                          color: AppTheme.accentCyan, fontSize: 11,
                          fontWeight: FontWeight.w900)))),
                const SizedBox(width: 10),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.plainInstruction, style: GoogleFonts.inter(
                      color: AppTheme.textPrimary, fontSize: 12,
                      fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text('${s.distance}  ·  ${s.duration}',
                      style: GoogleFonts.inter(
                          color: AppTheme.textHint, fontSize: 10)),
                ])),
              ]),
            );
          },
        ))
      else if (_loadingDirs)
        const Expanded(child: Center(child: CircularProgressIndicator(
            color: AppTheme.accentCyan)))
      else
        const Expanded(child: Center(child: Text('Calculating route…'))),
    ],
  );

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _fab(IconData icon, VoidCallback? onTap, Color color,
      {bool loading = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color:  AppTheme.bgCard,
            shape:  BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.3)),
            boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.4), blurRadius: 12)],
          ),
          child: loading
              ? SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: color))
              : Icon(icon, color: color, size: 20),
        ),
      );

  Widget _emptyState(String text) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.search_off_rounded,
          color: AppTheme.textHint, size: 48),
      const SizedBox(height: 12),
      Text(text, style: GoogleFonts.inter(
          color: AppTheme.textHint, fontSize: 14)),
    ],
  ));

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg,
        style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12))));

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  Future<void> _openWeb(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _sharePlace(PlaceDetails p) {
    final text = '${p.name}\n${p.address}\nhttps://www.google.com/maps/search/'
        '?api=1&query=${p.location.latitude},${p.location.longitude}';
    // Share via system share sheet
    // Clipboard fallback
    Clipboard.setData(ClipboardData(text: text));
    _snack('Location copied to clipboard');
  }

  String _catName(String type) => MapService.categories
      .firstWhere((c) => c.type == type,
          orElse: () => const PlaceCategory(
              type: '', label: 'Places', emoji: ''))
      .label;

  IconData _catIcon(String type) => switch (type) {
    'restaurant'  => Icons.restaurant_rounded,
    'hospital'    => Icons.local_hospital_rounded,
    'bank'        => Icons.account_balance_rounded,
    'gas_station' => Icons.local_gas_station_rounded,
    'hotel'       => Icons.hotel_rounded,
    'pharmacy'    => Icons.local_pharmacy_rounded,
    'supermarket' => Icons.shopping_cart_rounded,
    'atm'         => Icons.atm_rounded,
    'police'      => Icons.local_police_rounded,
    'school'      => Icons.school_rounded,
    _             => Icons.place_rounded,
  };

  double _catHue(String type) => switch (type) {
    'restaurant'  => BitmapDescriptor.hueOrange,
    'hospital'    => BitmapDescriptor.hueRed,
    'bank'        => BitmapDescriptor.hueAzure,
    'gas_station' => BitmapDescriptor.hueYellow,
    'hotel'       => BitmapDescriptor.hueViolet,
    'pharmacy'    => BitmapDescriptor.hueGreen,
    _             => BitmapDescriptor.hueCyan,
  };

  IconData _travelIcon(_TravelMode m) => switch (m) {
    _TravelMode.driving  => Icons.directions_car_rounded,
    _TravelMode.walking  => Icons.directions_walk_rounded,
    _TravelMode.cycling  => Icons.directions_bike_rounded,
    _TravelMode.transit  => Icons.directions_transit_rounded,
  };

  String _travelLabel(_TravelMode m) => switch (m) {
    _TravelMode.driving  => 'Drive',
    _TravelMode.walking  => 'Walk',
    _TravelMode.cycling  => 'Cycle',
    _TravelMode.transit  => 'Transit',
  };
}
