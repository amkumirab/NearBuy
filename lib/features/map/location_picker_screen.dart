import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart' as osm;
import 'package:nearbuy/providers.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

const defaultMapCenter = osm.LatLng(20, 0);

class LocationSelection {
  const LocationSelection({required this.position, required this.address});

  final osm.LatLng position;
  final String address;
}

class LocationSearchResult {
  const LocationSearchResult({required this.position, required this.address});

  final osm.LatLng position;
  final String address;
}

enum InitialMapSource { editedLocation, currentLocation, remembered, fallback }

class InitialMapView {
  const InitialMapView({
    required this.position,
    required this.zoom,
    required this.source,
  });

  final osm.LatLng position;
  final double zoom;
  final InitialMapSource source;
}

InitialMapView chooseInitialMapView({
  osm.LatLng? editedLocation,
  osm.LatLng? currentLocation,
  double? rememberedLatitude,
  double? rememberedLongitude,
}) {
  if (editedLocation != null) {
    return InitialMapView(
      position: editedLocation,
      zoom: 16,
      source: InitialMapSource.editedLocation,
    );
  }
  if (currentLocation != null) {
    return InitialMapView(
      position: currentLocation,
      zoom: 16,
      source: InitialMapSource.currentLocation,
    );
  }
  if (_validCoordinates(rememberedLatitude, rememberedLongitude)) {
    return InitialMapView(
      position: osm.LatLng(rememberedLatitude!, rememberedLongitude!),
      zoom: 15,
      source: InitialMapSource.remembered,
    );
  }
  return const InitialMapView(
    position: defaultMapCenter,
    zoom: 3,
    source: InitialMapSource.fallback,
  );
}

bool _validCoordinates(double? latitude, double? longitude) =>
    latitude != null &&
    longitude != null &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180;

abstract interface class LocationSearchService {
  Future<List<LocationSearchResult>> search(String query);
  Future<String> resolve(osm.LatLng position);
}

class PlatformLocationSearchService implements LocationSearchService {
  PlatformLocationSearchService({Geocoding? geocoding})
    : _geocoding = geocoding ?? Geocoding();

  final Geocoding _geocoding;

  @override
  Future<List<LocationSearchResult>> search(String query) async {
    final locations = await _geocoding.locationFromAddress(query);
    final unique = <String, Location>{};
    for (final location in locations) {
      final key =
          '${location.latitude.toStringAsFixed(5)}:'
          '${location.longitude.toStringAsFixed(5)}';
      unique.putIfAbsent(key, () => location);
      if (unique.length == 5) break;
    }

    return Future.wait(
      unique.values.map((location) async {
        final position = osm.LatLng(location.latitude, location.longitude);
        var address = query;
        try {
          final resolved = await resolve(position);
          if (resolved.isNotEmpty) address = resolved;
        } catch (_) {
          // Coordinates are still useful when reverse geocoding is unavailable.
        }
        return LocationSearchResult(position: position, address: address);
      }),
    );
  }

  @override
  Future<String> resolve(osm.LatLng position) async {
    final placemarks = await _geocoding.placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );
    return placemarks.isEmpty ? '' : formatPlacemark(placemarks.first);
  }
}

