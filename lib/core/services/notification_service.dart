import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nearbuy/core/database/app_database.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  DartPluginRegistrant.ensureInitialized();
}

class NotificationService {
  NotificationService();

  static const _categoryId = 'nearbuy_reminder';
  static const _viewAction = 'view_list';
  static const _laterAction = 'remind_later';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _listOpenController =
      StreamController.broadcast();
  String? _initialListId;

  Stream<String> get listOpenRequests => _listOpenController.stream;

  Future<void> initialize() async {
    const android = AndroidInitializationSettings('ic_stat_nearbuy');
    final ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          _categoryId,
          actions: [
            DarwinNotificationAction.plain(
              _viewAction,
              'View list',
              options: {DarwinNotificationActionOption.foreground},
            ),
            DarwinNotificationAction.plain(_laterAction, 'Remind later'),
          ],
        ),
      ],
    );

    await _plugin.initialize(
      settings: InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _handleResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _initialListId = _listIdFromPayload(
        launch?.notificationResponse?.payload,
      );
    }
  }

  String? takeInitialListId() {
    final value = _initialListId;
    _initialListId = null;
    return value;
  }

  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  Future<void> showReminder(
    ReminderCandidate candidate,
    SettingsEntry settings,
  ) async {
    final preview = candidate.pendingItems
        .take(3)
        .map((item) => item.name)
        .join(', ');
    final remainder = candidate.pendingItems.length > 3 ? ', …' : '';
    final payload = jsonEncode({
      'listId': candidate.list.id,
      'storeId': candidate.store.id,
    });

    final android = AndroidNotificationDetails(
      'nearby_shopping',
      'Nearby shopping reminders',
      channelDescription: 'Alerts when you enter the radius of a saved store.',
      importance: Importance.high,
      priority: Priority.high,
      playSound: settings.soundEnabled,
      enableVibration: settings.vibrationEnabled,
      category: AndroidNotificationCategory.reminder,
      actions: const [
        AndroidNotificationAction(
          _viewAction,
          'View list',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(_laterAction, 'Remind later'),
      ],
    );
    final ios = DarwinNotificationDetails(
      categoryIdentifier: _categoryId,
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: settings.soundEnabled,
    );

    await _plugin.show(
      id: candidate.store.id.hashCode & 0x7fffffff,
      title: 'You’re near ${candidate.store.name}',
      body:
          '${candidate.pendingItems.length} ${candidate.pendingItems.length == 1 ? 'item' : 'items'} left: $preview$remainder',
      notificationDetails: NotificationDetails(android: android, iOS: ios),
      payload: payload,
    );
  }

  Future<void> showTestNotification() async {
    const android = AndroidNotificationDetails(
      'nearby_shopping',
      'Nearby shopping reminders',
      channelDescription: 'Alerts when you enter the radius of a saved store.',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin.show(
      id: 700,
      title: 'NearBuy notifications are ready',
      body: 'You will be reminded when you enter a saved store radius.',
      notificationDetails: const NotificationDetails(
        android: android,
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  void _handleResponse(NotificationResponse response) {
    if (response.actionId == _laterAction) return;
    final listId = _listIdFromPayload(response.payload);
    if (listId != null) _listOpenController.add(listId);
  }

  String? _listIdFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      return (jsonDecode(payload) as Map<String, dynamic>)['listId'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() => _listOpenController.close();
}
