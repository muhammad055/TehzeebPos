import 'package:flutter_test/flutter_test.dart';
import 'package:tehzeeb_mobile/features/expenses/purchase_model.dart';
import 'package:tehzeeb_mobile/features/menu/dish_model.dart';

void main() {
  test('DishInput normalises tiers like the web Menu Setup', () {
    // No 2nd price → no scheme, no 3rd price.
    final single = const DishInput(name: 'Naan', price: 2, taxRate: 5, thirdPrice: 9, scheme: PricingScheme.quarterHalfFull).toJson();
    expect(single['doublePrice'], isNull);
    expect(single['thirdPrice'], isNull);
    expect(single['pricingScheme'], isNull);

    // Single/Double never carries a 3rd price.
    final sd = const DishInput(name: 'Biryani', price: 10, taxRate: 5, doublePrice: 15, thirdPrice: 20).toJson();
    expect(sd['pricingScheme'], 'SingleDouble');
    expect(sd['thirdPrice'], isNull);

    final qhf = const DishInput(name: 'Karahi', price: 20, taxRate: 5, doublePrice: 35, thirdPrice: 60, scheme: PricingScheme.quarterHalfFull).toJson();
    expect(qhf['pricingScheme'], 'QuarterHalfFull');
    expect(qhf['thirdPrice'], 60);

    expect(const DishInput(name: 'x', price: 1, taxRate: 0, printName: '  ').toJson()['printName'], isNull);
  });

  test('Dish.fromJson handles nulls; null scheme parses as SingleDouble', () {
    final d = Dish.fromJson({'id': 3, 'name': 'آلو قیمہ', 'price': 10.0, 'taxRate': 5.0, 'isActive': true, 'printName': 'Alu Qeema', 'doublePrice': 15.0, 'thirdPrice': null, 'pricingScheme': null, 'imagePath': null});
    expect(d.label, 'Alu Qeema');
    expect(d.thirdPrice, isNull);
    expect(PricingScheme.parse(d.pricingScheme), PricingScheme.singleDouble);
  });

  test('Purchase.fromJson keeps the calendar date (no timezone shift)', () {
    final p = Purchase.fromJson({
      'id': 1,
      'date': '2026-09-24T00:00:00Z',
      'supplier': 'Al Ain Foods',
      'description': '',
      'totalAmount': 120.5,
      'category': 'Food & Beverage',
      'attachments': [
        {'id': 9, 'imagePath': '/uploads/purchases/2026/September/x.jpg'}
      ],
    });
    expect(p.date, DateTime(2026, 9, 24));
    expect(p.attachments.single.id, 9);
  });
}
