// lib/features/map/screens/nova_map_screen.dart
// NOVA Map v2 — Premium Google Maps Experience
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nova_x/core/services/map_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';

// ── Map styles ────────────────────────────────────────────────────────────────
const String _kDarkStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#07101E"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8BA7C7"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#07101E"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#1E293B"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#0B1A2B"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#0D1F2D"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#091F30"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#3D8C5C"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1A2E45"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#8AACCA"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#22375A"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#1B4F72"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#00D4FF"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#11263B"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#00D4FF"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#030D1A"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3A6B9C"}]}
]''';

const String _kLightStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#F8FAFC"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#334155"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#FFFFFF"}]},
  {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#CBD5E1"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#F1F5F9"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#E2E8F0"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#DCFCE7"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#16A34A"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#FFFFFF"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#E2E8F0"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#475569"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#F8FAFC"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#BFDBFE"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#1D4ED8"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#E0E7FF"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#4F46E5"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#BFDBFE"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#1D4ED8"}]}
]''';

enum _BottomMode { none, nearby, place, directions }
enum _TravelMode { driving, walking, cycling, transit }

class NovaMapScreen extends StatefulWidget {
  const NovaMapScreen({super.key});
  @override State<NovaMapScreen> createState() => _NovaMapScreenState();
}

