import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import 'purchase_model.dart';

String _friendly(DioException e, String what) {
  final data = e.response?.data;
  if (data is Map && data['message'] is String) return data['message'] as String;
  if (data is String && data.isNotEmpty && data.length < 200) return data;
  return 'Could not $what. Check your connection.';
}

class ExpenseFilter {
  const ExpenseFilter({required this.range, this.category});

  final DateTimeRange range;
  final String? category;
}

/// Defaults to the current UAE month so far.
final expenseFilterProvider = StateProvider.autoDispose<ExpenseFilter>((ref) {
  final today = uaeToday();
  return ExpenseFilter(range: DateTimeRange(start: DateTime(today.year, today.month, 1), end: today));
});

final expensesProvider = FutureProvider.autoDispose<List<Purchase>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final f = ref.watch(expenseFilterProvider);
  try {
    final res = await dio.get('/purchases', queryParameters: {
      'from': apiDate(f.range.start),
      'to': apiDate(f.range.end),
      if (f.category != null) 'category': f.category,
    });
    return [
      for (final p in res.data as List) Purchase.fromJson(p as Map<String, dynamic>)
    ];
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) rethrow;
    throw Exception(_friendly(e, 'load expenses'));
  }
});

final purchaseProvider = FutureProvider.autoDispose.family<Purchase, int>((ref, id) async {
  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get('/purchases/$id');
    return Purchase.fromJson(res.data as Map<String, dynamic>);
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) rethrow;
    throw Exception(_friendly(e, 'load the expense'));
  }
});

// Actions return null on success or a user-facing error message.

/// Creates (existingId == null) or updates an expense, then uploads [photos].
Future<String?> saveExpense(
  WidgetRef ref, {
  int? existingId,
  required DateTime date,
  required String supplier,
  required String description,
  required double amount,
  required String category,
  List<Uint8List> photos = const [],
}) async {
  final dio = ref.read(apiClientProvider);
  // The backend reads these as multipart form fields, not JSON.
  final form = FormData.fromMap({
    'date': apiDate(date),
    'supplier': supplier,
    'description': description,
    'totalAmount': amount.toString(),
    'category': category,
  });
  try {
    int id;
    if (existingId == null) {
      final res = await dio.post('/purchases', data: form);
      id = ((res.data as Map)['id'] as num).toInt();
    } else {
      await dio.put('/purchases/$existingId', data: form);
      id = existingId;
    }
    if (photos.isNotEmpty) {
      try {
        await dio.post('/purchases/$id/attachments', data: FormData.fromMap({
          'files': [
            for (var i = 0; i < photos.length; i++)
              MultipartFile.fromBytes(photos[i], filename: 'receipt-$i.jpg'),
          ],
        }));
      } on DioException catch (e) {
        ref.invalidate(expensesProvider);
        ref.invalidate(purchaseProvider(id));
        return 'Expense saved, but the photos failed: ${_friendly(e, 'upload the photos')}';
      }
    }
    ref.invalidate(expensesProvider);
    ref.invalidate(purchaseProvider(id));
    return null;
  } on DioException catch (e) {
    return _friendly(e, 'save the expense');
  }
}

Future<String?> deleteExpense(WidgetRef ref, int id) async {
  try {
    await ref.read(apiClientProvider).delete('/purchases/$id');
    ref.invalidate(expensesProvider);
    return null;
  } on DioException catch (e) {
    return _friendly(e, 'delete the expense');
  }
}

Future<String?> deleteAttachment(WidgetRef ref, int purchaseId, int attachmentId) async {
  try {
    await ref.read(apiClientProvider).delete('/purchases/$purchaseId/attachments/$attachmentId');
    ref.invalidate(purchaseProvider(purchaseId));
    ref.invalidate(expensesProvider);
    return null;
  } on DioException catch (e) {
    return _friendly(e, 'delete the photo');
  }
}
