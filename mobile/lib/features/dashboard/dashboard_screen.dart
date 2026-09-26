import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import 'dashboard_provider.dart';
import 'stats_model.dart';

final _aedShort = NumberFormat.compact();

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);

    // Opens the Expenses list already filtered to that period.
    void openExpenses(DateTime from, DateTime to) =>
        context.push('/expenses?from=${apiDate(from)}&to=${apiDate(to)}');
    final today = uaeToday();
    final weekStart = today.subtract(Duration(days: today.weekday % 7)); // weeks start on Sunday
    final monthStart = DateTime(today.year, today.month, 1);

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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            _HeroCard(stats: s),
            const SizedBox(height: 12),
            _TileGrid(tiles: [
              _Tile('Expenses today', aed.format(s.todayExpenses),
                  icon: Icons.shopping_bag_outlined, onTap: () => openExpenses(today, today)),
              _Tile('Profit today', aed.format(s.todayProfit),
                  icon: Icons.trending_up_rounded, signed: s.todayProfit),
            ]),
            const SizedBox(height: 24),
            const _SectionTitle('This week'),
            _TileGrid(tiles: [
              _Tile('Sales', aed.format(s.weekSales), icon: Icons.payments_outlined),
              _Tile('Expenses', aed.format(s.weekExpenses),
                  icon: Icons.shopping_bag_outlined, onTap: () => openExpenses(weekStart, today)),
              _Tile('Profit', aed.format(s.weekProfit),
                  icon: Icons.trending_up_rounded, signed: s.weekProfit, wide: true),
            ]),
            const SizedBox(height: 24),
            const _SectionTitle('This month'),
            _TileGrid(tiles: [
              _Tile('Sales', aed.format(s.monthSales), icon: Icons.payments_outlined),
              _Tile('Expenses', aed.format(s.monthExpenses),
                  icon: Icons.shopping_bag_outlined, onTap: () => openExpenses(monthStart, today)),
              _Tile('Profit', aed.format(s.monthProfit),
                  icon: Icons.trending_up_rounded, signed: s.monthProfit, wide: true),
            ]),
            const SizedBox(height: 24),
            _TrendSection(last7: s.last7Days),
            const SizedBox(height: 24),
            const _SectionTitle('Top items'),
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
        padding: const EdgeInsets.only(bottom: 12, left: 2),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

