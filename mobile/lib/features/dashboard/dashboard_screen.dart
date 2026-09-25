import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import 'dashboard_provider.dart';
import 'stats_model.dart';

final _aedShort = NumberFormat.compact();

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(statsProvider);
        await ref.read(statsProvider.future).catchError((_) => _empty);
      },
      child: stats.when(
        loading: () => const _Scrollable(child: Center(child: CircularProgressIndicator())),
        error: (e, _) => _Scrollable(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 40),
                  const SizedBox(height: 12),
                  Text(e.toString().replaceFirst('Exception: ', ''),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(statsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
        data: (s) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _SectionTitle('Today'),
            _TileGrid(tiles: [
              _Tile('Sales', aed.format(s.todaySales)),
              _Tile('Orders', '${s.todayOrderCount}'),
              _Tile('Avg order', aed.format(s.todayAvgOrder)),
              _Tile('Expenses', aed.format(s.todayExpenses)),
              _Tile('Profit', aed.format(s.todayProfit), signed: s.todayProfit),
            ]),
            const SizedBox(height: 20),
            _SectionTitle('This week'),
            _TileGrid(tiles: [
              _Tile('Sales', aed.format(s.weekSales)),
              _Tile('Expenses', aed.format(s.weekExpenses)),
              _Tile('Profit', aed.format(s.weekProfit), signed: s.weekProfit),
            ]),
            const SizedBox(height: 20),
            _SectionTitle('This month'),
            _TileGrid(tiles: [
              _Tile('Sales', aed.format(s.monthSales)),
              _Tile('Expenses', aed.format(s.monthExpenses)),
              _Tile('Profit', aed.format(s.monthProfit), signed: s.monthProfit),
            ]),
            const SizedBox(height: 20),
            _TrendSection(last7: s.last7Days),
            const SizedBox(height: 20),
            _SectionTitle('Top items'),
            _TopItems(items: s.topItems),
          ],
        ),
      ),
    );
  }
}

// Value returned to RefreshIndicator when the refetch fails — the error state
// is already rendered by `stats.when`.
final _empty = Stats.fromJson(const {});

/// Lets the loading/error states still be pulled to refresh.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(height: c.maxHeight, child: child),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _Tile {
  const _Tile(this.label, this.value, {this.signed});
  final String label;
  final String value;

  /// When set, the value is tinted green (>= 0) or red (< 0).
  final double? signed;
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});
  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final t in tiles)
          SizedBox(
            width: (MediaQuery.of(context).size.width - 32 - 12) / 2,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.label,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        t.value,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: t.signed == null
                                  ? null
                                  : (t.signed! >= 0 ? Colors.green.shade700 : scheme.error),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 7-day (from /api/stats) / 30-day (from /api/stats/trend) sales toggle.
class _TrendSection extends ConsumerStatefulWidget {
  const _TrendSection({required this.last7});
  final List<DayTotal> last7;

  @override
  ConsumerState<_TrendSection> createState() => _TrendSectionState();
}

class _TrendSectionState extends ConsumerState<_TrendSection> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final Widget chart = _days == 7
        ? _SalesChart(days: widget.last7)
        : ref.watch(trendProvider(_days)).when(
              loading: () => const SizedBox(
                  height: 200, child: Center(child: CircularProgressIndicator())),
              error: (e, _) => SizedBox(
                  height: 200,
                  child: Center(child: Text(e.toString().replaceFirst('Exception: ', '')))),
              data: (d) => _SalesChart(days: d, dense: true),
            );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _SectionTitle('Sales trend')),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 7, label: Text('7d')),
                ButtonSegment(value: 30, label: Text('30d')),
              ],
              selected: {_days},
              onSelectionChanged: (v) => setState(() => _days = v.first),
            ),
          ],
        ),
        chart,
      ],
    );
  }
}

class _SalesChart extends StatelessWidget {
  const _SalesChart({required this.days, this.dense = false});
  final List<DayTotal> days;

  /// 30-day mode: thinner bars, and only every 5th date label.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final maxTotal = days.map((d) => d.total).fold<double>(0, (a, b) => a > b ? a : b);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
        child: SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: maxTotal == 0 ? 1 : maxTotal * 1.15,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                    '${days[group.x].date}\n${aed.format(rod.toY)}',
                    TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (v, meta) => v == meta.max
                        ? const SizedBox.shrink()
                        : Text(_aedShort.format(v),
                            style: Theme.of(context).textTheme.labelSmall),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= days.length) return const SizedBox.shrink();
                      // "Sep 24" → "24" keeps 7 labels readable on a phone.
                      if (dense && i % 5 != 0) return const SizedBox.shrink();
                      final label = days[i].date.split(' ').last;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < days.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: days[i].total,
                      color: scheme.primary,
                      width: dense ? 5 : 18,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopItems extends StatelessWidget {
  const _TopItems({required this.items});
  final List<TopItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Card(
        margin: EdgeInsets.zero,
        child: Padding(padding: EdgeInsets.all(16), child: Text('No sales yet.')),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (i, it) in items.indexed)
            ListTile(
              leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
              title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${it.quantity} sold'),
              trailing: Text(aed.format(it.revenue)),
            ),
        ],
      ),
    );
  }
}
