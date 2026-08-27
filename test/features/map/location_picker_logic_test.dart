import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'package:nearbuy/features/map/location_picker_screen.dart';

void main() {
  group('chooseInitialMapView', () {
    test('keeps the location being edited', () {
      const edited = LatLng(48.8566, 2.3522);

      final view = chooseInitialMapView(
        editedLocation: edited,
        currentLocation: const LatLng(35.6892, 51.3890),
        rememberedLatitude: 45.4642,
        rememberedLongitude: 9.19,
      );

      expect(view.position, edited);
      expect(view.source, InitialMapSource.editedLocation);
      expect(view.zoom, 16);
    });

    test('prefers current location over remembered location', () {
      const current = LatLng(35.6892, 51.3890);

      final view = chooseInitialMapView(
        currentLocation: current,
        rememberedLatitude: 45.4642,
        rememberedLongitude: 9.19,
      );

      expect(view.position, current);
      expect(view.source, InitialMapSource.currentLocation);
    });

    test('uses a valid remembered location without current permission', () {
      final view = chooseInitialMapView(
        rememberedLatitude: 45.4642,
        rememberedLongitude: 9.19,
      );

      expect(view.position, const LatLng(45.4642, 9.19));
      expect(view.source, InitialMapSource.remembered);
      expect(view.zoom, 15);
    });

    test('falls back to the world view for invalid coordinates', () {
      final view = chooseInitialMapView(
        rememberedLatitude: 120,
        rememberedLongitude: 9.19,
      );

      expect(view.position, defaultMapCenter);
      expect(view.source, InitialMapSource.fallback);
    });
  });

  test('formats a readable address without duplicate components', () {
    const placemark = Placemark(
      name: 'Central Market',
      street: 'Central Market',
      locality: 'Milan',
      administrativeArea: 'Lombardy',
      postalCode: '20100',
      country: 'Italy',
    );

    expect(
      formatPlacemark(placemark),
      'Central Market, Milan, Lombardy, 20100, Italy',
    );
  });
}
