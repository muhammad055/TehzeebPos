import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import 'expenses_provider.dart';
import 'purchase_model.dart';

/// [initialFrom]/[initialTo] (yyyy-MM-dd) preset the date range, e.g. when opened from the
/// dashboard's expense tiles.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key, this.initialFrom, this.initialTo});
  final String? initialFrom;
  final String? initialTo;

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  @override
  void initState() {
    super.initState();
    final from = DateTime.tryParse(widget.initialFrom ?? '');
    final to = DateTime.tryParse(widget.initialTo ?? '');
    if (from != null && to != null && !to.isBefore(from)) {
      // Not during build: providers can't be modified while the tree is building.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(expenseFilterProvider.notifier).state =
            ExpenseFilter(range: DateTimeRange(start: from, end: to));
      });
    }
  }

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final f = ref.read(expenseFilterProvider);
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: f.range,
      firstDate: DateTime(2024),
      lastDate: uaeToday(),
    );
    if (picked != null) {
      ref.read(expenseFilterProvider.notifier).state =
          ExpenseFilter(range: picked, category: f.category);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(expenseFilterProvider);
    final expenses = ref.watch(expensesProvider);
    final fmt = DateFormat('d MMM');
    final sameDay = filter.range.start == filter.range.end;

    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/expenses/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickRange(context, ref),
                  icon: const Icon(Icons.date_range),
                  label: Text(sameDay
                      ? fmt.format(filter.range.start)
                      : '${fmt.format(filter.range.start)} – ${fmt.format(filter.range.end)}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: filter.category,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  hint: const Text('All categories'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All categories')),
                    for (final c in expenseCategories)
                      DropdownMenuItem<String?>(value: c, child: Text(c)),
                  ],
                  onChanged: (c) => ref.read(expenseFilterProvider.notifier).state =
                      ExpenseFilter(range: filter.range, category: c),
                ),
              ),
            ]),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(expensesProvider);
                await ref.read(expensesProvider.future).then((_) {}, onError: (_) {});
              },
              child: expenses.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(children: [
                      Text(e.toString().replaceFirst('Exception: ', ''), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => ref.invalidate(expensesProvider),
                        child: const Text('Retry'),
                      ),
                    ]),
                  ),
                ]),
                data: (list) {
                  if (list.isEmpty) {
                    return ListView(children: const [
                      Padding(padding: EdgeInsets.all(48), child: Center(child: Text('No expenses in this period.'))),
                    ]);
                  }
                  final total = list.fold<double>(0, (a, p) => a + p.totalAmount);
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text('${list.length} expenses · ${aed.format(total)}'),
                      ),
                      for (final p in list)
                        ListTile(
                          onTap: () => context.push('/expenses/${p.id}'),
                          title: Text(p.supplier.isEmpty ? p.category : p.supplier,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text([
                            DateFormat('d MMM').format(p.date),
                            p.category,
                            if (p.items.isNotEmpty)
                              p.items.take(2).map((i) => i.itemName).join(', ') +
                                  (p.items.length > 2 ? ' +${p.items.length - 2}' : '')
                            else if (p.description.isNotEmpty)
                              p.description,
                          ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (p.attachments.isNotEmpty) ...[
                              const Icon(Icons.attach_file, size: 16),
                              Text('${p.attachments.length}  '),
                            ],
                            Text(aed.format(p.totalAmount)),
                          ]),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
