import 'package:flutter_test/flutter_test.dart';
import 'package:tehzeeb_mobile/features/expenses/purchase_model.dart';
import 'package:tehzeeb_mobile/features/inventory/inventory_model.dart';

void main() {
  test('Purchase.fromJson reads itemised lines and keeps old bills line-free', () {
    final withLines = Purchase.fromJson({
      'id': 5,
      'date': '2026-09-20T00:00:00',
      'supplier': 'Butcher',
      'totalAmount': 210,
      'items': [
        {'itemId': 3, 'itemName': 'Chicken', 'unit': 'kg', 'quantity': 10, 'unitPrice': 12.5, 'lineTotal': 125},
        {'itemId': 4, 'itemName': 'Rice', 'unit': 'kg', 'quantity': 20, 'unitPrice': 4.25, 'lineTotal': 85},
      ],
    });
    expect(withLines.items.length, 2);
    expect(withLines.items.first.itemName, 'Chicken');
    expect(withLines.items.first.quantity, 10.0);
    expect(withLines.items.last.lineTotal, 85.0);

    final old = Purchase.fromJson({'id': 1, 'date': '2026-09-01T00:00:00', 'totalAmount': 50});
    expect(old.items, isEmpty);
  });

  test('BillLineInput.toJson matches what the backend expects', () {
    expect(const BillLineInput(itemId: 3, quantity: 2.5, unitPrice: 12).toJson(),
        {'itemId': 3, 'quantity': 2.5, 'unitPrice': 12.0});
  });

  test('OnHandRow.fromJson handles a never-counted item', () {
    final r = OnHandRow.fromJson({
      'itemId': 1,
      'name': 'Chicken',
      'unit': 'kg',
      'lastCountDate': null,
      'lastCountQty': null,
      'bought': 10,
      'used': 7,
      'expected': 3,
      'avgUnitCost': 12.5,
      'value': 37.5,
    });
    expect(r.lastCountDate, isNull);
    expect(r.lastCountQty, isNull);
    expect(r.expected, 3.0);
    expect(r.value, 37.5);
  });

  test('StockReport.fromJson carries shortages as negatives', () {
    final rep = StockReport.fromJson({
      'totalSpend': 210,
      'totalShortageValue': -37.5,
      'items': [
        {
          'name': 'Chicken',
          'unit': 'kg',
          'boughtQty': 10,
          'spend': 125,
          'avgUnitCost': 12.5,
          'usedQty': 7,
          'counts': 1,
          'shortageQty': -3,
          'shortageValue': -37.5,
        }
      ],
    });
    expect(rep.totalShortageValue, -37.5);
    expect(rep.items.single.shortageQty, -3.0);
  });

  test('CountResult.fromJson reads expected, counted and variance', () {
    final c = CountResult.fromJson(
        {'name': 'Chicken', 'unit': 'kg', 'counted': 0, 'expected': 3, 'variance': -3});
    expect(c.variance, -3.0);
    expect(c.expected, 3.0);
  });

  test('qty() trims trailing zeros', () {
    expect(qty(7), '7');
    expect(qty(2.5), '2.5');
    expect(qty(0.125), '0.125');
    expect(qty(10.0), '10');
    expect(qty(-3), '-3');
  });
}
