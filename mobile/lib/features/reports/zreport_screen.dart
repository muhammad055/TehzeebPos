import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import 'reports_provider.dart';

/// Read-only view of the current open shift. Closing a shift (which resets it
/// and prints the Z-Report) stays a counter/web action by design.
class ZReportScreen extends ConsumerWidget {
  const ZReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final z = ref.watch(zReportProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Z-Report (current shift)')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(zReportProvider);
          await ref.read(zReportProvider.future).then((_) {}, onError: (_) {});
        },
        child: z.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(children: [
                Text(e.toString().replaceFirst('Exception: ', ''), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(zReportProvider),
                  child: const Text('Retry'),
                ),
              ]),
            ),
          ]),
          data: (r) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Report #${r.nextReportNumber}',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(r.shiftStartIso == null
                  ? 'Shift started: beginning of records'
                  : 'Shift started: ${formatUaeDateTime(parseUtc(r.shiftStartIso!))}'),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    _Line('Orders', '${r.totalOrders}'),
                    _Line('Net sales (before tax)', aed.format(r.netSales)),
                    _Line('Discounts', aed.format(r.discounts)),
                    _Line('Tax', aed.format(r.taxTotal)),
                    const Divider(),
                    _Line('Gross sales', aed.format(r.grossSales), bold: true),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              Text('Top items', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: r.topItems.isEmpty
                    ? const Padding(padding: EdgeInsets.all(16), child: Text('No sales this shift.'))
                    : Column(children: [
                        for (final i in r.topItems)
                          ListTile(
                            dense: true,
                            title: Text(i.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${i.qty} sold'),
                            trailing: Text(aed.format(i.revenue)),
                          ),
                      ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.w700) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
