import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nearbuy/core/database/app_database.dart';
import 'package:nearbuy/core/repositories/nearbuy_repository.dart';
import 'package:nearbuy/core/widgets/async_error_view.dart';
import 'package:nearbuy/providers.dart';

class ListDetailScreen extends ConsumerWidget {
  const ListDetailScreen({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listsAsync = ref.watch(listsProvider);
    final itemsAsync = ref.watch(listItemsProvider(listId));
    final stores = ref.watch(storesProvider).value ?? const <Store>[];

    if (listsAsync.hasError) {
      return Scaffold(body: AsyncErrorView(error: listsAsync.error!));
    }
    if (itemsAsync.hasError) {
      return Scaffold(body: AsyncErrorView(error: itemsAsync.error!));
    }
    final lists = listsAsync.value;
    final items = itemsAsync.value;
    if (lists == null || items == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final list = _firstWhereOrNull(lists, (entry) => entry.id == listId);
    if (list == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'List not found',
          message: 'This list may have been deleted.',
        ),
      );
    }
    final store = _firstWhereOrNull(
      stores,
      (entry) => entry.id == list.storeId,
    );
    final completed = items.where((item) => item.completed).length;
    final remaining = items.length - completed;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          list.name,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (action) async {
              switch (action) {
                case 'edit':
                  await context.push('/lists/$listId/edit');
                case 'restore':
                  await ref.read(actionsProvider).restoreItems(listId);
                case 'clear':
                  await ref.read(actionsProvider).clearCompleted(listId);
                case 'delete':
                  if (!context.mounted) return;
                  final confirmed = await _confirm(
                    context,
                    title: 'Delete ${list.name}?',
                    message:
                        'The list, its items, and linked store will be permanently removed.',
                  );
                  if (confirmed) {
                    await ref.read(actionsProvider).deleteList(listId);
                    if (context.mounted) context.go('/');
                  }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_location_alt_outlined),
                  title: Text('Edit list & store'),
                ),
              ),
              PopupMenuItem(
                value: 'restore',
                child: ListTile(
                  leading: Icon(Icons.restore_rounded),
                  title: Text('Restore checked'),
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.playlist_remove_rounded),
                  title: Text('Clear completed'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Delete list'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          store == null
                              ? Icons.location_off_outlined
                              : Icons.storefront_outlined,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            store == null
                                ? 'Normal list · no store linked'
                                : '${store.name} · ${store.geofenceRadius} m radius',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '$completed / ${items.length}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: items.isEmpty ? 0 : completed / items.length,
                      minHeight: 9,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    if (store != null && store.address.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          store.address,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.playlist_add_rounded,
                    title: 'This list is empty',
                    message: 'Add the first item below.',
                    action: FilledButton.icon(
                      onPressed: () =>
                          _showItemDialog(context, ref, listId: listId),
                      icon: const Icon(Icons.add),
                      label: const Text('Add item'),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                    itemCount: items.length,
                    onReorder: (oldIndex, newIndex) => ref
                        .read(actionsProvider)
                        .reorderItems(listId, oldIndex, newIndex),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Card(
                        key: ValueKey(item.id),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: () =>
                              ref.read(actionsProvider).toggleItem(item),
                          leading: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: Icon(
                              item.completed
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              key: ValueKey(item.completed),
                              color: item.completed
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                          ),
                          title: Text(
                            item.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              decoration: item.completed
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if (item.quantity.isNotEmpty) item.quantity,
                              if (item.note?.isNotEmpty ?? false) item.note!,
                            ].join(' · '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit item',
                                onPressed: () => _showItemDialog(
                                  context,
                                  ref,
                                  listId: listId,
                                  item: item,
                                ),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                              ),
                              IconButton(
                                tooltip: 'Delete item',
                                onPressed: () =>
                                    ref.read(actionsProvider).deleteItem(item),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 20,
                                ),
                              ),
                              const Icon(Icons.drag_handle_rounded),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (remaining > 0)
            FilledButton.icon(
              onPressed: () => context.push('/shopping/$listId'),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start shopping'),
            ),
          const SizedBox(height: 10),
          FloatingActionButton.small(
            heroTag: 'add-item',
            onPressed: () => _showItemDialog(context, ref, listId: listId),
            tooltip: 'Add item',
            child: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

Future<void> _showItemDialog(
  BuildContext context,
  WidgetRef ref, {
  required String listId,
  ShoppingItem? item,
}) async {
  final name = TextEditingController(text: item?.name);
  final quantity = TextEditingController(text: item?.quantity ?? '1');
  final note = TextEditingController(text: item?.note);
  final formKey = GlobalKey<FormState>();
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(item == null ? 'Add item' : 'Edit item'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Item name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter an item name'
                  : null,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: quantity,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(context, true);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (saved == true) {
    if (item == null) {
      await ref
          .read(actionsProvider)
          .addItem(
            listId,
            ItemDraft(
              name: name.text,
              quantity: quantity.text,
              note: note.text,
            ),
          );
    } else {
      await ref
          .read(actionsProvider)
          .updateItem(
            item,
            name: name.text,
            quantity: quantity.text,
            note: note.text,
          );
    }
  }
  name.dispose();
  quantity.dispose();
  note.dispose();
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
}) async =>
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
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ??
    false;

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}
