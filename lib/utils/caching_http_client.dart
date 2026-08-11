import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

export 'package:fs_service_lib/utils/caching_http_client_hive.dart';
export 'package:fs_service_lib/utils/caching_http_client_memory.dart';

/// Strategies for invalidating cached HTTP responses upon mutation requests.
enum CacheInvalidationStrategy {
  /// Smartly invalidates only the mutated document URL and related collection entries.
  smart,

  /// Clears the entire cache whenever a mutating request succeeds.
  all,

  /// Does not automatically invalidate cache on mutations (requires manual [CachingHttpClient.clearCache]).
  none,
}

/// Statistics for HTTP cache operations.
class CacheStats {
  /// Number of successful cache hits.
  int hits = 0;

  /// Number of cache misses (requests served from network).
  int misses = 0;

  /// Number of responses stored in cache.
  int stores = 0;

  /// Number of cache invalidation events.
  int invalidations = 0;

  /// Total number of evaluated requests ([hits] + [misses]).
  int get totalRequests => hits + misses;

  /// Ratio of cache hits to total requests (between 0.0 and 1.0).
  double get hitRatio => totalRequests == 0 ? 0.0 : hits / totalRequests;

  /// Percentage of cache hits formatted as a string (e.g., "85.0%").
  String get hitRatioPercentage => '${(hitRatio * 100).toStringAsFixed(1)}%';

  /// Resets all statistics counters to zero.
  void reset() {
    hits = 0;
    misses = 0;
    stores = 0;
    invalidations = 0;
  }

  @override
  String toString() =>
      'CacheStats(hits: $hits, misses: $misses, stores: $stores, '
      'invalidations: $invalidations, hitRatio: $hitRatioPercentage)';
}

/// Abstract HTTP client wrapper that provides response caching capabilities.
abstract class CachingHttpClient extends http.BaseClient {
  CachingHttpClient({
    this.inner,
    required this.ttl,
    required this.maxEntrySizeBytes,
    required this.maxSizeBytes,
    required this.cacheCheckPeriod,
    this.invalidationStrategy = CacheInvalidationStrategy.smart,
    this.onCacheHit,
  });

  /// Underlying HTTP client instance.
  http.Client? inner;

  /// Returns active inner HTTP client or throws [StateError] if missing.
  http.Client get activeInnerClient {
    final client = inner;
    if (client == null) {
      throw StateError(
        'CachingHttpClient must have an inner http.Client attached before sending requests.',
      );
    }
    return client;
  }

  /// Duration for which cached responses remain valid.
  Duration ttl;

  /// Maximum byte size allowed for a single cached response.
  /// Responses exceeding this limit will not be cached.
  int maxEntrySizeBytes;

  /// Maximum total byte size allowed for all cached responses combined.
  int maxSizeBytes;

  /// Interval between automatic cleanup sweeps of expired cache entries.
  Duration cacheCheckPeriod;

  /// Strategy used to invalidate cache when mutating HTTP requests occur.
  CacheInvalidationStrategy invalidationStrategy;

  /// Optional callback triggered when a request hits the cache, passing the request URL and current cache stats.
  final void Function(String url, CacheStats stats)? onCacheHit;

  /// Statistics for cache operations (hits, misses, ratios).
  final CacheStats stats = CacheStats();

  /// Total size in bytes of all currently cached responses.
  int currentSizeBytes = 0;

  /// Timestamp of the last expired cache entries cleanup sweep.
  DateTime lastCleanupTime = DateTime.now();

  /// Returns the current number of cached entries.
  int get cacheCount;

  /// Manually clears all cached responses.
  Future<void> clearCache();

  /// Removes a specific URL or all URLs matching a path prefix from the cache.
  void invalidateUrl(String urlOrPrefix);

  /// Determines if an HTTP request is mutating (writes/updates/deletes data).
  ///
  /// Note: Firestore REST API uses POST for `:runQuery`, `:runAggregationQuery`,
  /// and `:listCollectionIds`, which are read-only operations and must NOT be
  /// treated as mutating requests.
  bool isMutatingRequest(http.BaseRequest request) {
    final method = request.method;
    if (method == 'GET' || method == 'HEAD' || method == 'OPTIONS') {
      return false;
    }

    final path = request.url.path;
    if (method == 'POST' &&
        (path.endsWith(':runQuery') ||
            path.endsWith(':runAggregationQuery') ||
            path.endsWith(':listCollectionIds'))) {
      return false;
    }

    return true;
  }

  @override
  void close() {
    unawaited(clearCache());
    inner?.close();
    super.close();
  }
}

/// Represents an HTTP response stored in cache.
class CachedHttpResponse {
  CachedHttpResponse({
    required this.bytes,
    required this.statusCode,
    required this.headers,
    required this.createdAt,
  });

  /// Constructs a [CachedHttpResponse] from a serialized map (e.g. from Hive).
  factory CachedHttpResponse.fromMap(Map<dynamic, dynamic> map) {
    final rawBytes = map['bytes'];
    final Uint8List bytes;
    if (rawBytes is Uint8List) {
      bytes = rawBytes;
    } else if (rawBytes is List) {
      bytes = Uint8List.fromList(List<int>.from(rawBytes));
    } else {
      bytes = Uint8List(0);
    }

    final rawHeaders = map['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        headers[k.toString()] = v.toString();
      });
    }

    return CachedHttpResponse(
      bytes: bytes,
      statusCode: (map['statusCode'] as num?)?.toInt() ?? 200,
      headers: headers,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Binary payload of the response.
  final Uint8List bytes;

  /// HTTP status code of the response.
  final int statusCode;

  /// Response HTTP headers.
  final Map<String, String> headers;

  /// Timestamp when the entry was placed in cache.
  final DateTime createdAt;

  /// Checks if this cached entry has exceeded the allowed [ttl].
  bool isExpired(Duration ttl) => DateTime.now().difference(createdAt) > ttl;

  /// Serializes this response entry into a Map for disk storage.
  Map<String, dynamic> toMap() => {
    'bytes': bytes,
    'statusCode': statusCode,
    'headers': headers,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };
}
