import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:nearbuy/core/database/app_database.dart';
import 'package:nearbuy/core/widgets/async_error_view.dart';
import 'package:nearbuy/providers.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionsProvider);
    return sessionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AsyncErrorView(error: error),
      data: (sessions) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          const Text(
            'Shopping history',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            '${sessions.length} completed ${sessions.length == 1 ? 'session' : 'sessions'}',
          ),
          const SizedBox(height: 18),
          if (sessions.isEmpty)
            const EmptyState(
              icon: Icons.history_rounded,
              title: 'No shopping history yet',
              message:
                  'Finish a trip in Shopping Mode to save its duration and purchased items.',
            )
          else
            ...sessions.map((session) => _SessionCard(session: session)),
        ],
      ),
    );
  }
}

class _SessionCard extends ConsumerWidget {
  const _SessionCard({required this.session});
  final ShoppingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref.watch(sessionItemsProvider(session.id)).value ??
        const <ShoppingSessionItem>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ExpansionTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(
              Icons.receipt_long_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          title: Text(
            session.storeName,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            '${DateFormat.yMMMMd().format(session.completedAt)} · ${_duration(session.durationSeconds)}',
          ),
          trailing: Chip(label: Text('${session.itemsPurchasedCount} items')),
          children: [
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No item details saved.'),
              )
            else
              ...items.map(
                (item) => ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 20,
                  ),
                  title: Text(item.itemName),
                  subtitle: item.note == null ? null : Text(item.note!),
                  trailing: Text(item.quantity),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _duration(int seconds) {
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  if (minutes == 0) return '${remaining}s';
  return '${minutes}m ${remaining == 0 ? '' : '${remaining}s'}'.trim();
}
