import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import 'inventory_model.dart';
import 'inventory_provider.dart';

/// Stock on hand, day-end usage / stock-count entry, and the purchases-vs-usage report.
/// Expected stock = last count + bought since - used since; a count below it is a shortage.
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inventory'),
          bottom: const TabBar(
            tabs: [Tab(text: 'On hand'), Tab(text: 'Entry'), Tab(text: 'Report')],
          ),
        ),
        body: const TabBarView(children: [_OnHandTab(), _EntryTab(), _ReportTab()]),
      ),
    );
  }
}

// ── shared bits ─────────────────────────────────────────────────────────────

Widget _errorView(String message, VoidCallback retry) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 40),
          const SizedBox(height: 12),
          Text(message.replaceFirst('Exception: ', ''), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: retry, child: const Text('Retry')),
        ]),
      ),
    );

Widget _emptyView(IconData icon, String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
        ]),
      ),
    );

// ── On hand ─────────────────────────────────────────────────────────────────

class _OnHandTab extends ConsumerWidget {
  const _OnHandTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(onHandProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(onHandProvider);
        await ref.read(onHandProvider.future).catchError((_) => <OnHandRow>[]);
      },
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _errorView(e.toString(), () => ref.invalidate(onHandProvider)),
        data: (rows) {
          if (rows.isEmpty) {
            return ListView(children: [
              SizedBox(
                height: 360,
                child: _emptyView(Icons.inventory_2_outlined,
                    'No items yet. Add items when you enter a bill, and enter an opening stock count.'),
              ),
            ]);
          }
          final total = rows.fold<double>(0, (s, r) => s + r.value);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    const Icon(Icons.inventory_2_rounded, color: AppColors.accent),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Stock value', style: TextStyle(color: AppColors.textMuted))),
                    Text(aed.format(total),
                        style: Theme.of(context).textTheme.titleLarge),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              for (final r in rows) ...[
                _OnHandCard(row: r),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _OnHandCard extends StatelessWidget {
  const _OnHandCard({required this.row});
  final OnHandRow row;

  @override
  Widget build(BuildContext context) {
    final negative = row.expected < 0;
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(row.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Text('${qty(row.expected)} ${row.unit}',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: negative ? AppColors.danger : AppColors.text)),
          ]),
          const SizedBox(height: 6),
          if (negative)
            const Text('Used more than was bought', style: TextStyle(color: AppColors.danger, fontSize: 12)),
          Text(
            row.lastCountDate == null
                ? 'Never counted'
                : 'Counted ${qty(row.lastCountQty ?? 0)} ${row.unit} on ${row.lastCountDate}',
            style: small,
          ),
          Text('Bought ${qty(row.bought)} · Used ${qty(row.used)} since  ·  '
              '${aed.format(row.value)}', style: small),
        ]),
      ),
    );
  }
}

// ── Entry (usage / count) ───────────────────────────────────────────────────

class _EntryTab extends ConsumerStatefulWidget {
  const _EntryTab();

  @override
  ConsumerState<_EntryTab> createState() => _EntryTabState();
}

class _EntryTabState extends ConsumerState<_EntryTab> {
  String _kind = 'usage'; // 'usage' | 'count'
  DateTime _date = uaeToday();

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: uaeToday(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(itemsProvider);
    final key = (kind: _kind, date: apiDate(_date));
    final entries = ref.watch(dayEntriesProvider(key));

    Widget body;
    if (items.isLoading || entries.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (items.hasError || entries.hasError) {
      body = _errorView((items.error ?? entries.error).toString(), () {
        ref.invalidate(itemsProvider);
        ref.invalidate(dayEntriesProvider(key));
      });
    } else if (items.value!.isEmpty) {
      body = _emptyView(Icons.inventory_2_outlined, 'No items yet. Add items when you enter a bill.');
    } else {
      // Keyed so switching kind/date rebuilds the fields from what is saved for that day.
      body = _EntryForm(
        key: ValueKey('${key.kind}${key.date}'),
        kind: _kind,
        date: _date,
        items: items.value!,
        saved: entries.value!,
      );
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'usage', label: Text('Daily usage'), icon: Icon(Icons.restaurant)),
                ButtonSegment(value: 'count', label: Text('Stock count'), icon: Icon(Icons.fact_check_outlined)),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(DateFormat('EEE, d MMM y').format(_date)),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _kind == 'usage'
                  ? 'Quantity used today per item. Leave blank if not used.'
                  : 'What is physically on the shelf now. Leave blank if not counted.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
        ]),
      ),
      Expanded(child: body),
    ]);
  }
}

class _EntryForm extends ConsumerStatefulWidget {
  const _EntryForm({
    super.key,
    required this.kind,
    required this.date,
    required this.items,
    required this.saved,
  });

  final String kind;
  final DateTime date;
  final List<Item> items;
  final Map<int, DayEntry> saved;

