import 'package:flutter_test/flutter_test.dart';
import 'package:tehzeeb_mobile/core/format.dart';
import 'package:tehzeeb_mobile/features/orders/order_model.dart';
import 'package:tehzeeb_mobile/features/reports/reports_model.dart';

void main() {
  test('parseUtc treats zone-less timestamps as UTC and UAE display adds 4h', () {
    expect(parseUtc('2026-09-24T20:30:00'), DateTime.utc(2026, 9, 24, 20, 30));
    expect(parseUtc('2026-09-24T20:30:00Z'), DateTime.utc(2026, 9, 24, 20, 30));
    // 20:30 UTC is 00:30 the next day in UAE.
    final uae = toUae(DateTime.utc(2026, 9, 24, 20, 30));
    expect(uae.day, 25);
    expect(uae.hour, 0);
  });

  test('PosOrder.fromJson parses a cancelled order', () {
    final o = PosOrder.fromJson({
      'id': 7,
      'orderDate': '2026-09-24T10:00:00Z',
      'tokenNumber': 3,
      'paymentMethod': 'Cash',
      'subTotal': 10,
      'discount': 0,
      'taxTotal': 0.5,
      'grandTotal': 10.5,
      'isCancelled': true,
      'cancelledAt': '2026-09-24T11:00:00Z',
      'cancelReason': 'wrong order',
      'items': [
        {'dishName': 'Biryani', 'quantity': 1, 'unitPrice': 10, 'lineTotal': 10}
      ],
    });
    expect(o.isCancelled, isTrue);
    expect(o.cancelReason, 'wrong order');
    expect(o.items.single.dishName, 'Biryani');
  });

  test('Report and ZReport parse server shapes', () {
    final r = Report.fromJson({
      'summary': {'totalOrders': 2, 'totalRevenue': 20, 'avgOrderValue': 10, 'totalItemsSold': 3},
      'itemBreakdown': [
        {'dishId': 1, 'dishName': 'Biryani', 'qtySold': 3, 'revenue': 20}
      ],
      'dailySales': [
        {'date': '2026-09-24', 'revenue': 20, 'orders': 2}
      ],
    });
    expect(r.totalRevenue, 20.0);
    expect(r.daily.single.orders, 2);

    final z = ZReport.fromJson({
      'nextReportNumber': 4,
      'shiftStart': null,
      'totalOrders': 0,
      'grossSales': 0,
      'discounts': 0,
      'taxTotal': 0,
      'netSales': 0,
      'topItems': [],
    });
    expect(z.nextReportNumber, 4);
    expect(z.shiftStartIso, isNull);
  });
}
