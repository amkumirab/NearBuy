import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nearbuy/core/theme/app_theme.dart';
import 'package:nearbuy/features/history/history_screen.dart';
import 'package:nearbuy/features/home/home_screen.dart';
import 'package:nearbuy/features/lists/list_detail_screen.dart';
import 'package:nearbuy/features/lists/list_editor_screen.dart';
import 'package:nearbuy/features/map/map_screen.dart';
import 'package:nearbuy/features/settings/settings_screen.dart';
import 'package:nearbuy/features/shell/app_shell.dart';
import 'package:nearbuy/features/shopping/shopping_mode_screen.dart';
import 'package:nearbuy/providers.dart';

class NearBuyApp extends ConsumerStatefulWidget {
  const NearBuyApp({super.key, this.initialListId});

  final String? initialListId;

  @override
  ConsumerState<NearBuyApp> createState() => _NearBuyAppState();
}

class _NearBuyAppState extends ConsumerState<NearBuyApp> {
  late final GoRouter _router;
  StreamSubscription<String>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _router = _createRouter(widget.initialListId);
    final notifications = ref.read(notificationServiceProvider);
    _notificationSubscription = notifications.listOpenRequests.listen(
      (listId) => _router.go('/lists/$listId'),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(geofenceServiceProvider).sync();
      } catch (_) {
        // Permissions can be completed later from Settings.
      }
    });
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setting = ref.watch(settingsProvider).value;
    final themeMode = switch (setting?.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp.router(
      title: 'NearBuy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}

GoRouter _createRouter(String? initialListId) => GoRouter(
  initialLocation: initialListId == null ? '/' : '/lists/$initialListId',
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(path: '/map', builder: (context, state) => const MapScreen()),
        GoRoute(
          path: '/history',
          builder: (context, state) => const HistoryScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/lists/new',
      builder: (context, state) => const ListEditorScreen(),
    ),
    GoRoute(
      path: '/lists/:id/edit',
      builder: (context, state) =>
          ListEditorScreen(listId: state.pathParameters['id']),
    ),
    GoRoute(
      path: '/lists/:id',
      builder: (context, state) =>
          ListDetailScreen(listId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/shopping/:id',
      builder: (context, state) =>
          ShoppingModeScreen(listId: state.pathParameters['id']!),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('NearBuy')),
    body: Center(child: Text('Page not found: ${state.uri}')),
  ),
);
