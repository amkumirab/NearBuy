import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nearbuy/core/database/app_database.dart';
import 'package:nearbuy/core/widgets/async_error_view.dart';
import 'package:nearbuy/providers.dart';
import 'package:permission_handler/permission_handler.dart';

final _notificationPermissionProvider = FutureProvider<PermissionStatus>(
  (ref) => Permission.notification.status,
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final locationAsync = ref.watch(locationStatusProvider);
    final notificationPermission = ref.watch(_notificationPermissionProvider);
    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AsyncErrorView(error: error),
      data: (settings) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          const Text(
            'Settings',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          const Text(
            'Permissions, reminders, appearance, and your local data.',
          ),
          const SizedBox(height: 18),
          _Section(
            title: 'Appearance',
            icon: Icons.palette_outlined,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'light',
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: 'dark',
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
                ButtonSegment(
                  value: 'system',
                  label: Text('System'),
                  icon: Icon(Icons.settings_suggest_outlined),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (value) => ref
                  .read(actionsProvider)
                  .updateSettings(
                    SettingsEntriesCompanion(themeMode: Value(value.first)),
                  ),
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Location & geofencing',
            icon: Icons.location_on_outlined,
            child: locationAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('Location status unavailable: $error'),
              data: (location) => Column(
                children: [
                  _StatusRow(
                    label: 'Location Services',
                    detail: location.servicesEnabled
                        ? 'Enabled on this device'
                        : 'Disabled on this device',
                    ok: location.servicesEnabled,
                    action: location.servicesEnabled
                        ? null
                        : TextButton(
                            onPressed: ref
                                .read(locationServiceProvider)
                                .openLocationSettings,
                            child: const Text('Open'),
                          ),
                  ),
                  const Divider(),
                  _StatusRow(
                    label: 'While-using permission',
                    detail: _permissionLabel(location.foregroundPermission),
                    ok: location.foregroundPermission.isGranted,
                    action: location.foregroundPermission.isGranted
                        ? null
                        : TextButton(
                            onPressed: () => ref
                                .read(locationStatusProvider.notifier)
                                .requestForeground(),
                            child: const Text('Enable'),
                          ),
                  ),
                  const Divider(),
                  _StatusRow(
                    label: 'Background permission',
                    detail: location.backgroundPermission.isGranted
                        ? 'Always access granted · reminders can work while closed'
                        : 'Required for native store-entry reminders',
                    ok: location.backgroundPermission.isGranted,
                    action: location.backgroundPermission.isGranted
                        ? null
                        : TextButton(
                            onPressed: () => _requestBackground(context, ref),
                            child: const Text('Enable'),
                          ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: settings.defaultRadius,
                    decoration: const InputDecoration(
                      labelText: 'Default reminder radius',
                    ),
                    items: const [250, 500, 700, 1000, 2000]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              value >= 1000
                                  ? '${value ~/ 1000} km'
                                  : '$value m',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(actionsProvider)
                            .updateSettings(
                              SettingsEntriesCompanion(
                                defaultRadius: Value(value),
                              ),
                            );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Notifications',
            icon: Icons.notifications_outlined,
            child: Column(
              children: [
                notificationPermission.when(
                  loading: () => const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Notification permission'),
                    trailing: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (_, _) => const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Notification permission'),
                    subtitle: Text('Status unavailable'),
                  ),
                  data: (status) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      status.isGranted
                          ? Icons.check_circle_outline_rounded
                          : Icons.warning_amber_rounded,
                    ),
                    title: const Text('Notification permission'),
                    subtitle: Text(_permissionLabel(status)),
                    trailing: status.isGranted
                        ? null
                        : TextButton(
                            onPressed: openAppSettings,
                            child: const Text('Open settings'),
                          ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.notificationsEnabled,
                  title: const Text(
                    'Proximity reminders',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'Notify only for stores with unfinished items.',
                  ),
                  onChanged: (value) => ref
                      .read(actionsProvider)
                      .updateSettings(
                        SettingsEntriesCompanion(
                          notificationsEnabled: Value(value),
                        ),
                      ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.soundEnabled,
                  title: const Text('Sound'),
                  onChanged: (value) => ref
                      .read(actionsProvider)
                      .updateSettings(
                        SettingsEntriesCompanion(soundEnabled: Value(value)),
                      ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.vibrationEnabled,
                  title: const Text('Vibration'),
                  onChanged: (value) => ref
                      .read(actionsProvider)
                      .updateSettings(
                        SettingsEntriesCompanion(
                          vibrationEnabled: Value(value),
                        ),
                      ),
                ),
                DropdownButtonFormField<int>(
                  initialValue: settings.cooldownHours,
                  decoration: const InputDecoration(
                    labelText: 'Per-store cooldown',
                  ),
                  items: const [1, 2, 3, 6, 12, 24]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(
                            '$value ${value == 1 ? 'hour' : 'hours'}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(actionsProvider)
                          .updateSettings(
                            SettingsEntriesCompanion(
                              cooldownHours: Value(value),
                            ),
                          );
                    }
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final granted = await ref
                              .read(notificationServiceProvider)
                              .requestPermission();
                          ref.invalidate(_notificationPermissionProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  granted
                                      ? 'Notifications enabled.'
                                      : 'Notification permission was not granted.',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text('Enable permission'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: ref
                          .read(notificationServiceProvider)
                          .showTestNotification,
                      child: const Text('Test'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Data',
            icon: Icons.storage_outlined,
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_toggle_off_rounded),
                  title: const Text('Clear shopping history'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    if (await _confirm(
                      context,
                      'Clear history?',
                      'Completed trip records will be permanently removed.',
                    )) {
                      await ref.read(actionsProvider).clearHistory();
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Delete all app data',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    if (await _confirm(
                      context,
                      'Delete all data?',
                      'All lists, stores, items, history, and settings will be removed.',
                    )) {
                      await ref.read(actionsProvider).deleteAllData();
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'About & privacy',
            icon: Icons.shield_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NearBuy 1.0.0',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Shopping lists, store coordinates, reminder timestamps, and trip history stay in the local SQLite database on this device.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Maps use OpenStreetMap tiles. Store coordinates remain in the local database and no Google Maps billing account is required.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _requestBackground(BuildContext context, WidgetRef ref) async {
  final accepted =
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.radar_rounded, size: 38),
          title: const Text('Allow background location?'),
          content: const Text(
            'NearBuy uses the operating system’s battery-efficient geofencing to detect entry into saved store radiuses. It does not continuously record or upload your location. Choose “Allow all the time” when Android or iOS asks.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;
  if (!accepted) return;
  await ref.read(locationStatusProvider.notifier).requestBackground();
  final result = ref.read(locationStatusProvider).value;
  if (context.mounted && !(result?.canUseBackground ?? false)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Background permission is still disabled. You can enable it in system app settings.',
        ),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: ref.read(locationServiceProvider).openAppSettings,
        ),
      ),
    );
  }
}

String _permissionLabel(PermissionStatus status) => switch (status) {
  PermissionStatus.granted => 'Granted',
  PermissionStatus.permanentlyDenied => 'Permanently denied',
  PermissionStatus.restricted => 'Restricted by the device',
  PermissionStatus.limited => 'Limited',
  _ => 'Not granted',
};

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.detail,
    required this.ok,
    this.action,
  });
  final String label;
  final String detail;
  final bool ok;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
        color: ok ? Colors.green : Colors.orange,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      if (action case final Widget action) action,
    ],
  );
}
