import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart' as osm;
import 'package:nearbuy/providers.dart';

class LocationSelection {
  const LocationSelection({required this.position, required this.address});

  final osm.LatLng position;
  final String address;
}

class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.initialPosition,
    this.initialAddress = '',
  });

  final osm.LatLng? initialPosition;
  final String initialAddress;

  @override
  ConsumerState<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  final _searchController = TextEditingController();
  final _mapController = fm.MapController();
  final _geocoding = Geocoding();

  Timer? _reverseGeocodeTimer;
  late osm.LatLng _selected;
  late String _address;
  bool _searching = false;
  bool _resolvingAddress = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialPosition ?? const osm.LatLng(41.9028, 12.4964);
    _address = widget.initialAddress;
  }

  @override
  void dispose() {
    _reverseGeocodeTimer?.cancel();
    _mapController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Choose store location',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body: Stack(
      children: [
        Positioned.fill(
          child: fm.FlutterMap(
            mapController: _mapController,
            options: fm.MapOptions(
              initialCenter: _selected,
              initialZoom: widget.initialPosition == null ? 5 : 16,
              minZoom: 3,
              maxZoom: 19,
              onPositionChanged: (camera, hasGesture) {
                _selected = camera.center;
                if (hasGesture) _scheduleReverseGeocode();
              },
            ),
            children: [
              fm.TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.nearbuy.nearbuy',
                maxNativeZoom: 19,
              ),
              const fm.RichAttributionWidget(
                attributions: [
                  fm.TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
        ),
        const IgnorePointer(
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 38),
              child: Icon(
                Icons.location_pin,
                size: 58,
                color: Color(0xFF087F5B),
                shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
              ),
            ),
          ),
        ),
        Positioned(left: 12, right: 12, top: 12, child: _searchBar()),
        Positioned(
          right: 14,
          bottom: 190,
          child: FloatingActionButton.small(
            heroTag: 'current-location',
            tooltip: 'Use my current location',
            onPressed: _useCurrentLocation,
            child: const Icon(Icons.my_location_rounded),
          ),
        ),
        Positioned(left: 12, right: 12, bottom: 12, child: _confirmationCard()),
      ],
    ),
  );

  Widget _searchBar() => Material(
    elevation: 5,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _searchAddress(),
      decoration: InputDecoration(
        hintText: 'Search city, street, or address',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searching
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                tooltip: 'Search',
                onPressed: _searchAddress,
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
        border: InputBorder.none,
        filled: true,
      ),
    ),
  );

  Widget _confirmationCard() => Card(
    elevation: 6,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 20),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _resolvingAddress
                      ? 'Finding address…'
                      : _address.isEmpty
                      ? '${_selected.latitude.toStringAsFixed(6)}, ${_selected.longitude.toStringAsFixed(6)}'
                      : _address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _confirm,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Confirm this location'),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _searchAddress() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _searching) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _searching = true);
    try {
      final results = await _geocoding.locationFromAddress(query);
      if (results.isEmpty) throw StateError('No matching address');
      final result = results.first;
      await _moveTo(osm.LatLng(result.latitude, result.longitude), zoom: 16);
      await _resolveAddress();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Address not found. Add the city or postal code and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    await ref.read(locationStatusProvider.notifier).requestForeground();
    final position = ref.read(locationStatusProvider).value?.position;
    if (!mounted) return;
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current location is unavailable. Check permission.'),
        ),
      );
      return;
    }
    await _moveTo(osm.LatLng(position.latitude, position.longitude), zoom: 17);
    await _resolveAddress();
  }

  Future<void> _moveTo(osm.LatLng position, {required double zoom}) async {
    _selected = position;
    _mapController.move(position, zoom);
  }

  void _scheduleReverseGeocode() {
    _reverseGeocodeTimer?.cancel();
    _reverseGeocodeTimer = Timer(
      const Duration(milliseconds: 650),
      _resolveAddress,
    );
  }

  Future<void> _resolveAddress() async {
    if (_resolvingAddress) return;
    final requested = _selected;
    if (mounted) setState(() => _resolvingAddress = true);
    try {
      final placemarks = await _geocoding.placemarkFromCoordinates(
        requested.latitude,
        requested.longitude,
      );
      if (placemarks.isNotEmpty && mounted) {
        final value = _formatPlacemark(placemarks.first);
        if ((requested.latitude - _selected.latitude).abs() < .00001 &&
            (requested.longitude - _selected.longitude).abs() < .00001) {
          setState(() => _address = value);
        }
      }
    } catch (_) {
      // Coordinates remain usable when the platform geocoder is unavailable.
    } finally {
      if (mounted) setState(() => _resolvingAddress = false);
    }
  }

  Future<void> _confirm() async {
    _reverseGeocodeTimer?.cancel();
    if (_address.isEmpty) await _resolveAddress();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pop(LocationSelection(position: _selected, address: _address));
  }
}

String _formatPlacemark(Placemark placemark) {
  final values = <String?>[
    placemark.name,
    placemark.street,
    placemark.locality,
    placemark.administrativeArea,
    placemark.postalCode,
    placemark.country,
  ];
  final unique = <String>[];
  for (final value in values) {
    final clean = value?.trim() ?? '';
    if (clean.isNotEmpty && !unique.contains(clean)) unique.add(clean);
  }
  return unique.join(', ');
}
