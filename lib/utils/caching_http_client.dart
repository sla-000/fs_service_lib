import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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

/// An HTTP client wrapper that provides in-memory caching for GET requests.
///
/// Caching can be toggled via [enableCache], and entries expire after [ttl].
/// Mutating requests (PATCH, DELETE, POST document writes) automatically invalidate
/// relevant cache entries based on [invalidationStrategy].
class CachingHttpClient extends http.BaseClient {
  CachingHttpClient(
    this._inner, {
    this.enableCache = true,
    this.ttl = const Duration(minutes: 10),
    this.maxEntries = 10000,
    this.cacheCheckPeriod = const Duration(minutes: 30),
    this.invalidationStrategy = CacheInvalidationStrategy.smart,
    this.onCacheHit,
  });

  final http.Client _inner;

  /// Whether HTTP response caching is enabled.
  bool enableCache;

  /// Duration for which cached responses remain valid.
  Duration ttl;

  /// Maximum number of items allowed in the cache.
  int maxEntries;

  /// Interval between automatic cleanup sweeps of expired cache entries.
  Duration cacheCheckPeriod;

  /// Strategy used to invalidate cache when mutating HTTP requests occur.
  CacheInvalidationStrategy invalidationStrategy;

  /// Optional callback triggered when a request hits the cache, passing the request URL and current cache stats.
  final void Function(String url, CacheStats stats)? onCacheHit;

  /// Statistics for cache hits, misses, stores, and invalidations.
  final CacheStats stats = CacheStats();

  final Map<String, _CachedResponse> _cache = {};
  DateTime _lastCleanupTime = DateTime.now();

  /// Returns the current number of cached entries.
  int get cacheCount => _cache.length;

  /// Manually clears all cached responses.
  void clearCache() {
    _cache.clear();
  }

  /// Removes a specific URL or all URLs matching a path prefix from the cache.
  void invalidateUrl(String urlOrPrefix) {
    final beforeCount = _cache.length;
    _cache.removeWhere((key, _) => key.contains(urlOrPrefix));
    final removed = beforeCount - _cache.length;
    if (removed > 0) {
      stats.invalidations++;
    }
  }

  /// Removes all expired entries from cache.
  void _cleanExpiredEntries() {
    _cache.removeWhere((_, cached) => cached.isExpired(ttl));
  }

  /// Puts an entry into cache, enforcing maxEntries LRU limit and periodic cleanup.
  void _putInCache(String key, _CachedResponse response) {
    final now = DateTime.now();
    if (now.difference(_lastCleanupTime) >= cacheCheckPeriod) {
      _cleanExpiredEntries();
      _lastCleanupTime = now;
    }

    final isNewKey = !_cache.containsKey(key);
    if (isNewKey && _cache.length >= maxEntries && _cache.isNotEmpty) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }

    // Re-insert to keep key at the end of LinkedHashMap (MRU order)
    _cache.remove(key);
    _cache[key] = response;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!enableCache) {
      return _inner.send(request);
    }

    final key = request.url.toString();

    // Handle GET request caching
    if (request.method == 'GET') {
      final cached = _cache[key];
      if (cached != null && !cached.isExpired(ttl)) {
        stats.hits++;
        // Refresh position in LinkedHashMap to keep LRU order
        _cache.remove(key);
        _cache[key] = cached;

        onCacheHit?.call(key, stats);

        return http.StreamedResponse(
          Stream.value(cached.bytes),
          cached.statusCode,
          headers: cached.headers,
          contentLength: cached.bytes.length,
          request: request,
        );
      }
      stats.misses++;
    }

    final response = await _inner.send(request);

    // Cache successful GET responses
    if (request.method == 'GET' && response.statusCode == 200) {
      final bytes = await response.stream.toBytes();

      _putInCache(
        key,
        _CachedResponse(
          bytes: bytes,
          statusCode: response.statusCode,
          headers: response.headers,
          createdAt: DateTime.now(),
        ),
      );
      stats.stores++;

      return http.StreamedResponse(
        Stream.value(bytes),
        response.statusCode,
        headers: response.headers,
        contentLength: response.contentLength,
        reasonPhrase: response.reasonPhrase,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        request: response.request,
      );
    }

    // Check if the request is a mutating operation
    if (_isMutatingRequest(request) && response.statusCode < 400) {
      _applyInvalidation(request);
    }

    return response;
  }

  /// Determines if an HTTP request is mutating (writes/updates/deletes data).
  ///
  /// Note: Firestore REST API uses POST for `:runQuery`, `:runAggregationQuery`,
  /// and `:listCollectionIds`, which are read-only operations and must NOT be
  /// treated as mutating requests.
  bool _isMutatingRequest(http.BaseRequest request) {
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

  /// Applies cache invalidation based on the selected [invalidationStrategy].
  void _applyInvalidation(http.BaseRequest request) {
    stats.invalidations++;
    final url = request.url;

    switch (invalidationStrategy) {
      case CacheInvalidationStrategy.all:
        clearCache();
      case CacheInvalidationStrategy.smart:
        final urlString = url.toString();
        _cache.remove(urlString);

        final pathSegments = url.pathSegments;
        if (pathSegments.isNotEmpty) {
          final parentPath = pathSegments
              .sublist(0, pathSegments.length - 1)
              .join('/');
          if (parentPath.isNotEmpty) {
            _cache.removeWhere((key, _) => key.contains(parentPath));
          }
        }
      case CacheInvalidationStrategy.none:
        break;
    }
  }

  @override
  void close() {
    clearCache();
    _inner.close();
    super.close();
  }
}

class _CachedResponse {
  _CachedResponse({
    required this.bytes,
    required this.statusCode,
    required this.headers,
    required this.createdAt,
  });

  final Uint8List bytes;
  final int statusCode;
  final Map<String, String> headers;
  final DateTime createdAt;

  bool isExpired(Duration ttl) => DateTime.now().difference(createdAt) > ttl;
}
