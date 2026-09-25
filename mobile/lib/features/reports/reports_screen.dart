import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import 'reports_provider.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final f = ref.read(reportFilterProvider);
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: f.range,
      firstDate: DateTime(2024),
      lastDate: uaeToday(),
    );
    if (picked != null) {
      ref.read(reportFilterProvider.notifier).state = f.copyWith(range: picked);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportFilterProvider);
    final report = ref.watch(reportProvider);
    final dishes = ref.watch(dishesProvider);
    final fmt = DateFormat('d MMM');
    final sameDay = filter.range.start == filter.range.end;

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(reportProvider);
          await ref.read(reportProvider.future).then((_) {}, onError: (_) {});
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickRange(context, ref),
                  icon: const Icon(Icons.date_range),
                  label: Text(sameDay
                      ? fmt.format(filter.range.start)
                      : '${fmt.format(filter.range.start)} – ${fmt.format(filter.range.end)}'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: filter.dishId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Dish', isDense: true),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('All dishes')),
                ...(dishes.valueOrNull ?? const []).map(
                  (d) => DropdownMenuItem<int?>(value: d.id, child: Text(d.label)),
                ),
              ],
              onChanged: (v) => ref.read(reportFilterProvider.notifier).state =
                  v == null ? filter.copyWith(clearDish: true) : filter.copyWith(dishId: v),
            ),
            const SizedBox(height: 16),
            report.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Text(e.toString().replaceFirst('Exception: ', ''), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(reportProvider),
                    child: const Text('Retry'),
                  ),
                ]),
              ),
              data: (r) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    _Stat('Revenue', aed.format(r.totalRevenue)),
                    _Stat('Orders', '${r.totalOrders}'),
                    _Stat('Avg order', aed.format(r.avgOrderValue)),
                    _Stat('Items sold', '${r.totalItemsSold}'),
                  ]),
                  if (r.daily.length > 1) ...[
                    const SizedBox(height: 20),
                    Text('Daily sales', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Column(children: [
                        for (final d in r.daily)
                          ListTile(
                            dense: true,
                            title: Text(DateFormat('EEE, d MMM').format(d.date)),
                            subtitle: Text('${d.orders} orders'),
                            trailing: Text(aed.format(d.revenue)),
                          ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text('Items sold', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (r.items.isEmpty)
                    const Card(
                      margin: EdgeInsets.zero,
                      child: Padding(padding: EdgeInsets.all(16), child: Text('No sales in this period.')),
                    )
                  else
                    Card(
                      margin: EdgeInsets.zero,
                      child: Column(children: [
                        for (final i in r.items)
                          ListTile(
                            dense: true,
                            title: Text(i.dishName, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${i.qtySold} sold'),
                            trailing: Text(aed.format(i.revenue)),
                          ),
                      ]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: (MediaQuery.of(context).size.width - 32 - 12) / 2,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      );
}
