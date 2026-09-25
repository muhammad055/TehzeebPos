import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import 'reports_model.dart';

/// Filter state for the Reports screen: UAE date range + optional dish.
class ReportFilter {
  const ReportFilter({required this.range, this.dishId});

  final DateTimeRange range;
  final int? dishId;

  ReportFilter copyWith({DateTimeRange? range, int? dishId, bool clearDish = false}) =>
      ReportFilter(
        range: range ?? this.range,
        dishId: clearDish ? null : (dishId ?? this.dishId),
      );
}

final reportFilterProvider = StateProvider.autoDispose<ReportFilter>((ref) {
  final today = uaeToday();
  return ReportFilter(range: DateTimeRange(start: today, end: today));
});

final reportProvider = FutureProvider.autoDispose<Report>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final f = ref.watch(reportFilterProvider);
  try {
    final res = await dio.get('/reports', queryParameters: {
      'from': apiDate(f.range.start),
      'to': apiDate(f.range.end),
      if (f.dishId != null) 'dishId': f.dishId,
    });
    return Report.fromJson(res.data as Map<String, dynamic>);
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) rethrow;
    throw Exception('Could not load the report. Check your connection.');
  }
});

final zReportProvider = FutureProvider.autoDispose<ZReport>((ref) async {
  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get('/z-report');
    return ZReport.fromJson(res.data as Map<String, dynamic>);
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) rethrow;
    throw Exception('Could not load the Z-Report. Check your connection.');
  }
});
