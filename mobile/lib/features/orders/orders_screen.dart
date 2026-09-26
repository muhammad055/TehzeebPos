import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import 'order_model.dart';
import 'orders_provider.dart';

/// Orders for a date range: quick range chips, a summary, and orders grouped by UAE day.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(ordersRangeProvider);
    final orders = ref.watch(ordersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: Column(children: [
        _RangeBar(range: range),
        Expanded(
          child: RefreshIndicator(
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
                    const Icon(Icons.cloud_off, size: 40),
                    const SizedBox(height: 12),
                    Text(e.toString().replaceFirst('Exception: ', ''), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(ordersProvider),
                      child: const Text('Retry'),
                    ),
                  ]),
                ),
              ]),
              data: (list) => _OrdersList(list: list, multiDay: range.start != range.end),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Range bar ───────────────────────────────────────────────────────────────

class _RangeBar extends ConsumerWidget {
  const _RangeBar({required this.range});
  final DateTimeRange range;

  DateTimeRange _r(DateTime a, DateTime b) => DateTimeRange(start: a, end: b);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = uaeToday();
    final presets = <(String, DateTimeRange)>[
      ('Today', _r(today, today)),
      ('Yesterday', _r(today.subtract(const Duration(days: 1)), today.subtract(const Duration(days: 1)))),
      ('7 days', _r(today.subtract(const Duration(days: 6)), today)),
      ('This month', _r(DateTime(today.year, today.month, 1), today)),
    ];
    final matched = presets.any((p) => p.$2 == range);
    final fmt = DateFormat('d MMM');
    final label = range.start == range.end
        ? DateFormat('EEE, d MMM y').format(range.start)
        : '${fmt.format(range.start)} – ${DateFormat('d MMM y').format(range.end)}';

    Future<void> pick() async {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2024),
        lastDate: today,
        initialDateRange: range,
      );
      if (picked != null) ref.read(ordersRangeProvider.notifier).state = picked;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final p in presets)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(p.$1),
                  selected: range == p.$2,
                  onSelected: (_) => ref.read(ordersRangeProvider.notifier).state = p.$2,
                ),
              ),
            ChoiceChip(
              avatar: const Icon(Icons.date_range, size: 16),
              label: const Text('Custom'),
              selected: !matched,
              onSelected: (_) => pick(),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: pick,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const Icon(Icons.calendar_today, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const Icon(Icons.arrow_drop_down, color: AppColors.textMuted),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── List ────────────────────────────────────────────────────────────────────

class _OrdersList extends StatelessWidget {
  const _OrdersList({required this.list, required this.multiDay});
  final List<PosOrder> list;
  final bool multiDay;

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 80),
        Icon(Icons.receipt_long_outlined, size: 44, color: AppColors.textMuted),
        SizedBox(height: 10),
        Center(child: Text('No orders in this period', style: TextStyle(color: AppColors.textMuted))),
      ]);
    }

    final live = list.where((o) => !o.isCancelled).toList();
    final total = live.fold<double>(0, (a, o) => a + o.grandTotal);
    final cash = live.where((o) => o.paymentMethod.toLowerCase() == 'cash').fold<double>(0, (a, o) => a + o.grandTotal);
    final card = live.where((o) => o.paymentMethod.toLowerCase() == 'card').fold<double>(0, (a, o) => a + o.grandTotal);
    final cancelled = list.length - live.length;

    // Group by UAE calendar day, newest first (the API already returns newest first).
    final days = <DateTime, List<PosOrder>>{};
    for (final o in list) {
      final u = toUae(o.orderDate);
      days.putIfAbsent(DateTime(u.year, u.month, u.day), () => []).add(o);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _Summary(
          count: live.length,
          total: total,
          avg: live.isEmpty ? 0 : total / live.length,
          cash: cash,
          card: card,
          cancelled: cancelled,
        ),
        const SizedBox(height: 8),
        for (final e in days.entries) ...[
          if (multiDay) _DayHeader(day: e.key, orders: e.value),
          for (final o in e.value) ...[
            _OrderCard(order: o),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.count,
    required this.total,
    required this.avg,
    required this.cash,
    required this.card,
    required this.cancelled,
  });

  final int count;
  final double total;
  final double avg;
  final double cash;
  final double card;
  final int cancelled;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 12)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$count ${count == 1 ? 'order' : 'orders'}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(aed.format(total),
              style: const TextStyle(
                  color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        ),
        const SizedBox(height: 14),
        Row(children: [
          stat('Avg order', aed.format(avg)),
          stat('Cash', aed.format(cash)),
          stat('Card', aed.format(card)),
        ]),
        if (cancelled > 0) ...[
          const SizedBox(height: 10),
          Text('$cancelled cancelled (not counted)',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
        ],
      ]),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.orders});
  final DateTime day;
  final List<PosOrder> orders;

  @override
  Widget build(BuildContext context) {
    final live = orders.where((o) => !o.isCancelled);
    final total = live.fold<double>(0, (a, o) => a + o.grandTotal);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
      child: Row(children: [
        Expanded(
          child: Text(DateFormat('EEEE, d MMM').format(day),
              style: Theme.of(context).textTheme.titleMedium),
        ),
        Text('${live.length} · ${aed.format(total)}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
      ]),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final PosOrder order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final cancelled = o.isCancelled;
    final isCard = o.paymentMethod.toLowerCase() == 'card';
    final names = o.items.map((i) => i.dishName).toList();
    final shown = names.take(2).join(', ');
    final more = names.length > 2 ? ' +${names.length - 2} more' : '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/orders/${o.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: cancelled ? AppColors.surface2 : AppColors.accentDim,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('#${o.tokenNumber}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: cancelled ? AppColors.textMuted : AppColors.accentDark)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(
                    aed.format(o.grandTotal),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cancelled ? AppColors.textMuted : AppColors.text,
                      decoration: cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (cancelled)
                    const _Pill(text: 'Cancelled', color: AppColors.danger)
                  else
                    _Pill(
                      text: isCard ? 'Card' : 'Cash',
                      color: isCard ? AppColors.accentDark : AppColors.success,
                      icon: isCard ? Icons.credit_card_rounded : Icons.payments_rounded,
                    ),
                ]),
                const SizedBox(height: 3),
                Text('${formatUaeTime(o.orderDate)} · ${o.items.length} ${o.items.length == 1 ? 'item' : 'items'}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                if (names.isNotEmpty)
                  Text('$shown$more',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ]),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 3)],
          Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );
}
