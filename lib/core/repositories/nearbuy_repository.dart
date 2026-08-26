import 'package:drift/drift.dart';
import 'package:nearbuy/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

class ItemDraft {
  const ItemDraft({required this.name, this.quantity = '1', this.note});

  final String name;
  final String quantity;
  final String? note;
}

class StoreDraft {
  const StoreDraft({
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.geofenceRadius,
    required this.geofenceEnabled,
  });

  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final String address;
  final int geofenceRadius;
  final bool geofenceEnabled;
}

class NearBuyRepository {
  NearBuyRepository(this.database);

  final AppDatabase database;
  final Uuid _uuid = const Uuid();

  Stream<List<ShoppingList>> watchLists() => database.watchLists();
  Stream<List<Store>> watchStores() => database.watchStores();
  Stream<List<ShoppingItem>> watchAllItems() => database.watchAllItems();
  Stream<List<ShoppingItem>> watchItemsForList(String id) =>
      database.watchItemsForList(id);
  Stream<List<ShoppingSession>> watchSessions() => database.watchSessions();
  Stream<List<ShoppingSessionItem>> watchSessionItems(String id) =>
      database.watchSessionItems(id);
  Stream<SettingsEntry> watchSettings() => database.watchSettings();
  Future<SettingsEntry> readSettings() => database.readSettings();
  Future<ShoppingList?> findList(String id) => database.findList(id);
  Future<Store?> findStore(String id) => database.findStore(id);
  Future<List<ShoppingItem>> itemsForList(String id) =>
      database.itemsForList(id);

  Future<String> saveList({
    String? listId,
    required String name,
    StoreDraft? storeDraft,
    List<ItemDraft> initialItems = const [],
  }) async {
    final now = DateTime.now();
    final id = listId ?? _uuid.v4();

    await database.transaction(() async {
      final existing = listId == null ? null : await database.findList(listId);
      String? storeId = existing?.storeId;

      if (storeDraft == null) {
        if (storeId != null) {
          await (database.delete(
            database.stores,
          )..where((row) => row.id.equals(storeId!))).go();
          storeId = null;
        }
      } else if (storeId == null) {
        storeId = _uuid.v4();
        await database
            .into(database.stores)
            .insert(
              StoresCompanion.insert(
                id: storeId,
                name: storeDraft.name.trim(),
                category: Value(storeDraft.category),
                latitude: storeDraft.latitude,
                longitude: storeDraft.longitude,
                address: Value(storeDraft.address.trim()),
                geofenceRadius: Value(storeDraft.geofenceRadius),
                geofenceEnabled: Value(storeDraft.geofenceEnabled),
                createdAt: now,
              ),
            );
      } else {
        await (database.update(
          database.stores,
        )..where((row) => row.id.equals(storeId!))).write(
          StoresCompanion(
            name: Value(storeDraft.name.trim()),
            category: Value(storeDraft.category),
            latitude: Value(storeDraft.latitude),
            longitude: Value(storeDraft.longitude),
            address: Value(storeDraft.address.trim()),
            geofenceRadius: Value(storeDraft.geofenceRadius),
            geofenceEnabled: Value(storeDraft.geofenceEnabled),
          ),
        );
      }

      if (existing == null) {
        await database
            .into(database.shoppingLists)
            .insert(
              ShoppingListsCompanion.insert(
                id: id,
                name: name.trim(),
                storeId: Value(storeId),
                createdAt: now,
                updatedAt: now,
              ),
            );
        for (var index = 0; index < initialItems.length; index++) {
          final draft = initialItems[index];
          if (draft.name.trim().isEmpty) continue;
          await database
              .into(database.shoppingItems)
              .insert(
                ShoppingItemsCompanion.insert(
                  id: _uuid.v4(),
                  shoppingListId: id,
                  name: draft.name.trim(),
                  quantity: Value(
                    draft.quantity.trim().isEmpty ? '1' : draft.quantity.trim(),
                  ),
                  note: Value(
                    draft.note?.trim().isEmpty == true
                        ? null
                        : draft.note?.trim(),
                  ),
                  createdAt: now,
                  sortOrder: index,
                ),
              );
        }
      } else {
        await (database.update(
          database.shoppingLists,
        )..where((row) => row.id.equals(id))).write(
          ShoppingListsCompanion(
            name: Value(name.trim()),
            storeId: Value(storeId),
            updatedAt: Value(now),
          ),
        );
      }
    });
    return id;
  }

  Future<void> deleteList(String listId) async {
    await database.transaction(() async {
      final list = await database.findList(listId);
      await (database.delete(
        database.shoppingLists,
      )..where((row) => row.id.equals(listId))).go();
      if (list?.storeId != null) {
        await (database.delete(
          database.stores,
        )..where((row) => row.id.equals(list!.storeId!))).go();
      }
    });
  }

  Future<void> addItem(String listId, ItemDraft draft) async {
    final current = await database.itemsForList(listId);
    await database
        .into(database.shoppingItems)
        .insert(
          ShoppingItemsCompanion.insert(
            id: _uuid.v4(),
            shoppingListId: listId,
            name: draft.name.trim(),
            quantity: Value(
              draft.quantity.trim().isEmpty ? '1' : draft.quantity.trim(),
            ),
            note: Value(
              draft.note?.trim().isEmpty == true ? null : draft.note?.trim(),
            ),
            createdAt: DateTime.now(),
            sortOrder: current.length,
          ),
        );
    await _touchList(listId);
  }

