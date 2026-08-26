import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:nearbuy/core/database/app_database.dart';
import 'package:nearbuy/core/widgets/async_error_view.dart';
import 'package:nearbuy/providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listsAsync = ref.watch(listsProvider);
    final stores = ref.watch(storesProvider).value ?? const <Store>[];
    final items = ref.watch(allItemsProvider).value ?? const <ShoppingItem>[];
    final location = ref.watch(locationStatusProvider).value;

    return listsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AsyncErrorView(error: error),
      data: (lists) => RefreshIndicator(
        onRefresh: () => ref.read(locationStatusProvider.notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              sliver: SliverList.list(
                children: [
                  if (!(location?.canUseLocation ?? false))
                    const _LocationBanner(),
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Shopping lists',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Everything you need, right when you’re nearby.',
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => context.push('/lists/new'),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New list'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (lists.isEmpty)
                    EmptyState(
                      icon: Icons.shopping_cart_outlined,
                      title: 'No shopping lists yet',
                      message:
                          'Create a list with or without a store. Add a location whenever you want proximity reminders.',
                      action: FilledButton(
                        onPressed: () => context.push('/lists/new'),
                        child: const Text('Create shopping list'),
                      ),
                    )
                  else
                    ...lists.map((list) {
                      final store = stores
                          .where((entry) => entry.id == list.storeId)
                          .firstOrNull;
                      final listItems = items
                          .where((item) => item.shoppingListId == list.id)
                          .toList();
                      final remaining = listItems
                          .where((item) => !item.completed)
                          .length;
                      final completed = listItems.length - remaining;
                      double? distance;
                      if (store != null && location?.position != null) {
                        distance = Geolocator.distanceBetween(
                          location!.position!.latitude,
                          location.position!.longitude,
                          store.latitude,
                          store.longitude,
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ListCard(
                          list: list,
                          store: store,
                          remaining: remaining,
                          completed: completed,
                          total: listItems.length,
                          distanceMeters: distance,
                          onTap: () => context.push('/lists/${list.id}'),
                          onToggleGeofence: store == null
                              ? null
                              : () => ref
                                    .read(actionsProvider)
                                    .setGeofenceEnabled(
                                      store.id,
                                      !store.geofenceEnabled,
                                    ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationBanner extends ConsumerWidget {
  const _LocationBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.location_off_outlined),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Location is optional',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Enable it to see distance and activate reminders.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(locationStatusProvider.notifier).requestForeground(),
            child: const Text('Enable'),
          ),
        ],
      ),
    ),
  );
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.list,
    required this.store,
    required this.remaining,
    required this.completed,
    required this.total,
    required this.distanceMeters,
    required this.onTap,
    required this.onToggleGeofence,
  });

  final ShoppingList list;
  final Store? store;
  final int remaining;
  final int completed;
  final int total;
  final double? distanceMeters;
  final VoidCallback onTap;
  final VoidCallback? onToggleGeofence;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Icon(
                      _categoryIcon(store?.category),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          list.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          store == null
                              ? 'Normal list · no location'
                              : (store!.address.isEmpty
                                    ? store!.category
                                    : store!.address),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (store != null)
                    IconButton(
                      onPressed: onToggleGeofence,
                      tooltip: store!.geofenceEnabled
                          ? 'Disable proximity reminder'
                          : 'Enable proximity reminder',
                      icon: Icon(
                        store!.geofenceEnabled
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$remaining ${remaining == 1 ? 'item' : 'items'} remaining',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '$completed / $total',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                borderRadius: BorderRadius.circular(99),
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  if (store != null) ...[
                    _Badge(
                      icon: Icons.location_on_outlined,
                      text: _distance(distanceMeters),
                    ),
                    const SizedBox(width: 8),
                    _Badge(
                      icon: Icons.radar_rounded,
                      text: '${store!.geofenceRadius} m',
                    ),
                  ] else
                    const _Badge(
                      icon: Icons.location_off_outlined,
                      text: 'No store',
                    ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _distance(double? meters) {
    if (meters == null) return 'Distance unavailable';
    if (meters < 1000) return '${meters.round()} m away';
    return '${(meters / 1000).toStringAsFixed(1)} km away';
  }

  static IconData _categoryIcon(String? category) => switch (category) {
    'Pharmacy' => Icons.local_pharmacy_outlined,
    'Electronics' => Icons.devices_other_outlined,
    'Clothing' => Icons.checkroom_outlined,
    'Bakery' => Icons.bakery_dining_outlined,
    'Hardware' => Icons.hardware_outlined,
    _ => Icons.storefront_outlined,
  };
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
