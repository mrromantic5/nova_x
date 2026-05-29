// lib/core/services/map_service.dart
//
// NOVA Map — Maps API Service
// Handles: Places Autocomplete, Place Details, Nearby Search,
//          Directions, Reverse Geocoding, Distance Matrix

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ── Data Models ──────────────────────────────────────────────────────────────

class PlaceAutocomplete {
  final String placeId;
  final String mainText;
  final String secondaryText;
  final String description;
  const PlaceAutocomplete({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    required this.description,
  });
}

class PlaceDetails {
  final String   placeId;
  final String   name;
  final String   address;
  final LatLng   location;
  final double?  rating;
  final int?     userRatingsTotal;
  final String?  phoneNumber;
  final String?  website;
  final bool?    openNow;
  final String?  openingHours;
  final List<String> types;
  final String?  photoRef;
  final double?  distanceKm;

  const PlaceDetails({
    required this.placeId,
    required this.name,
    required this.address,
    required this.location,
    this.rating,
    this.userRatingsTotal,
    this.phoneNumber,
    this.website,
    this.openNow,
    this.openingHours,
    required this.types,
    this.photoRef,
    this.distanceKm,
  });
}

class NearbyPlace {
  final String  placeId;
  final String  name;
  final String  vicinity;
  final LatLng  location;
  final double? rating;
  final bool?   openNow;
  final String? photoRef;
  final List<String> types;

  const NearbyPlace({
    required this.placeId,
    required this.name,
    required this.vicinity,
    required this.location,
    this.rating,
    this.openNow,
    this.photoRef,
    required this.types,
  });
}

class DirectionStep {
  final String htmlInstruction;
  final String plainInstruction;
  final String distance;
  final String duration;
  final LatLng startLocation;
  final LatLng endLocation;
  final String maneuver;

  const DirectionStep({
    required this.htmlInstruction,
    required this.plainInstruction,
    required this.distance,
    required this.duration,
    required this.startLocation,
    required this.endLocation,
    required this.maneuver,
  });
}

class DirectionsResult {
  final List<LatLng>      polylinePoints;
  final String            distance;
  final String            duration;
  final String            durationInTraffic;
  final List<DirectionStep> steps;
  final LatLngBounds      bounds;
  final String            summary;

  const DirectionsResult({
    required this.polylinePoints,
    required this.distance,
    required this.duration,
    required this.durationInTraffic,
    required this.steps,
    required this.bounds,
    required this.summary,
  });
}

// ── Place categories ─────────────────────────────────────────────────────────
class PlaceCategory {
  final String  type;
  final String  label;
  final String  emoji;
  const PlaceCategory({
    required this.type,
    required this.label,
    required this.emoji,
  });
}

