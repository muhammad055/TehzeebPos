/// Mirrors `GET /api/reports` and `GET /api/z-report` (backend/Program.cs).
/// Cancelled orders are already excluded server-side.
class ItemBreakdown {
  const ItemBreakdown({required this.dishId, required this.dishName, required this.qtySold, required this.revenue});

  final int dishId;
  final String dishName;
  final int qtySold;
  final double revenue;

  factory ItemBreakdown.fromJson(Map<String, dynamic> j) => ItemBreakdown(
        dishId: (j['dishId'] as num? ?? 0).toInt(),
        dishName: j['dishName'] as String? ?? '',
        qtySold: (j['qtySold'] as num? ?? 0).toInt(),
        revenue: (j['revenue'] as num? ?? 0).toDouble(),
      );
}

class DailySales {
  const DailySales({required this.date, required this.revenue, required this.orders});

  final DateTime date; // UAE calendar day
  final double revenue;
  final int orders;

  factory DailySales.fromJson(Map<String, dynamic> j) => DailySales(
        date: DateTime.parse(j['date'] as String),
        revenue: (j['revenue'] as num? ?? 0).toDouble(),
        orders: (j['orders'] as num? ?? 0).toInt(),
      );
}

class Report {
  const Report({
    required this.totalOrders,
    required this.totalRevenue,
    required this.avgOrderValue,
    required this.totalItemsSold,
    required this.items,
    required this.daily,
  });

  final int totalOrders;
  final double totalRevenue;
  final double avgOrderValue;
  final int totalItemsSold;
  final List<ItemBreakdown> items;
  final List<DailySales> daily;

  factory Report.fromJson(Map<String, dynamic> j) {
    final s = (j['summary'] as Map<String, dynamic>? ?? const {});
    return Report(
      totalOrders: (s['totalOrders'] as num? ?? 0).toInt(),
      totalRevenue: (s['totalRevenue'] as num? ?? 0).toDouble(),
      avgOrderValue: (s['avgOrderValue'] as num? ?? 0).toDouble(),
      totalItemsSold: (s['totalItemsSold'] as num? ?? 0).toInt(),
      items: [
        for (final i in (j['itemBreakdown'] as List? ?? const []))
          ItemBreakdown.fromJson(i as Map<String, dynamic>)
      ],
      daily: [
        for (final i in (j['dailySales'] as List? ?? const []))
          DailySales.fromJson(i as Map<String, dynamic>)
      ],
    );
  }
}

class ZReportItem {
  const ZReportItem({required this.name, required this.qty, required this.revenue});

  final String name;
  final int qty;
  final double revenue;

  factory ZReportItem.fromJson(Map<String, dynamic> j) => ZReportItem(
        name: j['name'] as String? ?? '',
        qty: (j['qty'] as num? ?? 0).toInt(),
        revenue: (j['revenue'] as num? ?? 0).toDouble(),
      );
}

/// Current open shift (since the last Z-Report was closed). Read-only on mobile:
/// closing a shift stays a counter/web action.
class ZReport {
  const ZReport({
    required this.nextReportNumber,
    required this.shiftStartIso,
    required this.totalOrders,
    required this.grossSales,
    required this.discounts,
    required this.taxTotal,
    required this.netSales,
    required this.topItems,
  });

  final int nextReportNumber;
  final String? shiftStartIso;
  final int totalOrders;
  final double grossSales;
  final double discounts;
  final double taxTotal;
  final double netSales;
  final List<ZReportItem> topItems;

  factory ZReport.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num? ?? 0).toDouble();
    return ZReport(
      nextReportNumber: (j['nextReportNumber'] as num? ?? 1).toInt(),
      shiftStartIso: j['shiftStart'] as String?,
      totalOrders: (j['totalOrders'] as num? ?? 0).toInt(),
      grossSales: d('grossSales'),
      discounts: d('discounts'),
      taxTotal: d('taxTotal'),
      netSales: d('netSales'),
      topItems: [
        for (final i in (j['topItems'] as List? ?? const []))
          ZReportItem.fromJson(i as Map<String, dynamic>)
      ],
    );
  }
}
