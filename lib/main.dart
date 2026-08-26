import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nearbuy/app.dart';
import 'package:nearbuy/core/services/notification_service.dart';
import 'package:nearbuy/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notifications = NotificationService();
  await notifications.initialize();

  runApp(
    ProviderScope(
      overrides: [notificationServiceProvider.overrideWithValue(notifications)],
      child: NearBuyApp(initialListId: notifications.takeInitialListId()),
    ),
  );
}
