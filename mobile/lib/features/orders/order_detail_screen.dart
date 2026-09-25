import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import 'order_model.dart';
import 'orders_provider.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});
  final int orderId;

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref, PosOrder o) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancel order #${o.tokenNumber}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The order stays in history but is excluded from sales totals. This cannot be undone.'),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep order')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (confirmed != true) return;

    final error = await cancelOrder(ref, o.id, text.isEmpty ? null : text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Order cancelled.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider(orderId));
    return Scaffold(
      appBar: AppBar(title: const Text('Order')),
      body: order.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString().replaceFirst('Exception: ', ''))),
        data: (o) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Token #${o.tokenNumber}', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('${formatUaeDateTime(o.orderDate)} · ${o.paymentMethod}'),
            if (o.isCancelled) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Cancelled${o.cancelledAt != null ? ' on ${formatUaeDateTime(o.cancelledAt!)}' : ''}'
                    '${o.cancelReason != null ? '\nReason: ${o.cancelReason}' : ''}',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final i in o.items)
                    ListTile(
                      title: Text(i.dishName),
                      subtitle: Text('${i.quantity} × ${aed.format(i.unitPrice)}'),
                      trailing: Text(aed.format(i.lineTotal)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Row('Subtotal', aed.format(o.subTotal)),
            if (o.discount > 0) _Row('Discount', '- ${aed.format(o.discount)}'),
            _Row('Tax', aed.format(o.taxTotal)),
            const Divider(),
            _Row('Total', aed.format(o.grandTotal), bold: true),
            if (!o.isCancelled) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                onPressed: () => _confirmCancel(context, ref, o),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel order'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
