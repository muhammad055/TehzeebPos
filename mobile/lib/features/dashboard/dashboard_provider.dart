import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import 'stats_model.dart';

/// Fetches `/api/stats`. autoDispose so reopening the dashboard refetches;
/// `ref.invalidate(statsProvider)` powers pull-to-refresh.
final statsProvider = FutureProvider.autoDispose<Stats>((ref) async {
  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get('/stats');
    return Stats.fromJson(res.data as Map<String, dynamic>);
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) rethrow; // interceptor already signs out
    throw Exception('Could not load the dashboard. Check your connection.');
  }
});

/// Daily sales for the last [days] UAE days (`/api/stats/trend`), oldest first.
/// Dates are reformatted to "Sep 24" to match the 7-day series in `/api/stats`.
final trendProvider =
    FutureProvider.autoDispose.family<List<DayTotal>, int>((ref, days) async {
  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get('/stats/trend', queryParameters: {'days': days});
    return [
      for (final p in res.data as List)
        DayTotal(
          date: DateFormat('MMM dd').format(DateTime.parse((p as Map)['date'] as String)),
          total: (p['total'] as num).toDouble(),
        )
    ];
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) rethrow;
    throw Exception('Could not load the trend. Check your connection.');
  }
});

/// Daily sales for an explicit UAE date range (`from`/`to` are yyyy-MM-dd, inclusive).
final trendRangeProvider =
    FutureProvider.autoDispose.family<List<DayTotal>, ({String from, String to})>((ref, r) async {
  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get('/stats/trend', queryParameters: {'from': r.from, 'to': r.to});
    return [
      for (final p in res.data as List)
        DayTotal(
          date: DateFormat('MMM dd').format(DateTime.parse((p as Map)['date'] as String)),
          total: (p['total'] as num).toDouble(),
        )
    ];
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) rethrow;
    final data = e.response?.data;
    if (data is String && data.isNotEmpty && data.length < 120) throw Exception(data);
    throw Exception('Could not load the trend. Check your connection.');
  }
});
