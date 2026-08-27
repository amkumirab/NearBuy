import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nearbuy/core/database/app_database.dart';
import 'package:nearbuy/core/repositories/nearbuy_repository.dart';

void main() {
  late AppDatabase database;
  late NearBuyRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = NearBuyRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('creates a local list with its store and ordered items', () async {
    final listId = await repository.saveList(
      name: 'Weekly groceries',
      storeDraft: const StoreDraft(
        name: 'Neighbourhood market',
        category: 'Groceries',
        latitude: 45.4642,
        longitude: 9.19,
        address: 'Milan',
        geofenceRadius: 700,
        geofenceEnabled: true,
      ),
      initialItems: const [
        ItemDraft(name: 'Milk', quantity: '2'),
        ItemDraft(name: 'Bread'),
      ],
    );

    final list = await repository.findList(listId);
    final store = await repository.findStore(list!.storeId!);
    final items = await repository.itemsForList(listId);

    expect(list.name, 'Weekly groceries');
    expect(store?.name, 'Neighbourhood market');
    expect(store?.geofenceRadius, 700);
    expect(items.map((item) => item.name), ['Milk', 'Bread']);
    expect(items.map((item) => item.sortOrder), [0, 1]);
  });

  test('deleting a list also removes its private store and items', () async {
    final listId = await repository.saveList(
      name: 'Pharmacy',
      storeDraft: const StoreDraft(
        name: 'Local pharmacy',
        category: 'Pharmacy',
        latitude: 45,
        longitude: 9,
        address: '',
        geofenceRadius: 500,
        geofenceEnabled: true,
      ),
      initialItems: const [ItemDraft(name: 'Vitamins')],
    );
    final storeId = (await repository.findList(listId))!.storeId!;

    await repository.deleteList(listId);

    expect(await repository.findList(listId), isNull);
    expect(await repository.findStore(storeId), isNull);
    expect(await repository.itemsForList(listId), isEmpty);
  });

  test(
    'reminder candidate requires pending items and respects cooldown',
    () async {
      final listId = await repository.saveList(
        name: 'Hardware run',
        storeDraft: const StoreDraft(
          name: 'Hardware store',
          category: 'Hardware',
          latitude: 45,
          longitude: 9,
          address: '',
          geofenceRadius: 1000,
          geofenceEnabled: true,
        ),
        initialItems: const [ItemDraft(name: 'Screws')],
      );
      final list = (await repository.findList(listId))!;

      final first = await database.reminderCandidate(list.storeId!);
      expect(first?.pendingItems.single.name, 'Screws');

      await database.markStoreNotified(list.storeId!);
      expect(await database.reminderCandidate(list.storeId!), isNull);

      final item = (await repository.itemsForList(listId)).single;
      await repository.toggleItem(item);
      await repository.updateSettings(
        const SettingsEntriesCompanion(cooldownHours: Value(0)),
      );
      expect(await database.reminderCandidate(list.storeId!), isNull);
    },
  );

  test('deleting all data restores privacy-safe defaults', () async {
    await repository.updateSettings(
      const SettingsEntriesCompanion(
        themeMode: Value('dark'),
        defaultRadius: Value(2000),
        notificationsEnabled: Value(false),
      ),
    );
    await repository.saveLastMapLocation(45.4642, 9.19);

    await repository.deleteAllData();
    final settings = await repository.readSettings();

    expect(settings.themeMode, 'system');
    expect(settings.defaultRadius, 700);
    expect(settings.notificationsEnabled, isTrue);
    expect(settings.lastMapLatitude, isNull);
    expect(settings.lastMapLongitude, isNull);
  });

  test('remembers the last confirmed map location', () async {
    await repository.saveLastMapLocation(35.6892, 51.3890);

    final settings = await repository.readSettings();

    expect(settings.lastMapLatitude, 35.6892);
    expect(settings.lastMapLongitude, 51.3890);
  });
}
