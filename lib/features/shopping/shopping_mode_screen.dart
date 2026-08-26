import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nearbuy/core/database/app_database.dart';
import 'package:nearbuy/core/widgets/async_error_view.dart';
import 'package:nearbuy/providers.dart';

class ShoppingModeScreen extends ConsumerStatefulWidget {
  const ShoppingModeScreen({super.key, required this.listId});

  final String listId;

  @override
  ConsumerState<ShoppingModeScreen> createState() => _ShoppingModeScreenState();
}

class _ShoppingModeScreenState extends ConsumerState<ShoppingModeScreen> {
  final DateTime _startedAt = DateTime.now();
  final Set<String> _initialCompletedIds = {};
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _capturedInitialState = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsed = DateTime.now().difference(_startedAt));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lists = ref.watch(listsProvider).value;
    final stores = ref.watch(storesProvider).value ?? const <Store>[];
    final itemsAsync = ref.watch(listItemsProvider(widget.listId));
    final list = lists == null
        ? null
        : _first(lists, (entry) => entry.id == widget.listId);
    final store = list == null
        ? null
        : _first(stores, (entry) => entry.id == list.storeId);

    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07111F),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              list == null
                  ? 'Shopping mode'
                  : 'Shopping at ${store?.name ?? list.name}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            Text(
              _formatDuration(_elapsed),
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncErrorView(error: error),
        data: (items) {
          if (!_capturedInitialState) {
            _initialCompletedIds.addAll(
              items.where((item) => item.completed).map((item) => item.id),
            );
            _capturedInitialState = true;
          }
          if (list == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'List not found',
              message: 'Return to Home and choose another list.',
            );
          }
          final completed = items.where((item) => item.completed).length;
          final newlyPurchased = items
              .where(
                (item) =>
                    item.completed && !_initialCompletedIds.contains(item.id),
              )
              .toList();
          final allCompleted = items.isNotEmpty && completed == items.length;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$completed of ${items.length} complete',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${newlyPurchased.length} this trip',
                          style: const TextStyle(color: Color(0xFF6EE7B7)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: items.isEmpty ? 0 : completed / items.length,
                      minHeight: 10,
                      color: const Color(0xFF10B981),
                      backgroundColor: Colors.white12,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ],
                ),
              ),
              if (allCompleted)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF047857), Color(0xFF0F766E)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.emoji_events_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Shopping completed! Save this trip to History.',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 110),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Material(
                      color: item.completed
                          ? Colors.white.withValues(alpha: .045)
                          : const Color(0xFF122033),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () async {
                          await HapticFeedback.selectionClick();
                          await ref.read(actionsProvider).toggleItem(item);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                item.completed
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: item.completed
                                    ? const Color(0xFF34D399)
                                    : Colors.white54,
                                size: 29,
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: TextStyle(
                                        color: item.completed
                                            ? Colors.white38
                                            : Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        decoration: item.completed
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                    if (item.quantity.isNotEmpty ||
                                        (item.note?.isNotEmpty ?? false))
                                      Text(
                                        [
                                          item.quantity,
                                          if (item.note?.isNotEmpty ?? false)
                                            item.note!,
                                        ].join(' · '),
                                        style: const TextStyle(
                                          color: Colors.white54,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: itemsAsync.value == null || list == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () =>
                          ref.read(actionsProvider).restoreItems(widget.listId),
                      icon: const Icon(Icons.restore_rounded),
                      label: const Text('Restore'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed:
                          _saving || _newlyPurchased(itemsAsync.value!).isEmpty
                          ? null
                          : () => _finish(
                              list,
                              store,
                              _newlyPurchased(itemsAsync.value!),
                            ),
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: const Text('Finish & save'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  List<ShoppingItem> _newlyPurchased(List<ShoppingItem> items) => items
      .where(
        (item) => item.completed && !_initialCompletedIds.contains(item.id),
      )
      .toList();

  Future<void> _finish(
    ShoppingList list,
    Store? store,
    List<ShoppingItem> purchased,
  ) async {
    setState(() => _saving = true);
    await ref
        .read(repositoryProvider)
        .saveSession(
          list: list,
          store: store,
          startedAt: _startedAt,
          duration: _elapsed,
          purchasedItems: purchased,
        );
    if (mounted) context.go('/history');
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

T? _first<T>(Iterable<T> values, bool Function(T) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}
