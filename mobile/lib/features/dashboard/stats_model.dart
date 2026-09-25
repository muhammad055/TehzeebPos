/// Mirror of `GET /api/stats` (backend/Program.cs). All money figures are AED,
/// and the period boundaries (today/week/month, UTC+4) are computed by the
/// server — the app must never recompute them.
class TopItem {
  const TopItem({required this.name, required this.quantity, required this.revenue});

  final String name;
  final int quantity;
  final double revenue;

  factory TopItem.fromJson(Map<String, dynamic> j) => TopItem(
        name: j['name'] as String? ?? '',
        quantity: (j['quantity'] as num? ?? 0).toInt(),
        revenue: (j['revenue'] as num? ?? 0).toDouble(),
      );
}

class DayTotal {
  const DayTotal({required this.date, required this.total});

  final String date; // already formatted by the server, e.g. "Sep 24"
  final double total;

  factory DayTotal.fromJson(Map<String, dynamic> j) => DayTotal(
        date: j['date'] as String? ?? '',
        total: (j['total'] as num? ?? 0).toDouble(),
      );
}

class Stats {
  const Stats({
    required this.todaySales,
    required this.todayOrderCount,
    required this.weekSales,
    required this.monthSales,
    required this.todayExpenses,
    required this.weekExpenses,
    required this.monthExpenses,
    required this.todayProfit,
    required this.weekProfit,
    required this.monthProfit,
    required this.topItems,
    required this.last7Days,
  });

  final double todaySales;
  final int todayOrderCount;
  final double weekSales;
  final double monthSales;
  final double todayExpenses;
  final double weekExpenses;
  final double monthExpenses;
  final double todayProfit;
  final double weekProfit;
  final double monthProfit;
  final List<TopItem> topItems;
  final List<DayTotal> last7Days;

  /// Average order value today; 0 when there are no orders yet.
  double get todayAvgOrder => todayOrderCount == 0 ? 0 : todaySales / todayOrderCount;

  factory Stats.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num? ?? 0).toDouble();
    return Stats(
      todaySales: d('todaySales'),
      todayOrderCount: (j['todayOrderCount'] as num? ?? 0).toInt(),
      weekSales: d('weekSales'),
      monthSales: d('monthSales'),
      todayExpenses: d('todayExpenses'),
      weekExpenses: d('weekExpenses'),
      monthExpenses: d('monthExpenses'),
      todayProfit: d('todayProfit'),
      weekProfit: d('weekProfit'),
      monthProfit: d('monthProfit'),
      topItems: [
        for (final i in (j['topItems'] as List? ?? const []))
          TopItem.fromJson(i as Map<String, dynamic>)
      ],
      last7Days: [
        for (final i in (j['last7Days'] as List? ?? const []))
          DayTotal.fromJson(i as Map<String, dynamic>)
      ],
    );
  }
}
