import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/holiday_data.dart';

/// 线上放假安排：优先拉本应用仓库里的数据，拉不到再试公共接口。
///
/// 任何一次成功都会缓存到本地，断网时继续用上一次的数据。
class HolidayRepository {
  HolidayRepository({
    List<String>? endpoints,
    this.timeout = const Duration(seconds: 8),
    HttpClient Function()? clientFactory,
  })  : endpoints = endpoints ?? defaultEndpoints,
        _clientFactory = clientFactory ?? HttpClient.new;

  static const String cacheKey = 'daymark.holidays.cache';

  /// 自建数据源：仓库里的 JSON，raw 优先，jsDelivr 兜底。
  static const List<String> defaultEndpoints = [
    'https://raw.githubusercontent.com/Gan332/Dating/main/assets/holidays/holidays.json',
    'https://cdn.jsdelivr.net/gh/Gan332/Dating@main/assets/holidays/holidays.json',
  ];

  /// 公共接口兜底，按年份查询。
  static const String timorEndpoint = 'https://timor.tech/api/holiday';

  final List<String> endpoints;
  final Duration timeout;
  final HttpClient Function() _clientFactory;

  /// 读取上次缓存的数据；没有或已损坏时返回 null。
  Future<HolidaySnapshot?> loadCached() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(cacheKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return HolidaySnapshot.fromJson(decoded);
      }
    } catch (error) {
      debugPrint('节假日缓存损坏，忽略：$error');
    }
    return null;
  }

  Future<void> cache(HolidaySnapshot snapshot) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(cacheKey, jsonEncode(snapshot.toJson()));
  }

  /// 依次尝试所有数据源，全部失败再试公共接口；仍失败则抛错。
  Future<HolidaySnapshot> fetch({required int year}) async {
    Object? lastError;
    for (final url in endpoints) {
      try {
        final body = await _get(url);
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          final snapshot = HolidaySnapshot.fromJson(decoded);
          if (snapshot != null) return snapshot;
        }
        lastError = FormatException('数据格式无法识别');
      } catch (error) {
        lastError = error;
        debugPrint('拉取 $url 失败：$error');
      }
    }

    try {
      final body = await _get('$timorEndpoint/year/$year');
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final data = HolidayData.fromTimor(year, decoded);
        if (data != null) {
          return HolidaySnapshot(
            years: {year: data},
            source: data.source,
            fetchedAt: DateTime.now(),
          );
        }
      }
      lastError = FormatException('公共接口数据格式无法识别');
    } catch (error) {
      lastError = error;
      debugPrint('拉取公共接口失败：$error');
    }

    throw HolidayUpdateException('暂时拿不到最新的放假安排', lastError);
  }

  Future<String> _get(String url) async {
    final client = _clientFactory();
    try {
      client.connectionTimeout = timeout;
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'daymark-app');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      return await response.transform(utf8.decoder).join().timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }
}

/// 在线更新失败。UI 只展示 [message]，原始错误留在日志里。
class HolidayUpdateException implements Exception {
  const HolidayUpdateException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
