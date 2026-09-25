import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import 'orders_provider.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  Future<void> _pickDate(BuildContext context, WidgetRef ref) async {
    final current = ref.read(ordersDateProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2024),
      lastDate: uaeToday(),
    );
    if (picked != null) ref.read(ordersDateProvider.notifier).state = picked;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(ordersDateProvider);
    final orders = ref.watch(ordersProvider);
    final isToday = date == uaeToday();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        actions: [
          TextButton.icon(
            onPressed: () => _pickDate(context, ref),
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(isToday ? 'Today' : DateFormat('d MMM y').format(date)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(ordersProvider);
          await ref.read(ordersProvider.future).then((_) {}, onError: (_) {});
        },
        child: orders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(children: [
                Text(e.toString().replaceFirst('Exception: ', ''),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(ordersProvider),
                  child: const Text('Retry'),
                ),
              ]),
            ),
          ]),
          data: (list) {
            if (list.isEmpty) {
              return ListView(children: const [
                Padding(padding: EdgeInsets.all(48), child: Center(child: Text('No orders on this day.'))),
              ]);
            }
            final live = list.where((o) => !o.isCancelled);
            final total = live.fold<double>(0, (a, o) => a + o.grandTotal);
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '${live.length} orders · ${aed.format(total)}'
                    '${list.length != live.length ? ' · ${list.length - live.length} cancelled' : ''}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                for (final o in list)
                  ListTile(
                    onTap: () => context.push('/orders/${o.id}'),
                    leading: CircleAvatar(child: Text('${o.tokenNumber}')),
                    title: Text(
                      aed.format(o.grandTotal),
                      style: o.isCancelled
                          ? const TextStyle(decoration: TextDecoration.lineThrough)
                          : null,
                    ),
                    subtitle: Text(
                        '${formatUaeTime(o.orderDate)} · ${o.paymentMethod} · ${o.items.length} items'),
                    trailing: o.isCancelled
                        ? Chip(
                            label: const Text('Cancelled'),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: Theme.of(context).colorScheme.errorContainer,
                          )
                        : const Icon(Icons.chevron_right),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