// ════════════════════════════════════════════════════════════════════════════
class MapService {
  static const _apiKey  = 'AIzaSyBc_bNBj_hmsG5rNFXHC4Tmgp0BRBjyXos';
  static const _baseUrl = 'https://maps.googleapis.com/maps/api';

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    validateStatus: (_) => true,
  ));

  static const List<PlaceCategory> categories = [
    PlaceCategory(type: 'restaurant',     label: 'Food',      emoji: '🍽️'),
    PlaceCategory(type: 'hospital',       label: 'Hospital',  emoji: '🏥'),
    PlaceCategory(type: 'bank',           label: 'Bank',      emoji: '🏦'),
    PlaceCategory(type: 'gas_station',    label: 'Fuel',      emoji: '⛽'),
    PlaceCategory(type: 'hotel',          label: 'Hotel',     emoji: '🏨'),
    PlaceCategory(type: 'pharmacy',       label: 'Pharmacy',  emoji: '💊'),
    PlaceCategory(type: 'supermarket',    label: 'Market',    emoji: '🛒'),
    PlaceCategory(type: 'atm',            label: 'ATM',       emoji: '🏧'),
    PlaceCategory(type: 'police',         label: 'Police',    emoji: '👮'),
    PlaceCategory(type: 'school',         label: 'School',    emoji: '🏫'),
  ];

  // ── Places Autocomplete ───────────────────────────────────────────────────
  static Future<List<PlaceAutocomplete>> searchPlaces(
      String input, {LatLng? location}) async {
    if (input.trim().isEmpty) return [];
    try {
      final params = {
        'input': input,
        'key':   _apiKey,
        'language': 'en',
        if (location != null)
          'location': '${location.latitude},${location.longitude}',
        if (location != null)
          'radius': '50000',
      };
      final r = await _dio.get('$_baseUrl/place/autocomplete/json',
          queryParameters: params);
      final data = r.data as Map<String, dynamic>;
      if (data['status'] != 'OK') return [];
      return (data['predictions'] as List).map((p) {
        final terms = p['terms'] as List? ?? [];
        return PlaceAutocomplete(
          placeId:       p['place_id'] ?? '',
          description:   p['description'] ?? '',
          mainText:      p['structured_formatting']?['main_text'] ?? '',
          secondaryText: p['structured_formatting']?['secondary_text'] ?? '',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Place Details ─────────────────────────────────────────────────────────
  static Future<PlaceDetails?> getPlaceDetails(
      String placeId, {LatLng? currentLocation}) async {
    try {
      final r = await _dio.get('$_baseUrl/place/details/json',
          queryParameters: {
            'place_id': placeId,
            'fields':
                'name,formatted_address,geometry,rating,user_ratings_total,'
                'formatted_phone_number,website,opening_hours,types,photos',
            'key': _apiKey,
          });
      final data = r.data as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;
      final result = data['result'] as Map<String, dynamic>;
      final geo = result['geometry']['location'];
      final loc = LatLng(
          (geo['lat'] as num).toDouble(),
          (geo['lng'] as num).toDouble());

      double? dist;
      if (currentLocation != null) {
        dist = _calcDistKm(currentLocation, loc);
      }

      final photos = result['photos'] as List?;
      final hours  = result['opening_hours'];
      List<String> weekdays = [];
      if (hours?['weekday_text'] != null) {
        weekdays = List<String>.from(hours['weekday_text']);
      }

      return PlaceDetails(
        placeId:          placeId,
        name:             result['name'] ?? '',
        address:          result['formatted_address'] ?? '',
        location:         loc,
        rating:           (result['rating'] as num?)?.toDouble(),
        userRatingsTotal: result['user_ratings_total'] as int?,
        phoneNumber:      result['formatted_phone_number'] as String?,
        website:          result['website'] as String?,
        openNow:          hours?['open_now'] as bool?,
        openingHours:     weekdays.isNotEmpty ? weekdays.join('\n') : null,
        types:            List<String>.from(result['types'] ?? []),
        photoRef:         photos?.isNotEmpty == true
            ? photos!.first['photo_reference'] as String?
            : null,
        distanceKm:       dist,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Nearby Places ─────────────────────────────────────────────────────────
  static Future<List<NearbyPlace>> getNearbyPlaces(
      LatLng location, String type,
      {int radius = 2000}) async {
    try {
      final r = await _dio.get('$_baseUrl/place/nearbysearch/json',
          queryParameters: {
            'location': '${location.latitude},${location.longitude}',
            'radius':   radius,
            'type':     type,
            'key':      _apiKey,
            'language': 'en',
          });
      final data = r.data as Map<String, dynamic>;
      if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') {
        return [];
      }
      return ((data['results'] as List?) ?? []).take(20).map((p) {
        final geo = p['geometry']['location'];
        final oh  = p['opening_hours'];
        final ph  = p['photos'] as List?;
        return NearbyPlace(
          placeId:  p['place_id'] ?? '',
          name:     p['name'] ?? '',
          vicinity: p['vicinity'] ?? '',
          location: LatLng(
              (geo['lat'] as num).toDouble(),
              (geo['lng'] as num).toDouble()),
          rating:   (p['rating'] as num?)?.toDouble(),
          openNow:  oh?['open_now'] as bool?,
          photoRef: ph?.isNotEmpty == true
              ? ph!.first['photo_reference'] as String?
              : null,
          types: List<String>.from(p['types'] ?? []),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Directions ────────────────────────────────────────────────────────────
  static Future<DirectionsResult?> getDirections({
    required LatLng origin,
    required LatLng destination,
    String mode = 'driving',
  }) async {
    try {
      final r = await _dio.get('$_baseUrl/directions/json',
          queryParameters: {
            'origin':      '${origin.latitude},${origin.longitude}',
            'destination': '${destination.latitude},${destination.longitude}',
            'mode':        mode,
            'departure_time': 'now',
            'alternatives': false,
            'key':         _apiKey,
            'language':    'en',
          });
      final data = r.data as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;

      final route = (data['routes'] as List).first as Map<String, dynamic>;
      final leg   = (route['legs'] as List).first as Map<String, dynamic>;

      // Decode polyline
      final encoded = route['overview_polyline']['points'] as String;
      final points  = _decodePolyline(encoded);

      // Bounds
      final ne = route['bounds']['northeast'];
      final sw = route['bounds']['southwest'];
      final bounds = LatLngBounds(
        northeast: LatLng(
            (ne['lat'] as num).toDouble(), (ne['lng'] as num).toDouble()),
        southwest: LatLng(
            (sw['lat'] as num).toDouble(), (sw['lng'] as num).toDouble()),
      );

      // Steps
      final steps = ((leg['steps'] as List?) ?? []).map((s) {
        final sl = s['start_location'];
        final el = s['end_location'];
        return DirectionStep(
          htmlInstruction:  s['html_instructions'] ?? '',
          plainInstruction: _stripHtml(s['html_instructions'] ?? ''),
          distance:  s['distance']?['text'] ?? '',
          duration:  s['duration']?['text'] ?? '',
          startLocation: LatLng(
              (sl['lat'] as num).toDouble(),
              (sl['lng'] as num).toDouble()),
          endLocation: LatLng(
              (el['lat'] as num).toDouble(),
              (el['lng'] as num).toDouble()),
          maneuver: s['maneuver'] ?? '',
        );
      }).toList();

      final trafficDur = leg['duration_in_traffic']?['text'] ??
          leg['duration']?['text'] ?? '';

      return DirectionsResult(
        polylinePoints:    points,
        distance:          leg['distance']?['text'] ?? '',
        duration:          leg['duration']?['text'] ?? '',
        durationInTraffic: trafficDur,
        steps:             steps,
        bounds:            bounds,
        summary:           route['summary'] ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  // ── Reverse Geocoding ─────────────────────────────────────────────────────
  static Future<String?> getAddressFromLocation(LatLng location) async {
    try {
      final r = await _dio.get('$_baseUrl/geocode/json',
          queryParameters: {
            'latlng': '${location.latitude},${location.longitude}',
            'key':    _apiKey,
            'language': 'en',
          });
      final data = r.data as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;
      final results = data['results'] as List;
      if (results.isEmpty) return null;
      return results.first['formatted_address'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── Photo URL ─────────────────────────────────────────────────────────────
  static String getPhotoUrl(String photoRef, {int maxWidth = 400}) =>
      '$_baseUrl/place/photo'
      '?maxwidth=$maxWidth'
      '&photo_reference=$photoRef'
      '&key=$_apiKey';

  // ── Helpers ───────────────────────────────────────────────────────────────
  static double _calcDistKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final lat1 = a.latitude * (3.14159265358979 / 180);
    final lat2 = b.latitude * (3.14159265358979 / 180);
    final dLat = (b.latitude  - a.latitude)  * (3.14159265358979 / 180);
    final dLon = (b.longitude - a.longitude) * (3.14159265358979 / 180);
    final sinLat = (dLat / 2);
    final sinLon = (dLon / 2);
    final x = sinLat * sinLat +
        (1 - sinLat * sinLat - (lat1 - lat2).abs()) *
        sinLon * sinLon;
    return r * 2 * (x < 1 ? x : 1);
  }

  static List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;
      shift = 0; result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  static String _stripHtml(String html) =>
      html.replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ').trim();
}