  Future<void> updateItem(
    ShoppingItem item, {
    String? name,
    String? quantity,
    String? note,
  }) async {
    await (database.update(
      database.shoppingItems,
    )..where((row) => row.id.equals(item.id))).write(
      ShoppingItemsCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        quantity: quantity == null
            ? const Value.absent()
            : Value(quantity.trim().isEmpty ? '1' : quantity.trim()),
        note: note == null
            ? const Value.absent()
            : Value(note.trim().isEmpty ? null : note.trim()),
      ),
    );
    await _touchList(item.shoppingListId);
  }

  Future<void> toggleItem(ShoppingItem item) async {
    final completed = !item.completed;
    await (database.update(
      database.shoppingItems,
    )..where((row) => row.id.equals(item.id))).write(
      ShoppingItemsCompanion(
        completed: Value(completed),
        completedAt: Value(completed ? DateTime.now() : null),
      ),
    );
    await _touchList(item.shoppingListId);
  }

  Future<void> deleteItem(ShoppingItem item) async {
    await (database.delete(
      database.shoppingItems,
    )..where((row) => row.id.equals(item.id))).go();
    await _normalizeOrder(item.shoppingListId);
    await _touchList(item.shoppingListId);
  }

  Future<void> reorderItems(String listId, int oldIndex, int newIndex) async {
    final values = await database.itemsForList(listId);
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = values.removeAt(oldIndex);
    values.insert(newIndex, moved);
    await database.batch((batch) {
      for (var index = 0; index < values.length; index++) {
        batch.update(
          database.shoppingItems,
          ShoppingItemsCompanion(sortOrder: Value(index)),
          where: (row) => row.id.equals(values[index].id),
        );
      }
    });
    await _touchList(listId);
  }

  Future<void> restoreItems(String listId) async {
    await (database.update(
      database.shoppingItems,
    )..where((row) => row.shoppingListId.equals(listId))).write(
      const ShoppingItemsCompanion(
        completed: Value(false),
        completedAt: Value(null),
      ),
    );
    await _touchList(listId);
  }

  Future<void> clearCompleted(String listId) async {
    await (database.delete(database.shoppingItems)..where(
          (row) =>
              row.shoppingListId.equals(listId) & row.completed.equals(true),
        ))
        .go();
    await _normalizeOrder(listId);
    await _touchList(listId);
  }

  Future<void> setGeofenceEnabled(String storeId, bool enabled) =>
      (database.update(database.stores)..where((row) => row.id.equals(storeId)))
          .write(StoresCompanion(geofenceEnabled: Value(enabled)));

  Future<void> saveSession({
    required ShoppingList list,
    Store? store,
    required DateTime startedAt,
    required Duration duration,
    required List<ShoppingItem> purchasedItems,
  }) async {
    final sessionId = _uuid.v4();
    await database.transaction(() async {
      await database
          .into(database.shoppingSessions)
          .insert(
            ShoppingSessionsCompanion.insert(
              id: sessionId,
              shoppingListId: Value(list.id),
              storeId: Value(store?.id),
              storeName: store?.name ?? list.name,
              storeCategory: Value(store?.category),
              startedAt: startedAt,
              completedAt: DateTime.now(),
              durationSeconds: duration.inSeconds,
              itemsPurchasedCount: purchasedItems.length,
            ),
          );
      for (final item in purchasedItems) {
        await database
            .into(database.shoppingSessionItems)
            .insert(
              ShoppingSessionItemsCompanion.insert(
                id: _uuid.v4(),
                sessionId: sessionId,
                itemName: item.name,
                quantity: item.quantity,
                note: Value(item.note),
              ),
            );
      }
    });
  }

  Future<void> updateSettings(SettingsEntriesCompanion values) =>
      (database.update(
        database.settingsEntries,
      )..where((row) => row.id.equals('main'))).write(values);

  Future<void> clearHistory() => database.transaction(() async {
    await database.delete(database.shoppingSessionItems).go();
    await database.delete(database.shoppingSessions).go();
  });

  Future<void> deleteAllData() => database.transaction(() async {
    await database.delete(database.shoppingSessionItems).go();
    await database.delete(database.shoppingSessions).go();
    await database.delete(database.shoppingItems).go();
    await database.delete(database.shoppingLists).go();
    await database.delete(database.stores).go();
    await (database.update(
      database.settingsEntries,
    )..where((row) => row.id.equals('main'))).write(
      const SettingsEntriesCompanion(
        themeMode: Value('system'),
        defaultRadius: Value(700),
        cooldownHours: Value(3),
        notificationsEnabled: Value(true),
        soundEnabled: Value(true),
        vibrationEnabled: Value(true),
      ),
    );
  });

  Future<void> _normalizeOrder(String listId) async {
    final values = await database.itemsForList(listId);
    await database.batch((batch) {
      for (var index = 0; index < values.length; index++) {
        batch.update(
          database.shoppingItems,
          ShoppingItemsCompanion(sortOrder: Value(index)),
          where: (row) => row.id.equals(values[index].id),
        );
      }
    });
  }

  Future<void> _touchList(String listId) =>
      (database.update(database.shoppingLists)
            ..where((row) => row.id.equals(listId)))
          .write(ShoppingListsCompanion(updatedAt: Value(DateTime.now())));
}