  @override
  ConsumerState<_EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends ConsumerState<_EntryForm> {
  late final Map<int, TextEditingController> _qty;
  late final Map<int, TextEditingController> _note;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _qty = {
      for (final i in widget.items)
        i.id: TextEditingController(text: widget.saved[i.id] == null ? '' : qty(widget.saved[i.id]!.quantity)),
    };
    _note = {
      for (final i in widget.items) i.id: TextEditingController(text: widget.saved[i.id]?.note ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in [..._qty.values, ..._note.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final isUsage = widget.kind == 'usage';
    for (final i in widget.items) {
      final t = _qty[i.id]!.text.trim();
      if (t.isNotEmpty && (double.tryParse(t) == null || double.parse(t) < 0)) {
        _snack('Check the quantity for ${i.name}.');
        return;
      }
    }
    setState(() => _saving = true);
    String? err;
    List<CountResult> results = const [];

    if (isUsage) {
      // Blank on an item that had a value clears it (0); otherwise blank means "skip".
      final entries = <({int itemId, double quantity, String note})>[];
      for (final i in widget.items) {
        final t = _qty[i.id]!.text.trim();
        if (t.isEmpty && !widget.saved.containsKey(i.id)) continue;
        entries.add((itemId: i.id, quantity: t.isEmpty ? 0 : double.parse(t), note: _note[i.id]!.text.trim()));
      }
      err = await saveUsage(ref, widget.date, entries);
    } else {
      final entries = <({int itemId, double counted, String note})>[];
      for (final i in widget.items) {
        final t = _qty[i.id]!.text.trim();
        if (t.isEmpty) continue;
        entries.add((itemId: i.id, counted: double.parse(t), note: _note[i.id]!.text.trim()));
      }
      if (entries.isEmpty) {
        setState(() => _saving = false);
        _snack('Enter at least one count.');
        return;
      }
      final r = await saveCount(ref, widget.date, entries);
      err = r.error;
      results = r.results;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      _snack(err);
      return;
    }
    _snack(isUsage ? 'Usage saved.' : 'Count saved.');
    if (!isUsage) await _showCountResult(results);
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _showCountResult(List<CountResult> results) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Count result'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [
            for (final r in results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Expected ${qty(r.expected)} ${r.unit} · counted ${qty(r.counted)} ${r.unit}'),
                trailing: Text(
                  r.variance == 0 ? 'OK' : '${r.variance > 0 ? '+' : ''}${qty(r.variance)} ${r.unit}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: r.variance < 0
                        ? AppColors.danger
                        : (r.variance > 0 ? AppColors.warning : AppColors.success),
                  ),
                ),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUsage = widget.kind == 'usage';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final i in widget.items) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Text(i.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _qty[i.id],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.end,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '0',
                        suffixText: i.unit,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: _note[i.id],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: isUsage ? 'Used in (e.g. biryani, korma)' : 'Note (optional)',
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(isUsage ? 'Save usage' : 'Save count'),
        ),
      ],
    );
  }
}

// ── Report ──────────────────────────────────────────────────────────────────

class _ReportTab extends ConsumerWidget {
  const _ReportTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(stockRangeProvider);
    final async = ref.watch(stockReportProvider);
    final fmt = DateFormat('d MMM');

    Future<void> pick() async {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2024),
        lastDate: uaeToday(),
        initialDateRange: range,
      );
      if (picked != null) ref.read(stockRangeProvider.notifier).state = picked;
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: pick,
            icon: const Icon(Icons.date_range, size: 18),
            label: Text('${fmt.format(range.start)} – ${fmt.format(range.end)}'),
          ),
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(stockReportProvider);
            await ref.read(stockReportProvider.future).catchError((_) => const StockReport(
                totalSpend: 0, totalShortageValue: 0, items: []));
          },
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _errorView(e.toString(), () => ref.invalidate(stockReportProvider)),
            data: (r) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Row(children: [
                  Expanded(child: _Stat(label: 'Spent on items', value: aed.format(r.totalSpend))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Stat(
                      label: 'Lost to shortages',
                      value: aed.format(-r.totalShortageValue),
                      color: r.totalShortageValue < 0 ? AppColors.danger : null,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                if (r.items.isEmpty)
                  SizedBox(height: 260, child: _emptyView(Icons.bar_chart_rounded, 'Nothing recorded in this period.')),
                for (final it in r.items) ...[
                  _ReportCard(row: it),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color)),
            ),
          ]),
        ),
      );
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.row});
  final StockReportRow row;

  @override
  Widget build(BuildContext context) {
    final short = row.shortageQty < 0;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(row.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Bought ${qty(row.boughtQty)} ${row.unit} for ${aed.format(row.spend)}'
              '  (avg ${aed.format(row.avgUnitCost)}/${row.unit})', style: muted),
          Text('Used ${qty(row.usedQty)} ${row.unit}', style: muted),
          if (short) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Short ${qty(-row.shortageQty)} ${row.unit} · lost ${aed.format(-row.shortageValue)}',
                style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
              ),
            ),
          ] else if (row.counts > 0)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('No shortages found', style: TextStyle(color: AppColors.success, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}