/// Gradient summary card for today: sales as the headline, orders and
/// average order underneath.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.stats});
  final Stats stats;

  @override
  Widget build(BuildContext context) {
    Widget mini(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.today_rounded, color: Colors.white.withValues(alpha: 0.85), size: 18),
              const SizedBox(width: 8),
              Text("Today's sales",
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(aed.format(stats.todaySales),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1)),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              mini('Orders', '${stats.todayOrderCount}'),
              const SizedBox(width: 10),
              mini('Avg order', aed.format(stats.todayAvgOrder)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tile {
  const _Tile(this.label, this.value, {required this.icon, this.signed, this.wide = false, this.onTap});
  final String label;
  final String value;
  final IconData icon;

  /// When set, the value is tinted green (>= 0) or red (< 0).
  final double? signed;

  /// Spans the full row instead of half of it.
  final bool wide;

  /// When set, the tile is tappable and shows a chevron.
  final VoidCallback? onTap;
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});
  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final half = (MediaQuery.of(context).size.width - 32 - 12) / 2;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final t in tiles)
          SizedBox(
            width: t.wide ? double.infinity : half,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
               onTap: t.onTap,
               child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: t.signed == null
                                ? AppColors.accentDim
                                : (t.signed! >= 0
                                    ? AppColors.success.withValues(alpha: 0.12)
                                    : AppColors.danger.withValues(alpha: 0.12)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            t.icon,
                            size: 17,
                            color: t.signed == null
                                ? AppColors.accentDark
                                : (t.signed! >= 0 ? AppColors.success : AppColors.danger),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(t.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ),
                        if (t.onTap != null)
                          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        t.value,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: t.signed == null
                                  ? null
                                  : (t.signed! >= 0 ? AppColors.success : AppColors.danger),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 7-day (from /api/stats) / 30-day / custom date range sales trend.
class _TrendSection extends ConsumerStatefulWidget {
  const _TrendSection({required this.last7});
  final List<DayTotal> last7;

  @override
  ConsumerState<_TrendSection> createState() => _TrendSectionState();
}

class _TrendSectionState extends ConsumerState<_TrendSection> {
  int _mode = 7; // 7, 30, or 0 = custom range
  DateTimeRange? _range;

  Future<void> _pickRange() async {
    final today = uaeToday();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: today,
      initialDateRange: _range ??
          DateTimeRange(start: today.subtract(const Duration(days: 13)), end: today),
    );
    if (picked == null) return;
    if (picked.duration.inDays >= 366) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Pick a range of one year or less.')));
      }
      return;
    }
    setState(() {
      _range = picked;
      _mode = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<DayTotal>> series;
    if (_mode == 7) {
      series = AsyncData(widget.last7);
    } else if (_mode == 30) {
      series = ref.watch(trendProvider(30));
    } else {
      series = ref.watch(trendRangeProvider((from: apiDate(_range!.start), to: apiDate(_range!.end))));
    }

    final chart = series.when(
      loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => SizedBox(
          height: 200,
          child: Center(child: Text(e.toString().replaceFirst('Exception: ', '')))),
      data: (d) => _SalesChart(days: d),
    );

    final total = series.valueOrNull?.fold<double>(0, (a, d) => a + d.total);
    final fmt = DateFormat('d MMM');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionTitle('Sales trend')),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 7, label: Text('7d')),
                ButtonSegment(value: 30, label: Text('30d')),
                ButtonSegment(value: 0, label: Icon(Icons.date_range, size: 18)),
              ],
              selected: {_mode},
              onSelectionChanged: (v) {
                final m = v.first;
                if (m == 0) {
                  _pickRange(); // the mode switches once a range is actually picked
                } else {
                  setState(() => _mode = m);
                }
              },
            ),
          ],
        ),
        if (_mode == 0 && _range != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: InkWell(
              onTap: _pickRange,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  const Icon(Icons.calendar_today, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text('${fmt.format(_range!.start)} – ${DateFormat('d MMM y').format(_range!.end)}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  const Icon(Icons.arrow_drop_down, color: AppColors.textMuted),
                  const Spacer(),
                  if (total != null)
                    Text(aed.format(total), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        chart,
      ],
    );
  }
}

class _SalesChart extends StatelessWidget {
  const _SalesChart({required this.days});
  final List<DayTotal> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    // Thinner bars and fewer date labels as the range grows, so it stays readable on a phone.
    final n = days.length;
    final barWidth = n <= 8 ? 20.0 : n <= 16 ? 12.0 : n <= 40 ? 6.0 : n <= 120 ? 3.0 : 1.5;
    final labelStep = n <= 8 ? 1 : (n / 6).ceil();
    final maxTotal = days.map((d) => d.total).fold<double>(0, (a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
        child: SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: maxTotal == 0 ? 1 : maxTotal * 1.15,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    const FlLine(color: AppColors.border, strokeWidth: 1, dashArray: [4, 4]),
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                    '${days[group.x].date}\n${aed.format(rod.toY)}',
                    const TextStyle(color: Colors.white, fontSize: 12),
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
                      if (i % labelStep != 0) return const SizedBox.shrink();
                      // "Sep 24" → "24" within a month; keep the month for long ranges.
                      final label = n > 31 ? days[i].date : days[i].date.split(' ').last;
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
                      gradient: AppColors.brandGradient,
                      width: barWidth,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
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
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Column(
            children: [
              Icon(Icons.restaurant_menu_rounded,
                  size: 32, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 8),
              Text('No sales yet',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, it) in items.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 64),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.accentDim,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text('${i + 1}',
                    style: const TextStyle(
                        color: AppColors.accentDark, fontWeight: FontWeight.w700)),
              ),
              title: Text(it.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${it.quantity} sold'),
              trailing: Text(aed.format(it.revenue),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}
