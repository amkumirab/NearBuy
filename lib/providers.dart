import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nearbuy/core/database/app_database.dart';
import 'package:nearbuy/core/repositories/nearbuy_repository.dart';
import 'package:nearbuy/core/services/geofence_service.dart';
import 'package:nearbuy/core/services/location_service.dart';
import 'package:nearbuy/core/services/notification_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase.defaults();
  ref.onDispose(database.close);
  return database;
});

final repositoryProvider = Provider<NearBuyRepository>(
  (ref) => NearBuyRepository(ref.watch(databaseProvider)),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError(
    'NotificationService must be overridden in main.',
  ),
);

final locationServiceProvider = Provider((ref) => LocationService());
final geofenceServiceProvider = Provider(
  (ref) => GeofenceService(ref.watch(databaseProvider)),
);

final listsProvider = StreamProvider<List<ShoppingList>>(
  (ref) => ref.watch(repositoryProvider).watchLists(),
);
final storesProvider = StreamProvider<List<Store>>(
  (ref) => ref.watch(repositoryProvider).watchStores(),
);
final allItemsProvider = StreamProvider<List<ShoppingItem>>(
  (ref) => ref.watch(repositoryProvider).watchAllItems(),
);
final listItemsProvider = StreamProvider.family<List<ShoppingItem>, String>(
  (ref, listId) => ref.watch(repositoryProvider).watchItemsForList(listId),
);
final sessionsProvider = StreamProvider<List<ShoppingSession>>(
  (ref) => ref.watch(repositoryProvider).watchSessions(),
);
final sessionItemsProvider =
    StreamProvider.family<List<ShoppingSessionItem>, String>(
      (ref, sessionId) =>
          ref.watch(repositoryProvider).watchSessionItems(sessionId),
    );
final settingsProvider = StreamProvider<SettingsEntry>(
  (ref) => ref.watch(repositoryProvider).watchSettings(),
);

final actionsProvider = Provider(
  (ref) => NearBuyActions(
    ref.watch(repositoryProvider),
    ref.watch(geofenceServiceProvider),
  ),
);

final locationStatusProvider =
    AsyncNotifierProvider<LocationController, LocationSnapshot>(
      LocationController.new,
    );

class LocationController extends AsyncNotifier<LocationSnapshot> {
  LocationService get _service => ref.read(locationServiceProvider);

  @override
  Future<LocationSnapshot> build() => _service.status();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_service.status);
  }

  Future<void> requestForeground() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_service.requestForeground);
  }

  Future<void> requestBackground() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_service.requestBackground);
    if (state.value?.canUseBackground ?? false) {
      await ref.read(geofenceServiceProvider).sync();
    }
  }
}

class NearBuyActions {
  NearBuyActions(this.repository, this.geofences);

  final NearBuyRepository repository;
  final GeofenceService geofences;

  Future<String> saveList({
    String? listId,
    required String name,
    StoreDraft? store,
    List<ItemDraft> items = const [],
  }) async {
    final id = await repository.saveList(
      listId: listId,
      name: name,
      storeDraft: store,
      initialItems: items,
    );
    await _sync();
    return id;
  }

  Future<void> deleteList(String id) async {
    await repository.deleteList(id);
    await _sync();
  }

  Future<void> addItem(String listId, ItemDraft item) async {
    await repository.addItem(listId, item);
    await _sync();
  }

  Future<void> updateItem(
    ShoppingItem item, {
    String? name,
    String? quantity,
    String? note,
  }) => repository.updateItem(item, name: name, quantity: quantity, note: note);

  Future<void> toggleItem(ShoppingItem item) async {
    await repository.toggleItem(item);
    await _sync();
  }

  Future<void> deleteItem(ShoppingItem item) async {
    await repository.deleteItem(item);
    await _sync();
  }

  Future<void> reorderItems(String listId, int oldIndex, int newIndex) =>
      repository.reorderItems(listId, oldIndex, newIndex);

  Future<void> restoreItems(String listId) async {
    await repository.restoreItems(listId);
    await _sync();
  }

  Future<void> clearCompleted(String listId) async {
    await repository.clearCompleted(listId);
    await _sync();
  }

  Future<void> setGeofenceEnabled(String storeId, bool enabled) async {
    await repository.setGeofenceEnabled(storeId, enabled);
    await _sync();
  }

  Future<void> updateSettings(SettingsEntriesCompanion values) async {
    await repository.updateSettings(values);
    await _sync();
  }

  Future<void> clearHistory() => repository.clearHistory();

  Future<void> deleteAllData() async {
    await repository.deleteAllData();
    await geofences.removeAll();
  }

  Future<void> _sync() async {
    try {
      await geofences.sync();
    } catch (_) {
      // The data operation remains valid if OS registration is temporarily unavailable.
    }
  }
}
