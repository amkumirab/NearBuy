import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as osm;
import 'package:nearbuy/core/database/app_database.dart';
import 'package:nearbuy/core/widgets/async_error_view.dart';
import 'package:nearbuy/providers.dart';

class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storesAsync = ref.watch(storesProvider);
    final lists = ref.watch(listsProvider).value ?? const <ShoppingList>[];
    final items = ref.watch(allItemsProvider).value ?? const <ShoppingItem>[];
    final location = ref.watch(locationStatusProvider).value;

    return storesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AsyncErrorView(error: error),
      data: (stores) {
        final activeStores = stores.where((store) {
          final storeLists = lists.where(
            (list) => list.storeId == store.id && !list.archived,
          );
          return storeLists.any(
            (list) => items.any(
              (item) => item.shoppingListId == list.id && !item.completed,
            ),
          );
        }).toList();
        if (activeStores.isEmpty) {
          return const EmptyState(
            icon: Icons.map_outlined,
            title: 'No active stores',
            message: 'Stores with unfinished shopping items will appear here.',
          );
        }

        final target = location?.position == null
            ? osm.LatLng(
                activeStores.first.latitude,
                activeStores.first.longitude,
              )
            : osm.LatLng(
                location!.position!.latitude,
                location.position!.longitude,
              );
        final userLocation = location?.canUseLocation == true ? target : null;

        return Stack(
          children: [
            _StoreMap(
              target: target,
              stores: activeStores,
              lists: lists,
              items: items,
              userLocation: userLocation,
            ),
            Positioned(
              left: 12,
              top: 10,
              child: SafeArea(
                child: Chip(
                  avatar: const Icon(Icons.radar_rounded, size: 18),
                  label: Text(
                    '${activeStores.length} active ${activeStores.length == 1 ? 'store' : 'stores'}',
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StoreMap extends StatelessWidget {
  const _StoreMap({
    required this.target,
    required this.stores,
    required this.lists,
    required this.items,
    this.userLocation,
  });

  final osm.LatLng target;
  final List<Store> stores;
  final List<ShoppingList> lists;
  final List<ShoppingItem> items;
  final osm.LatLng? userLocation;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return fm.FlutterMap(
      options: fm.MapOptions(
        initialCenter: target,
        initialZoom: 13,
        minZoom: 3,
        maxZoom: 19,
      ),
      children: [
        fm.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.nearbuy.nearbuy',
          maxNativeZoom: 19,
        ),
        fm.CircleLayer(
          circles: stores
              .where((store) => store.geofenceEnabled)
              .map(
                (store) => fm.CircleMarker(
                  point: osm.LatLng(store.latitude, store.longitude),
                  radius: store.geofenceRadius.toDouble(),
                  useRadiusInMeter: true,
                  color: primary.withValues(alpha: .12),
                  borderColor: primary,
                  borderStrokeWidth: 2,
                ),
              )
              .toList(),
        ),
        fm.MarkerLayer(
          markers: [
            ...stores.map((store) {
              final list = lists.firstWhere((list) => list.storeId == store.id);
              final remaining = items
                  .where(
                    (item) => item.shoppingListId == list.id && !item.completed,
                  )
                  .length;
              return fm.Marker(
                point: osm.LatLng(store.latitude, store.longitude),
                width: 54,
                height: 54,
                alignment: Alignment.topCenter,
                child: Tooltip(
                  message:
                      '${store.name} · $remaining items · ${store.geofenceRadius} m',
                  child: GestureDetector(
                    onTap: () => context.push('/lists/${list.id}'),
                    child: Icon(Icons.location_pin, size: 52, color: primary),
                  ),
                ),
              );
            }),
            if (userLocation != null)
              fm.Marker(
                point: userLocation!,
                width: 26,
                height: 26,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 5),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const fm.RichAttributionWidget(
          attributions: [
            fm.TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}
