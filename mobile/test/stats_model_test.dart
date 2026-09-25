import 'package:flutter_test/flutter_test.dart';
import 'package:tehzeeb_mobile/features/dashboard/stats_model.dart';

void main() {
  test('Stats.fromJson parses /api/stats shape (ints and doubles)', () {
    final s = Stats.fromJson({
      'todaySales': 250, // server may send int or double
      'todayOrderCount': 5,
      'weekSales': 1000.5,
      'monthSales': 4000,
      'todayExpenses': 50,
      'weekExpenses': 100,
      'monthExpenses': 400,
      'todayProfit': 200,
      'weekProfit': 900.5,
      'monthProfit': 3600,
      'topItems': [
        {'name': 'Biryani', 'quantity': 12, 'revenue': 240}
      ],
      'last7Days': [
        {'date': 'Sep 24', 'total': 250}
      ],
    });
    expect(s.todaySales, 250.0);
    expect(s.todayAvgOrder, 50.0);
    expect(s.topItems.single.name, 'Biryani');
    expect(s.last7Days.single.total, 250.0);
  });

  test('empty payload does not throw and avg order is 0', () {
    final s = Stats.fromJson(const {});
    expect(s.todayOrderCount, 0);
    expect(s.todayAvgOrder, 0);
    expect(s.topItems, isEmpty);
  });
}
