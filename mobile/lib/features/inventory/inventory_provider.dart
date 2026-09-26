import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import 'inventory_model.dart';

String _friendly(DioException e, String what) {
  final data = e.response?.data;
  if (data is Map && data['message'] is String) return data['message'] as String;
  if (data is String && data.isNotEmpty && data.length < 200) return data;
  return 'Could not $what. Check your connection.';
}

/// Active items — the picker on bills and the rows on the usage/count entry screens.
final itemsProvider = FutureProvider.autoDispose<List<Item>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get('/items');
    return [for (final i in res.data as List) Item.fromJson(i as Map<String, dynamic>)];
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) rethrow;
    throw Exception(_friendly(e, 'load items'));
  }
});

final onHandProvider = FutureProvider.autoDispose<List<OnHandRow>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get('/stock/on-hand');
    return [
      for (final r in (res.data as Map)['items'] as List) OnHandRow.fromJson(r as Map<String, dynamic>)
    ];
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) rethrow;
    throw Exception(_friendly(e, 'load stock'));
  }
});

/// Defaults to the current UAE month so far.
final stockRangeProvider = StateProvider.autoDispose<DateTimeRange>((ref) {
  final today = uaeToday();
  return DateTimeRange(start: DateTime(today.year, today.month, 1), end: today);
});

final stockReportProvider = FutureProvider.autoDispose<StockReport>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final range = ref.watch(stockRangeProvider);
  try {
    final res = await dio.get('/stock/report',
        queryParameters: {'from': apiDate(range.start), 'to': apiDate(range.end)});
    return StockReport.fromJson(res.data as Map<String, dynamic>);
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) rethrow;
    throw Exception(_friendly(e, 'load the report'));
  }
});

/// Saved usage (kind == 'usage') or counts (kind == 'count') for a date, by item id.
final dayEntriesProvider =
    FutureProvider.autoDispose.family<Map<int, DayEntry>, ({String kind, String date})>((ref, key) async {
  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get(key.kind == 'usage' ? '/stock/usage' : '/stock/counts',
        queryParameters: {'date': key.date});
    return {
      for (final e in (res.data as Map)['entries'] as List)
        (e['itemId'] as num).toInt(): DayEntry(
          quantity: ((key.kind == 'usage' ? e['quantity'] : e['countedQty']) as num).toDouble(),
          note: e['note'] as String? ?? '',
        ),
    };
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) rethrow;
    throw Exception(_friendly(e, 'load entries'));
  }
});

// Actions return null on success or a user-facing error message.

Future<({Item? item, String? error})> createItem(WidgetRef ref, String name, String unit) async {
  try {
    final res = await ref.read(apiClientProvider).post('/items', data: {'name': name, 'unit': unit});
    ref.invalidate(itemsProvider);
    return (item: Item.fromJson(res.data as Map<String, dynamic>), error: null);
  } on DioException catch (e) {
    if (e.response?.statusCode == 403) return (item: null, error: 'Only a manager or owner can add items.');
    return (item: null, error: _friendly(e, 'add the item'));
  }
}

/// [entries]: itemId -> (quantity, note). A quantity of 0 clears that item's usage for the day.
Future<String?> saveUsage(WidgetRef ref, DateTime date, List<({int itemId, double quantity, String note})> entries) async {
  try {
    await ref.read(apiClientProvider).put('/stock/usage', data: {
      'date': apiDate(date),
      'entries': [
        for (final e in entries) {'itemId': e.itemId, 'quantity': e.quantity, 'note': e.note}
      ],
    });
    ref.invalidate(dayEntriesProvider);
    ref.invalidate(onHandProvider);
    return null;
  } on DioException catch (e) {
    return _friendly(e, 'save usage');
  }
}

Future<({List<CountResult> results, String? error})> saveCount(
    WidgetRef ref, DateTime date, List<({int itemId, double counted, String note})> entries) async {
  try {
    final res = await ref.read(apiClientProvider).post('/stock/counts', data: {
      'date': apiDate(date),
      'entries': [
        for (final e in entries) {'itemId': e.itemId, 'countedQty': e.counted, 'note': e.note}
      ],
    });
    ref.invalidate(dayEntriesProvider);
    ref.invalidate(onHandProvider);
    ref.invalidate(stockReportProvider);
    return (
      results: [
        for (final r in (res.data as Map)['results'] as List) CountResult.fromJson(r as Map<String, dynamic>)
      ],
      error: null,
    );
  } on DioException catch (e) {
    return (results: <CountResult>[], error: _friendly(e, 'save the count'));
  }
}