class _NovaMapScreenState extends State<NovaMapScreen>
    with TickerProviderStateMixin {

  // ── Controllers ───────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  final _focusNode  = FocusNode();
  GoogleMapController? _mapCtrl;
  final _sheetCtrl  = DraggableScrollableController();
  final _speech     = SpeechToText();
  final _dio        = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
    validateStatus: (_) => true,
  ));

  // ── State ─────────────────────────────────────────────────────────────────
  LatLng?      _currentLoc;
  Set<Marker>  _markers   = {};
  Set<Polyline>_polylines = {};
  MapType      _mapType   = MapType.normal;
  _BottomMode  _mode      = _BottomMode.none;
  _TravelMode  _travelMode= _TravelMode.driving;
  bool         _darkMode  = true;

  List<PlaceAutocomplete> _suggestions = [];
  List<NearbyPlace>       _nearby      = [];
  PlaceDetails?           _selectedPlace;
  DirectionsResult?       _directions;

  bool   _locating      = false;
  bool   _loadingNearby = false;
  bool   _loadingDirs   = false;
  bool   _showSearch    = false;
  bool   _listening     = false;
  bool   _speechReady   = false;
  String _selectedCat   = 'restaurant';

  late AnimationController _fabAnim;

  @override
  void initState() {
    super.initState();
    _fabAnim = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 400));
    _initSpeech();
    _ipLocateFirst();
  }

  @override
  void dispose() {
    _mapCtrl?.dispose();
    _searchCtrl.dispose();
    _focusNode.dispose();
    _fabAnim.dispose();
    _sheetCtrl.dispose();
    super.dispose();
  }

  // ── Speech ────────────────────────────────────────────────────────────────
  Future<void> _initSpeech() async {
    _speechReady = await _speech.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    if (!_speechReady) { _snack('Microphone not available'); return; }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        _searchCtrl.text = r.recognizedWords;
        _onSearchChanged(r.recognizedWords);
        if (r.finalResult) setState(() => _listening = false);
      },
      listenFor: const Duration(seconds: 10),
      localeId: 'en_US',
    );
  }

  // ── IP + GPS location ─────────────────────────────────────────────────────
  Future<void> _ipLocateFirst() async {
    try {
      final r = await _dio.get('http://ip-api.com/json',
          options: Options(receiveTimeout: const Duration(seconds: 4)));
      final d = r.data as Map<String, dynamic>?;
      if (d != null && d['status'] == 'success' && _currentLoc == null) {
        final loc = LatLng(
            (d['lat'] as num).toDouble(), (d['lon'] as num).toDouble());
        if (mounted) {
          setState(() => _currentLoc = loc);
          _mapCtrl?.animateCamera(CameraUpdate.newCameraPosition(
              CameraPosition(target: loc, zoom: 12)));
        }
      }
    } catch (_) {}
    _locateUser();
  }

  Future<void> _locateUser() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        setState(() => _locating = false);
        _snack('Enable location in Settings for precise navigation.');
        if (_currentLoc != null) _loadNearby(_selectedCat);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final loc = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _currentLoc = loc;
        _locating   = false;
        _markers    = {Marker(
          markerId: const MarkerId('my_location'),
          position: loc,
          icon: BitmapDescriptor.defaultMarkerWithHue(180),
          infoWindow: const InfoWindow(title: 'You are here'),
        )};
      });
      _mapCtrl?.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: loc, zoom: 15)));
      _loadNearby(_selectedCat);
    } catch (_) {
      setState(() => _locating = false);
      if (_currentLoc != null) _loadNearby(_selectedCat);
    }
  }

  // ── Nearby ────────────────────────────────────────────────────────────────
  Future<void> _loadNearby(String type) async {
    if (_currentLoc == null) return;
    setState(() { _loadingNearby = true; _selectedCat = type;
                  _mode = _BottomMode.nearby; });
    final places = await MapService.getNearbyPlaces(
        _currentLoc!, type, currentLoc: _currentLoc);
    if (!mounted) return;
    final Set<Marker> m = {Marker(
      markerId: const MarkerId('my_location'),
      position: _currentLoc!,
      icon: BitmapDescriptor.defaultMarkerWithHue(180),
    )};
    for (final p in places) {
      m.add(Marker(
        markerId: MarkerId(p.placeId),
        position: p.location,
        icon: BitmapDescriptor.defaultMarkerWithHue(_catHue(_selectedCat)),
        infoWindow: InfoWindow(title: p.name, snippet: p.vicinity),
        onTap: () => _selectNearbyPlace(p),
      ));
    }
    setState(() { _nearby = places; _markers = m; _loadingNearby = false; });
    try { _sheetCtrl.animateTo(0.42,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut); } catch (_) {}
  }

  // ── Search ────────────────────────────────────────────────────────────────
  Timer? _debounce;
  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) { setState(() => _suggestions = []); return; }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final r = await MapService.searchPlaces(q, location: _currentLoc);
      if (mounted) setState(() => _suggestions = r);
    });
  }

  Future<void> _selectSuggestion(PlaceAutocomplete s) async {
    _focusNode.unfocus();
    setState(() { _suggestions = []; _showSearch = false; _loadingDirs = true; });
    final d = await MapService.getPlaceDetails(s.placeId,
        currentLocation: _currentLoc);
    setState(() => _loadingDirs = false);
    if (d == null) { _snack('Could not load place'); return; }
    _showPlaceDetails(d);
  }

  Future<void> _selectNearbyPlace(NearbyPlace np) async {
    setState(() => _loadingDirs = true);
    final d = await MapService.getPlaceDetails(np.placeId,
        currentLocation: _currentLoc);
    setState(() => _loadingDirs = false);
    if (d == null) return;
    _showPlaceDetails(d);
  }

  void _showPlaceDetails(PlaceDetails d) {
    final Set<Marker> m = {};
    if (_currentLoc != null) m.add(Marker(
      markerId: const MarkerId('my_location'),
      position: _currentLoc!,
      icon: BitmapDescriptor.defaultMarkerWithHue(180),
    ));
    m.add(Marker(
      markerId: MarkerId(d.placeId),
      position: d.location,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(title: d.name),
    ));
    setState(() { _selectedPlace = d; _mode = _BottomMode.place; _markers = m; });
    _mapCtrl?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: d.location, zoom: 16)));
    try { _sheetCtrl.animateTo(0.55,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut); } catch (_) {}
  }

  // ── Directions ────────────────────────────────────────────────────────────
  Future<void> _getDirections() async {
    final dest = _selectedPlace;
    if (_currentLoc == null || dest == null) { _snack('Location unavailable'); return; }
    setState(() { _loadingDirs = true; _mode = _BottomMode.directions; });
    final modeStr = switch (_travelMode) {
      _TravelMode.driving  => 'driving',
      _TravelMode.walking  => 'walking',
      _TravelMode.cycling  => 'bicycling',
      _TravelMode.transit  => 'transit',
    };
    final result = await MapService.getDirections(
        origin: _currentLoc!, destination: dest.location, mode: modeStr);
    if (!mounted) return;
    if (result == null) {
      setState(() => _loadingDirs = false);
      _snack('No route found'); return;
    }
    setState(() {
      _directions = result;
      _loadingDirs = false;
      _polylines   = {Polyline(
        polylineId: const PolylineId('route'),
        points: result.polylinePoints,
        color: AppTheme.accentCyan,
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      )};
    });
    _mapCtrl?.animateCamera(
        CameraUpdate.newLatLngBounds(result.bounds, 80));
    try { _sheetCtrl.animateTo(0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut); } catch (_) {}
  }

  void _clearDirections() {
    setState(() { _directions = null; _polylines = {};
      _mode = _selectedPlace != null ? _BottomMode.place : _BottomMode.nearby; });
  }

  Future<void> _onMapTap(LatLng pos) async {
    if (_showSearch) {
      setState(() { _showSearch = false; _suggestions = []; });
      _focusNode.unfocus(); return;
    }
    final addr = await MapService.getAddressFromLocation(pos);
    if (!mounted) return;
    setState(() {
      _markers = {
        if (_currentLoc != null) Marker(
          markerId: const MarkerId('my_location'),
          position: _currentLoc!,
          icon: BitmapDescriptor.defaultMarkerWithHue(180),
        ),
        Marker(
          markerId: const MarkerId('tapped'),
          position: pos,
          infoWindow: InfoWindow(title: addr ?? 'Selected Location'),
        ),
      };
    });
  }

  // ── DARK/LIGHT helpers ────────────────────────────────────────────────────
  Color get _bg       => _darkMode ? AppTheme.bgCard : Colors.white;
  Color get _bg2      => _darkMode ? AppTheme.bgElevated : const Color(0xFFF8FAFC);
  Color get _textPri  => _darkMode ? AppTheme.textPrimary : const Color(0xFF0F172A);
  Color get _textSec  => _darkMode ? AppTheme.textSecondary : const Color(0xFF475569);
  Color get _textHint => _darkMode ? AppTheme.textHint : const Color(0xFF94A3B8);
  Color get _divider  => _darkMode ? AppTheme.divider : const Color(0xFFE2E8F0);

  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkMode ? AppTheme.bgDark : const Color(0xFFF1F5F9),
      body: Stack(children: [

        // ── Google Map ─────────────────────────────────────────────────────
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _currentLoc ?? const LatLng(0, 20),
            zoom: _currentLoc != null ? 14 : 2,
          ),
          mapType:     _mapType,
          markers:     _markers,
          polylines:   _polylines,
          style:       _darkMode ? _kDarkStyle : _kLightStyle,
          myLocationEnabled:       false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled:     false,
          mapToolbarEnabled:       false,
          compassEnabled:          true,
          trafficEnabled:          _travelMode == _TravelMode.driving,
          onMapCreated: (c) { _mapCtrl = c; _fabAnim.forward(); },
          onTap: _onMapTap,
        ),

        // ── Safe area overlay ──────────────────────────────────────────────
        SafeArea(child: Column(children: [

          // ── Search bar ───────────────────────────────────────────────────
          Padding(padding: const EdgeInsets.fromLTRB(12,10,12,0),
            child: Column(children: [

              // Search bar container
              Container(
                height: 54,
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(
                      _darkMode ? 0.4 : 0.1),
                      blurRadius: 16, offset: const Offset(0, 4))],
                  border: Border.all(color: _divider),
                ),
                child: Row(children: [
                  // Back
                  IconButton(icon: Icon(Icons.arrow_back_ios_new_rounded,
                      color: _textSec, size: 17),
                    onPressed: () {
                      if (_mode == _BottomMode.directions) _clearDirections();
                      else Navigator.pop(context);
                    },
                  ),
                  // Search input
                  Expanded(child: TextField(
                    controller: _searchCtrl,
                    focusNode:  _focusNode,
                    style: GoogleFonts.inter(color: _textPri, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search NOVA Map…',
                      hintStyle: GoogleFonts.inter(color: _textHint, fontSize: 13),
                      border: InputBorder.none, isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) { setState(() => _showSearch = v.isNotEmpty);
                      _onSearchChanged(v); },
                    onTap: () => setState(() => _showSearch = true),
                  )),
                  // Voice search
                  GestureDetector(
                    onTap: _toggleVoice,
                    child: Container(
                      width: 36, height: 36, margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: _listening
                            ? AppTheme.accentCyan.withOpacity(0.15)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: _listening ? AppTheme.accentCyan : _textHint,
                        size: 20,
                      ),
                    ),
                  ),
                  // Clear/search
                  if (_searchCtrl.text.isNotEmpty)
                    IconButton(icon: Icon(Icons.clear_rounded,
                        color: _textHint, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() { _suggestions = []; _showSearch = false; });
                        _focusNode.unfocus();
                      },
                    )
                  else
                    Padding(padding: const EdgeInsets.only(right: 12),
                      child: Icon(Icons.search_rounded,
                          color: AppTheme.accentCyan, size: 20)),
                ]),
              ),

              // Listening indicator
              if (_listening)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentCyan.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.accentCyan.withOpacity(0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.mic_rounded, color: AppTheme.accentCyan, size: 14),
                    const SizedBox(width: 6),
                    Text('Listening…', style: GoogleFonts.inter(
                        color: AppTheme.accentCyan, fontSize: 12)),
                  ]),
                ),

              // Suggestions dropdown
              if (_suggestions.isNotEmpty && _showSearch)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _divider),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.3), blurRadius: 16)],
                  ),
                  child: Column(children: _suggestions.take(6).map((s) =>
                    InkWell(
                      onTap: () => _selectSuggestion(s),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                        child: Row(children: [
                          Container(width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: AppTheme.accentCyan.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.place_outlined,
                                color: AppTheme.accentCyan, size: 16)),
                          const SizedBox(width: 10),
                          Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(s.mainText, style: GoogleFonts.inter(
                                color: _textPri, fontSize: 13,
                                fontWeight: FontWeight.w600),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(s.secondaryText, style: GoogleFonts.inter(
                                color: _textHint, fontSize: 11),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ])),
                        ]),
                      ),
                    ),
                  ).toList()),
                ),
            ]),
          ),
        ])),

        // ── FABs ──────────────────────────────────────────────────────────
        Positioned(right: 12, bottom: _mode != _BottomMode.none ? 380 : 24,
          child: Column(children: [
            // Dark/light toggle
            _fab(_darkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              () => setState(() => _darkMode = !_darkMode),
              _darkMode ? Colors.amber : AppTheme.accentPurple),
            const SizedBox(height: 10),
            // Satellite toggle
            _fab(Icons.layers_rounded,
              () => setState(() => _mapType =
                  _mapType == MapType.normal ? MapType.satellite : MapType.normal),
              AppTheme.accentCyan),
            const SizedBox(height: 10),
            // My location
            _fab(_locating ? Icons.gps_not_fixed_rounded : Icons.gps_fixed_rounded,
              _locating ? null : _locateUser,
              _locating ? _textHint : AppTheme.success,
              loading: _locating),
          ]),
        ),

        // ── Loading overlay ────────────────────────────────────────────────
        if (_loadingDirs)
          Container(color: Colors.black38,
            child: const Center(child: CircularProgressIndicator(
                color: AppTheme.accentCyan))),

        // ── Bottom sheet ───────────────────────────────────────────────────
        if (_mode != _BottomMode.none)
          DraggableScrollableSheet(
            controller:       _sheetCtrl,
            initialChildSize: 0.42,
            minChildSize:     0.18,
            maxChildSize:     0.92,
            snap: true,
            snapSizes: const [0.18, 0.42, 0.65, 0.92],
            builder: (_, scroll) => Container(
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3),
                    blurRadius: 20)],
              ),
              child: Column(children: [
                // Handle
                Center(child: Container(
                  width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: _divider,
                      borderRadius: BorderRadius.circular(2)))),
                Expanded(child: _buildSheet(scroll)),
              ]),
            ),
          ),
      ]),
    );
  }

  // ── Sheet router ──────────────────────────────────────────────────────────
  Widget _buildSheet(ScrollController s) {
    switch (_mode) {
      case _BottomMode.nearby:     return _nearbyPanel(s);
      case _BottomMode.place:      return _placePanel(s);
      case _BottomMode.directions: return _directionsPanel(s);
      default:                     return const SizedBox.shrink();
    }
  }

  // ── Nearby panel ──────────────────────────────────────────────────────────
  Widget _nearbyPanel(ScrollController s) => Column(children: [
    // Category chips
    SizedBox(height: 48, child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      itemCount: MapService.categories.length,
      itemBuilder: (_, i) {
        final c = MapService.categories[i];
        final sel = _selectedCat == c.type;
        return GestureDetector(
          onTap: () => _loadNearby(c.type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: sel ? AppTheme.primaryGradient : null,
              color: sel ? null : _bg2,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: sel ? Colors.transparent : _divider),
              boxShadow: sel ? AppTheme.glowShadow : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(c.emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Text(c.label, style: GoogleFonts.inter(
                  color: sel ? Colors.white : _textSec,
                  fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        );
      },
    )),
    const SizedBox(height: 10),
    // Header
    Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Text('Nearby ${_catLabel(_selectedCat)}',
            style: GoogleFonts.spaceGrotesk(color: _textPri,
                fontSize: 16, fontWeight: FontWeight.w800)),
        const Spacer(),
        if (_nearby.isNotEmpty)
          Text('${_nearby.length} found', style: GoogleFonts.inter(
              color: _textHint, fontSize: 11)),
      ]),
    ),
    const SizedBox(height: 8),
    // List
    Expanded(child: _loadingNearby
        ? Center(child: CircularProgressIndicator(color: AppTheme.accentCyan))
        : _nearby.isEmpty
            ? _emptyState('No ${_catLabel(_selectedCat)} found nearby')
            : ListView.builder(
                controller: s,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                itemCount: _nearby.length,
                itemBuilder: (_, i) => _nearbyCard(_nearby[i]),
              )),
  ]);

  Widget _nearbyCard(NearbyPlace p) => GestureDetector(
    onTap: () => _selectNearbyPlace(p),
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Photo
        ClipRRect(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
          child: SizedBox(width: 90, height: 90,
            child: p.photoRef != null
                ? Image.network(
                    MapService.getPhotoUrl(p.photoRef!, maxWidth: 200),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _photoPlaceholder(_catIcon(_selectedCat)),
                    loadingBuilder: (_, child, loading) => loading == null ? child
                        : Container(color: _divider, child: const Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.accentCyan))),
                  )
                : _photoPlaceholder(_catIcon(_selectedCat)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: GoogleFonts.inter(color: _textPri,
                fontSize: 13, fontWeight: FontWeight.w700),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(p.vicinity, style: GoogleFonts.inter(color: _textHint, fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Row(children: [
              if (p.rating != null) ...[
                const Icon(Icons.star_rounded, color: Color(0xFFFFB300), size: 13),
                const SizedBox(width: 3),
                Text('${p.rating!.toStringAsFixed(1)}', style: GoogleFonts.inter(
                    color: _textSec, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
              ],
              if (p.openNow != null)
                _statusBadge(p.openNow!),
              if (p.distanceKm != null) ...[
                const Spacer(),
                Text(p.distanceKm! < 1
                    ? '${(p.distanceKm! * 1000).round()}m'
                    : '${p.distanceKm!.toStringAsFixed(1)}km',
                    style: GoogleFonts.inter(
                        color: AppTheme.accentCyan, fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ],
            ]),
          ]),
        )),
        const Padding(
          padding: EdgeInsets.only(right: 10, top: 35),
          child: Icon(Icons.chevron_right_rounded,
              color: AppTheme.textHint, size: 18),
        ),
      ]),
    ),
  );

  // ── Place details panel ───────────────────────────────────────────────────
  Widget _placePanel(ScrollController s) {
    final p = _selectedPlace;
    if (p == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      controller: s,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Photo hero
        if (p.photoRef != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 180, width: double.infinity,
              child: Image.network(
                MapService.getPhotoUrl(p.photoRef!, maxWidth: 800),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 180, color: _bg2,
                  child: Icon(Icons.image_not_supported_outlined,
                      color: _textHint, size: 40)),
              ),
            ),
          ),
        const SizedBox(height: 14),

        // Name + status
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(p.name, style: GoogleFonts.spaceGrotesk(
              color: _textPri, fontSize: 20, fontWeight: FontWeight.w800))),
          if (p.openNow != null) ...[
            const SizedBox(width: 8),
            _statusBadge(p.openNow!),
          ],
        ]),
        const SizedBox(height: 6),

        // Rating + distance
        Row(children: [
          if (p.rating != null) ...[
            ...List.generate(5, (i) => Icon(
              i < p.rating!.round() ? Icons.star_rounded : Icons.star_outline_rounded,
              color: const Color(0xFFFFB300), size: 15)),
            const SizedBox(width: 6),
            Text('${p.rating!.toStringAsFixed(1)}', style: GoogleFonts.inter(
                color: _textPri, fontSize: 13, fontWeight: FontWeight.w700)),
            if (p.userRatingsTotal != null) ...[
              const SizedBox(width: 4),
              Text('(${p.userRatingsTotal})', style: GoogleFonts.inter(
                  color: _textHint, fontSize: 12)),
            ],
          ],
          const Spacer(),
          if (p.distanceKm != null)
            Text(p.distanceKm! < 1
                ? '${(p.distanceKm! * 1000).round()} m away'
                : '${p.distanceKm!.toStringAsFixed(1)} km away',
                style: GoogleFonts.inter(color: AppTheme.accentCyan,
                    fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Text(p.address, style: GoogleFonts.inter(color: _textHint, fontSize: 12)),
        const SizedBox(height: 16),

        // Action buttons row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _actionBtn(Icons.directions_rounded, 'Directions',
                AppTheme.accentCyan, _getDirections),
            const SizedBox(width: 10),
            if (p.phoneNumber != null)
              _actionBtn(Icons.call_rounded, 'Call',
                  AppTheme.success, () => _call(p.phoneNumber!)),
            if (p.phoneNumber != null) const SizedBox(width: 10),
            if (p.website != null)
              _actionBtn(Icons.language_rounded, 'Website',
                  AppTheme.accentPurple, () => _openWeb(p.website!)),
            if (p.website != null) const SizedBox(width: 10),
            _actionBtn(Icons.share_outlined, 'Share',
                AppTheme.warning, () => _sharePlace(p)),
            const SizedBox(width: 10),
            _actionBtn(Icons.open_in_new_rounded, 'Google Maps',
                const Color(0xFF4285F4),
                () => _openInGoogleMaps(p.location)),
          ]),
        ),
        const SizedBox(height: 16),

        // Info section
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _bg2, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _divider)),
          child: Column(children: [
            if (p.phoneNumber != null) ...[
              _infoRow(Icons.phone_outlined, 'Phone', p.phoneNumber!),
              Divider(color: _divider, height: 16),
            ],
            _infoRow(Icons.place_outlined, 'Address', p.address),
            if (p.openingHours != null) ...[
              Divider(color: _divider, height: 16),
              _infoRow(Icons.schedule_outlined, 'Hours', p.openingHours!),
            ],
            if (p.website != null) ...[
              Divider(color: _divider, height: 16),
              _infoRow(Icons.language_outlined, 'Website',
                  p.website!.replaceAll('https://', '').replaceAll('http://', '')),
            ],
          ]),
        ),
      ]),
    );
  }

  // ── Directions panel ──────────────────────────────────────────────────────
  Widget _directionsPanel(ScrollController s) => Column(children: [
    // Travel mode tabs
    Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: _bg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _divider)),
        child: Row(children: _TravelMode.values.map((m) {
          final sel = _travelMode == m;
          return Expanded(child: GestureDetector(
            onTap: () { setState(() => _travelMode = m); _getDirections(); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                gradient: sel ? AppTheme.primaryGradient : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(children: [
                Icon(_modeIcon(m), color: sel ? Colors.white : _textHint, size: 20),
                const SizedBox(height: 2),
                Text(_modeLabel(m), style: GoogleFonts.inter(
                    color: sel ? Colors.white : _textHint,
                    fontSize: 9, fontWeight: FontWeight.w700)),
              ]),
            ),
          ));
        }).toList()),
      ),
    ),
    const SizedBox(height: 12),

    // Route summary card
    if (_directions != null) ...[
      Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              AppTheme.accentCyan.withOpacity(0.08),
              AppTheme.accentPurple.withOpacity(0.05),
            ]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.accentCyan.withOpacity(0.3)),
          ),
          child: Row(children: [
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_directions!.distance, style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.accentCyan, fontSize: 26,
                  fontWeight: FontWeight.w900)),
              Text(_directions!.durationInTraffic.isNotEmpty
                  ? _directions!.durationInTraffic
                  : _directions!.duration,
                  style: GoogleFonts.inter(color: _textPri,
                      fontSize: 14, fontWeight: FontWeight.w700)),
              if (_directions!.summary.isNotEmpty)
                Text('via ${_directions!.summary}', style: GoogleFonts.inter(
                    color: _textHint, fontSize: 11)),
            ])),
            GestureDetector(
              onTap: _clearDirections,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.danger.withOpacity(0.3))),
                child: const Icon(Icons.close_rounded,
                    color: AppTheme.danger, size: 18),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 10),

      // Steps
      Expanded(child: ListView.builder(
        controller: s,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
        itemCount: _directions!.steps.length,
        itemBuilder: (_, i) {
          final step = _directions!.steps[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _bg2, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _divider)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 30, height: 30,
                decoration: BoxDecoration(
                  color: AppTheme.accentCyan.withOpacity(0.1),
                  shape: BoxShape.circle),
                child: Center(child: Icon(
                    _maneuverIcon(step.maneuver),
                    color: AppTheme.accentCyan, size: 14))),
              const SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(step.plainInstruction, style: GoogleFonts.inter(
                    color: _textPri, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text('${step.distance}  ·  ${step.duration}',
                    style: GoogleFonts.inter(color: _textHint, fontSize: 10)),
              ])),
            ]),
          );
        },
      )),
    ] else if (_loadingDirs)
      const Expanded(child: Center(child: CircularProgressIndicator(
          color: AppTheme.accentCyan)))
    else
      Expanded(child: _emptyState('Select destination to get directions')),
  ]);

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _fab(IconData icon, VoidCallback? onTap, Color color,
      {bool loading = false}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          color: _bg, shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.35)),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.3), blurRadius: 10)],
        ),
        child: loading
            ? Center(child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: color)))
            : Icon(icon, color: color, size: 20),
      ),
    );

  Widget _actionBtn(IconData icon, String label, Color c, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(width: 54, height: 54,
          decoration: BoxDecoration(
            color: c.withOpacity(0.1),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: c.withOpacity(0.25))),
          child: Icon(icon, color: c, size: 22)),
        const SizedBox(height: 5),
        Text(label, style: GoogleFonts.inter(
            color: _textHint, fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
    );

  Widget _infoRow(IconData icon, String label, String val) =>
    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: AppTheme.accentCyan, size: 15),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.inter(
            color: _textHint, fontSize: 10, fontWeight: FontWeight.w700)),
        Text(val, style: GoogleFonts.inter(color: _textSec, fontSize: 12, height: 1.5)),
      ])),
    ]);

  Widget _statusBadge(bool open) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: (open ? AppTheme.success : AppTheme.danger).withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
          color: (open ? AppTheme.success : AppTheme.danger).withOpacity(0.3))),
    child: Text(open ? 'Open' : 'Closed', style: GoogleFonts.inter(
        color: open ? AppTheme.success : AppTheme.danger,
        fontSize: 10, fontWeight: FontWeight.w700)),
  );

  Widget _photoPlaceholder(IconData icon) => Container(
    color: _bg2,
    child: Center(child: Icon(icon, color: _textHint, size: 28)),
  );

  Widget _emptyState(String t) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.search_off_rounded, color: _textHint, size: 48),
      const SizedBox(height: 12),
      Text(t, style: GoogleFonts.inter(color: _textHint, fontSize: 13)),
    ],
  ));

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(m, style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));

  Future<void> _call(String phone) async {
    final u = Uri.parse('tel:$phone');
    if (await canLaunchUrl(u)) launchUrl(u);
  }

  Future<void> _openWeb(String url) async {
    final u = Uri.parse(url);
    if (await canLaunchUrl(u)) launchUrl(u, mode: LaunchMode.externalApplication);
  }

  Future<void> _openInGoogleMaps(LatLng loc) async {
    final url = 'https://www.google.com/maps/search/?api=1&query=${loc.latitude},${loc.longitude}';
    final u = Uri.parse(url);
    if (await canLaunchUrl(u)) launchUrl(u, mode: LaunchMode.externalApplication);
  }

  void _sharePlace(PlaceDetails p) {
    final text = '${p.name}\n${p.address}\n'
        'https://www.google.com/maps/search/?api=1'
        '&query=${p.location.latitude},${p.location.longitude}';
    Clipboard.setData(ClipboardData(text: text));
    _snack('📋 Location copied to clipboard');
  }

  String _catLabel(String type) {
    final cat = MapService.categories.where((c) => c.type == type);
    return cat.isNotEmpty ? cat.first.label : 'Places';
  }

  IconData _catIcon(String type) => switch (type) {
    'restaurant'   => Icons.restaurant_rounded,
    'hospital'     => Icons.local_hospital_rounded,
    'bank'         => Icons.account_balance_rounded,
    'gas_station'  => Icons.local_gas_station_rounded,
    'lodging'      => Icons.hotel_rounded,
    'pharmacy'     => Icons.local_pharmacy_rounded,
    'supermarket'  => Icons.shopping_cart_rounded,
    'atm'          => Icons.atm_rounded,
    'police'       => Icons.local_police_rounded,
    'school'       => Icons.school_rounded,
    'cafe'         => Icons.coffee_rounded,
    'shopping_mall'=> Icons.shopping_bag_rounded,
    'church'       => Icons.church_rounded,
    'mosque'       => Icons.mosque_rounded,
    'parking'      => Icons.local_parking_rounded,
    _              => Icons.place_rounded,
  };

  double _catHue(String type) => switch (type) {
    'restaurant'   => BitmapDescriptor.hueOrange,
    'hospital'     => BitmapDescriptor.hueRed,
    'bank'         => BitmapDescriptor.hueAzure,
    'gas_station'  => BitmapDescriptor.hueYellow,
    'lodging'      => BitmapDescriptor.hueViolet,
    'pharmacy'     => BitmapDescriptor.hueGreen,
    'cafe'         => BitmapDescriptor.hueOrange,
    _              => BitmapDescriptor.hueCyan,
  };

  IconData _modeIcon(_TravelMode m) => switch (m) {
    _TravelMode.driving  => Icons.directions_car_rounded,
    _TravelMode.walking  => Icons.directions_walk_rounded,
    _TravelMode.cycling  => Icons.directions_bike_rounded,
    _TravelMode.transit  => Icons.directions_transit_rounded,
  };

  String _modeLabel(_TravelMode m) => switch (m) {
    _TravelMode.driving  => 'Drive',
    _TravelMode.walking  => 'Walk',
    _TravelMode.cycling  => 'Cycle',
    _TravelMode.transit  => 'Transit',
  };

  IconData _maneuverIcon(String m) => switch (m) {
    'turn-right'           => Icons.turn_right_rounded,
    'turn-left'            => Icons.turn_left_rounded,
    'turn-slight-right'    => Icons.turn_slight_right_rounded,
    'turn-slight-left'     => Icons.turn_slight_left_rounded,
    'turn-sharp-right'     => Icons.turn_sharp_right_rounded,
    'turn-sharp-left'      => Icons.turn_sharp_left_rounded,
    'roundabout-right'     => Icons.roundabout_right_rounded,
    'roundabout-left'      => Icons.roundabout_left_rounded,
    'uturn-left'           => Icons.u_turn_left_rounded,
    'uturn-right'          => Icons.u_turn_right_rounded,
    'ramp-right'           => Icons.turn_right_rounded,
    'ramp-left'            => Icons.turn_left_rounded,
    _                      => Icons.straight_rounded,
  };
}
