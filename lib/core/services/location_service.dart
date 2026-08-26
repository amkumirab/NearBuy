import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

class LocationSnapshot {
  const LocationSnapshot({
    required this.servicesEnabled,
    required this.foregroundPermission,
    required this.backgroundPermission,
    this.position,
  });

  final bool servicesEnabled;
  final permissions.PermissionStatus foregroundPermission;
  final permissions.PermissionStatus backgroundPermission;
  final Position? position;

  bool get canUseLocation => servicesEnabled && foregroundPermission.isGranted;
  bool get canUseBackground => canUseLocation && backgroundPermission.isGranted;
}

class LocationService {
  Future<LocationSnapshot> status({bool includePosition = true}) async {
    final servicesEnabled = await Geolocator.isLocationServiceEnabled();
    final foreground = await permissions.Permission.location.status;
    final background = (Platform.isAndroid || Platform.isIOS)
        ? await permissions.Permission.locationAlways.status
        : permissions.PermissionStatus.denied;
    Position? position;
    if (includePosition && servicesEnabled && foreground.isGranted) {
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }
    }
    return LocationSnapshot(
      servicesEnabled: servicesEnabled,
      foregroundPermission: foreground,
      backgroundPermission: background,
      position: position,
    );
  }

  Future<LocationSnapshot> requestForeground() async {
    await permissions.Permission.location.request();
    return status();
  }

  Future<LocationSnapshot> requestBackground() async {
    final foreground = await permissions.Permission.location.request();
    if (foreground.isGranted) {
      await permissions.Permission.locationAlways.request();
    }
    return status();
  }

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
  Future<bool> openAppSettings() => permissions.openAppSettings();
}
