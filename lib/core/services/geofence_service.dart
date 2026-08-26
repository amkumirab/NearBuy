import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:nearbuy/core/database/app_database.dart';
import 'package:nearbuy/core/services/notification_service.dart';
import 'package:permission_handler/permission_handler.dart';

@pragma('vm:entry-point')
Future<void> nearBuyGeofenceTriggered(GeofenceCallbackParams params) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  if (params.event != GeofenceEvent.enter &&
      params.event != GeofenceEvent.dwell) {
    return;
  }

  final database = AppDatabase.defaults();
  final notifications = NotificationService();
  try {
    await notifications.initialize();
    for (final geofence in params.geofences) {
      final candidate = await database.reminderCandidate(geofence.id);
      if (candidate == null) continue;
      final settings = await database.readSettings();
      await notifications.showReminder(candidate, settings);
      await database.markStoreNotified(geofence.id);
    }
  } finally {
    await database.close();
    await notifications.dispose();
  }
}

class GeofenceService {
  GeofenceService(this.database);

  final AppDatabase database;
  bool _initialized = false;

  bool get _supported => Platform.isAndroid || Platform.isIOS;

  Future<void> initialize() async {
    if (!_supported || _initialized) return;
    await NativeGeofenceManager.instance.initialize();
    _initialized = true;
  }

  Future<void> sync() async {
    if (!_supported) return;
    if (!(await Permission.locationAlways.status).isGranted) return;
    await initialize();

    final registrations = await database.activeGeofenceRegistrations();
    final desiredIds = registrations.map((entry) => entry.store.id).toSet();
    final activeIds =
        (await NativeGeofenceManager.instance.getRegisteredGeofenceIds())
            .toSet();

    for (final staleId in activeIds.difference(desiredIds)) {
      await NativeGeofenceManager.instance.removeGeofenceById(staleId);
    }
    for (final registration in registrations) {
      final store = registration.store;
      await NativeGeofenceManager.instance.createGeofence(
        Geofence(
          id: store.id,
          location: Location(
            latitude: store.latitude,
            longitude: store.longitude,
          ),
          radiusMeters: store.geofenceRadius.toDouble(),
          triggers: const {GeofenceEvent.enter},
          iosSettings: const IosGeofenceSettings(initialTrigger: true),
          androidSettings: const AndroidGeofenceSettings(
            initialTriggers: {GeofenceEvent.enter},
            notificationResponsiveness: Duration(minutes: 2),
          ),
        ),
        nearBuyGeofenceTriggered,
      );
    }
  }

  Future<void> removeAll() async {
    if (!_supported) return;
    await initialize();
    await NativeGeofenceManager.instance.removeAllGeofences();
  }
}
