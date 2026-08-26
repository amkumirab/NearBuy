import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class Stores extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get category => text().withDefault(const Constant('Other'))();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  TextColumn get address => text().withDefault(const Constant(''))();
  IntColumn get geofenceRadius => integer().withDefault(const Constant(700))();
  BoolColumn get geofenceEnabled =>
      boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastNotificationAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ShoppingLists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get storeId =>
      text().nullable().references(Stores, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ShoppingItems extends Table {
  TextColumn get id => text()();
  TextColumn get shoppingListId =>
      text().references(ShoppingLists, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 160)();
  TextColumn get quantity => text().withDefault(const Constant('1'))();
  TextColumn get note => text().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ShoppingSessions extends Table {
  TextColumn get id => text()();
  TextColumn get shoppingListId => text().nullable()();
  TextColumn get storeId => text().nullable()();
  TextColumn get storeName => text()();
  TextColumn get storeCategory => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime()();
  IntColumn get durationSeconds => integer()();
  IntColumn get itemsPurchasedCount => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ShoppingSessionItems extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(ShoppingSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get itemName => text()();
  TextColumn get quantity => text()();
  TextColumn get note => text().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SettingsEntries extends Table {
  TextColumn get id => text().withDefault(const Constant('main'))();
  TextColumn get themeMode => text().withDefault(const Constant('system'))();
  IntColumn get defaultRadius => integer().withDefault(const Constant(700))();
  IntColumn get cooldownHours => integer().withDefault(const Constant(3))();
  BoolColumn get notificationsEnabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get soundEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get vibrationEnabled =>
      boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Stores,
    ShoppingLists,
    ShoppingItems,
    ShoppingSessions,
    ShoppingSessionItems,
    SettingsEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  AppDatabase.defaults() : super(driftDatabase(name: 'nearbuy'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await into(settingsEntries).insert(
        const SettingsEntriesCompanion(id: Value('main')),
        mode: InsertMode.insertOrIgnore,
      );
    },
  );

  Stream<List<ShoppingList>> watchLists() =>
      (select(shoppingLists)
            ..where((row) => row.archived.equals(false))
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
          .watch();

  Stream<List<Store>> watchStores() => select(stores).watch();

  Stream<List<ShoppingItem>> watchAllItems() => (select(
    shoppingItems,
  )..orderBy([(row) => OrderingTerm.asc(row.sortOrder)])).watch();

  Stream<List<ShoppingItem>> watchItemsForList(String listId) =>
      (select(shoppingItems)
            ..where((row) => row.shoppingListId.equals(listId))
            ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
          .watch();

  Stream<List<ShoppingSession>> watchSessions() => (select(
    shoppingSessions,
  )..orderBy([(row) => OrderingTerm.desc(row.completedAt)])).watch();

  Stream<List<ShoppingSessionItem>> watchSessionItems(String sessionId) =>
      (select(
        shoppingSessionItems,
      )..where((row) => row.sessionId.equals(sessionId))).watch();

  Stream<SettingsEntry> watchSettings() => (select(
    settingsEntries,
  )..where((row) => row.id.equals('main'))).watchSingle();

  Future<SettingsEntry> readSettings() => (select(
    settingsEntries,
  )..where((row) => row.id.equals('main'))).getSingle();

  Future<ShoppingList?> findList(String id) => (select(
    shoppingLists,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<Store?> findStore(String id) =>
      (select(stores)..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<List<ShoppingItem>> itemsForList(String listId) =>
      (select(shoppingItems)
            ..where((row) => row.shoppingListId.equals(listId))
            ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
          .get();

  Future<List<GeofenceRegistration>> activeGeofenceRegistrations() async {
    final allStores = await select(stores).get();
    final allLists = await (select(
      shoppingLists,
    )..where((row) => row.archived.equals(false))).get();
    final allItems = await select(shoppingItems).get();

    final registrations = <GeofenceRegistration>[];
    for (final store in allStores.where((store) => store.geofenceEnabled)) {
      final listsForStore = allLists.where((list) => list.storeId == store.id);
      final pending = listsForStore.fold<int>(
        0,
        (count, list) =>
            count +
            allItems
                .where(
                  (item) => item.shoppingListId == list.id && !item.completed,
                )
                .length,
      );
      if (pending > 0) registrations.add(GeofenceRegistration(store: store));
    }
    return registrations;
  }

  Future<ReminderCandidate?> reminderCandidate(String storeId) async {
    final settings = await readSettings();
    if (!settings.notificationsEnabled) return null;
    final store = await findStore(storeId);
    if (store == null || !store.geofenceEnabled) return null;

    final list =
        await (select(shoppingLists)..where(
              (row) => row.storeId.equals(storeId) & row.archived.equals(false),
            ))
            .getSingleOrNull();
    if (list == null) return null;

    final pendingItems =
        await (select(shoppingItems)..where(
              (row) =>
                  row.shoppingListId.equals(list.id) &
                  row.completed.equals(false),
            ))
            .get();
    if (pendingItems.isEmpty) return null;

    final last = store.lastNotificationAt;
    if (last != null &&
        DateTime.now().difference(last) <
            Duration(hours: settings.cooldownHours)) {
      return null;
    }
    return ReminderCandidate(
      store: store,
      list: list,
      pendingItems: pendingItems,
    );
  }

  Future<void> markStoreNotified(String storeId) =>
      (update(stores)..where((row) => row.id.equals(storeId))).write(
        StoresCompanion(lastNotificationAt: Value(DateTime.now())),
      );
}

class GeofenceRegistration {
  const GeofenceRegistration({required this.store});

  final Store store;
}

class ReminderCandidate {
  const ReminderCandidate({
    required this.store,
    required this.list,
    required this.pendingItems,
  });

  final Store store;
  final ShoppingList list;
  final List<ShoppingItem> pendingItems;
}