class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.initialPosition,
    this.initialAddress = '',
    this.searchService,
  });

  final osm.LatLng? initialPosition;
  final String initialAddress;
  final LocationSearchService? searchService;

  @override
  ConsumerState<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  final _searchController = TextEditingController();
  final _mapController = fm.MapController();

  late final LocationSearchService _searchService;
  Timer? _reverseGeocodeTimer;
  late osm.LatLng _selected;
  late String _address;
  List<LocationSearchResult> _searchResults = const [];
  bool _searching = false;
  bool _resolvingAddress = false;
  bool _locating = false;
  bool _mapTouched = false;
  int _addressRequest = 0;

  @override
  void initState() {
    super.initState();
    _searchService = widget.searchService ?? PlatformLocationSearchService();
    _selected = widget.initialPosition ?? defaultMapCenter;
    _address = widget.initialAddress;
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeMap());
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
              initialZoom: widget.initialPosition == null ? 3 : 16,
              minZoom: 3,
              maxZoom: 19,
              onPositionChanged: (camera, hasGesture) {
                _selected = camera.center;
                if (!hasGesture) return;
                _mapTouched = true;
                if (_address.isNotEmpty || _searchResults.isNotEmpty) {
                  setState(() {
                    _address = '';
                    _searchResults = const [];
                  });
                }
                _scheduleReverseGeocode();
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
        if (_searchResults.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            top: 76,
            child: _searchResultsPanel(),
          ),
        Positioned(
          right: 14,
          bottom: 190,
          child: FloatingActionButton.small(
            heroTag: 'current-location',
            tooltip: 'Use my current location',
            onPressed: _locating ? null : _useCurrentLocation,
            child: _locating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
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
      onChanged: (value) {
        if (value.isEmpty && _searchResults.isNotEmpty) {
          setState(() => _searchResults = const []);
        }
      },
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

  Widget _searchResultsPanel() => Material(
    elevation: 8,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _searchResults.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final result = _searchResults[index];
          return ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(
              result.address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${result.position.latitude.toStringAsFixed(5)}, '
              '${result.position.longitude.toStringAsFixed(5)}',
            ),
            onTap: () => _selectSearchResult(result),
          );
        },
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
          Text(
            'Move the map until the pin is over the store',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 20),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _resolvingAddress
                      ? 'Finding address…'
                      : _address.isEmpty
                      ? '${_selected.latitude.toStringAsFixed(6)}, '
                            '${_selected.longitude.toStringAsFixed(6)}'
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

  Future<void> _initializeMap() async {
    if (widget.initialPosition != null) {
      if (_address.isEmpty) await _resolveAddress();
      return;
    }

    double? rememberedLatitude;
    double? rememberedLongitude;
    try {
      final settings = await ref.read(repositoryProvider).readSettings();
      rememberedLatitude = settings.lastMapLatitude;
      rememberedLongitude = settings.lastMapLongitude;
    } catch (_) {
      // The picker still works with the world view if settings are unavailable.
    }
    if (!mounted || _mapTouched) return;

    final cachedPosition = ref.read(locationStatusProvider).value?.position;
    var view = chooseInitialMapView(
      currentLocation: cachedPosition == null
          ? null
          : osm.LatLng(cachedPosition.latitude, cachedPosition.longitude),
      rememberedLatitude: rememberedLatitude,
      rememberedLongitude: rememberedLongitude,
    );
    if (view.source != InitialMapSource.fallback) {
      await _moveTo(view.position, zoom: view.zoom);
      await _resolveAddress();
    }

    if (view.source == InitialMapSource.currentLocation) return;
    try {
      final snapshot = await ref.read(locationStatusProvider.future);
      if (!mounted || _mapTouched || snapshot.position == null) return;
      view = chooseInitialMapView(
        currentLocation: osm.LatLng(
          snapshot.position!.latitude,
          snapshot.position!.longitude,
        ),
      );
      await _moveTo(view.position, zoom: view.zoom);
      await _resolveAddress();
    } catch (_) {
      // Permission can be granted later with the current-location button.
    }
  }

  Future<void> _searchAddress() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _searching) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _searching = true;
      _searchResults = const [];
    });
    try {
      final results = await _searchService.search(query);
      if (!mounted) return;
      if (results.isEmpty) {
        _showMessage(
          'No matching address found. Add a city or postal code and try again.',
        );
      } else {
        setState(() => _searchResults = results);
      }
    } catch (error) {
      if (mounted) _showMessage(_searchErrorMessage(error));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectSearchResult(LocationSearchResult result) async {
    FocusManager.instance.primaryFocus?.unfocus();
    _mapTouched = true;
    await _moveTo(result.position, zoom: 16, address: result.address);
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      await ref.read(locationStatusProvider.notifier).requestForeground();
      if (!mounted) return;
      final snapshot = ref.read(locationStatusProvider).value;
      final position = snapshot?.position;
      if (position != null) {
        _mapTouched = true;
        await _moveTo(
          osm.LatLng(position.latitude, position.longitude),
          zoom: 17,
        );
        await _resolveAddress();
        return;
      }
      if (snapshot != null && !snapshot.servicesEnabled) {
        _showMessage(
          'Location services are turned off.',
          actionLabel: 'Turn on',
          onAction: () =>
              ref.read(locationServiceProvider).openLocationSettings(),
        );
      } else if (snapshot?.foregroundPermission.isPermanentlyDenied ?? false) {
        _showMessage(
          'Location permission is blocked for NearBuy.',
          actionLabel: 'Settings',
          onAction: () => ref.read(locationServiceProvider).openAppSettings(),
        );
      } else {
        _showMessage('Current location is unavailable. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not get your location. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _moveTo(
    osm.LatLng position, {
    required double zoom,
    String address = '',
  }) async {
    _reverseGeocodeTimer?.cancel();
    if (mounted) {
      setState(() {
        _selected = position;
        _address = address;
        _searchResults = const [];
      });
    } else {
      _selected = position;
      _address = address;
    }
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
    final requested = _selected;
    final requestId = ++_addressRequest;
    if (mounted) setState(() => _resolvingAddress = true);
    try {
      final value = await _searchService.resolve(requested);
      if (!mounted || requestId != _addressRequest) return;
      if ((requested.latitude - _selected.latitude).abs() < .00001 &&
          (requested.longitude - _selected.longitude).abs() < .00001) {
        setState(() => _address = value);
      }
    } catch (_) {
      // Coordinates remain usable when address lookup is unavailable.
    } finally {
      if (mounted && requestId == _addressRequest) {
        setState(() => _resolvingAddress = false);
      }
    }
  }

  Future<void> _confirm() async {
    _reverseGeocodeTimer?.cancel();
    if (_address.isEmpty) await _resolveAddress();
    try {
      await ref
          .read(repositoryProvider)
          .saveLastMapLocation(_selected.latitude, _selected.longitude);
    } catch (_) {
      // Remembering the map position must not block location selection.
    }
    if (!mounted) return;
    Navigator.of(
      context,
    ).pop(LocationSelection(position: _selected, address: _address));
  }

  void _showMessage(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
  }
}

String _searchErrorMessage(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('not found') || text.contains('no result')) {
    return 'No matching address found. Add a city or postal code and try again.';
  }
  if (text.contains('network') ||
      text.contains('socket') ||
      text.contains('connection') ||
      text.contains('unavailable')) {
    return 'Address search is unavailable. Check your internet connection.';
  }
  return 'Could not search for that address. Please try again.';
}

String formatPlacemark(Placemark placemark) {
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
