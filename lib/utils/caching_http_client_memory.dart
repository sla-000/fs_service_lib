import 'dart:async';

import 'package:fs_service_lib/utils/caching_http_client.dart';
import 'package:http/http.dart' as http;

/// An in-memory implementation of [CachingHttpClient] for GET requests.
///
/// Default parameters are optimized for lightweight containers / Cloud Run (512MB–1GB RAM):
/// - [maxSizeBytes]: 50 MB (~10% container RAM).
/// - [maxEntrySizeBytes]: 512 KB (covers 99% of Firestore REST documents).
/// - [ttl]: 15 minutes.
/// - [cacheCheckPeriod]: 5 minutes.
///
/// Recommended server presets:
/// - Light container (512MB–1GB RAM): maxSizeBytes = 50MB, maxEntrySizeBytes = 512KB, ttl = 15m.
/// - Standard server (2GB–4GB RAM): maxSizeBytes = 128MB–256MB, maxEntrySizeBytes = 1MB, ttl = 15–30m.
/// - Heavy server (8GB+ RAM): maxSizeBytes = 512MB–1GB, maxEntrySizeBytes = 2MB, ttl = 30–60m.
class CachingHttpClientMemory extends CachingHttpClient {
  CachingHttpClientMemory({
    super.inner,
    super.ttl = const Duration(minutes: 15),
    super.maxEntrySizeBytes = 512 * 1024,
    super.maxSizeBytes = 50 * 1024 * 1024,
    super.cacheCheckPeriod = const Duration(minutes: 5),
    super.invalidationStrategy = CacheInvalidationStrategy.smart,
    super.onCacheHit,
  });

  final Map<String, CachedHttpResponse> _cache = {};

  @override
  int get cacheCount => _cache.length;

  /// Removes a key from cache and updates total byte size tracking.
  CachedHttpResponse? _removeKey(String key) {
    final removed = _cache.remove(key);
    if (removed != null) {
      currentSizeBytes -= removed.bytes.length;
    }
    return removed;
  }

  @override
  Future<void> clearCache() async {
    _cache.clear();
    currentSizeBytes = 0;
  }

  @override
  void invalidateUrl(String urlOrPrefix) {
    final keysToRemove =
        _cache.keys.where((key) => key.contains(urlOrPrefix)).toList();
    keysToRemove.forEach(_removeKey);
    if (keysToRemove.isNotEmpty) {
      stats.invalidations++;
    }
  }

  /// Removes all expired entries from cache.
  void _cleanExpiredEntries() {
    final expiredKeys = <String>[];
    for (final entry in _cache.entries) {
      if (entry.value.isExpired(ttl)) {
        expiredKeys.add(entry.key);
      }
    }
    expiredKeys.forEach(_removeKey);
  }

  /// Puts an entry into cache, enforcing maxSizeBytes and maxEntrySizeBytes limits.
  void _putInCache(String key, CachedHttpResponse response) {
    final now = DateTime.now();
    if (now.difference(lastCleanupTime) >= cacheCheckPeriod) {
      _cleanExpiredEntries();
      lastCleanupTime = now;
    }

    _removeKey(key);

    final entrySize = response.bytes.length;

    // Do not cache responses larger than maxEntrySizeBytes
    if (entrySize > maxEntrySizeBytes) {
      return;
    }

    // Evict oldest LRU entries if maxSizeBytes limit would be exceeded
    while (_cache.isNotEmpty && currentSizeBytes + entrySize > maxSizeBytes) {
      final oldestKey = _cache.keys.first;
      _removeKey(oldestKey);
    }

    if (currentSizeBytes + entrySize <= maxSizeBytes) {
      _cache[key] = response;
      currentSizeBytes += entrySize;
      stats.stores++;
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final client = activeInnerClient;
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

    final response = await client.send(request);

    // Cache successful GET responses
    if (request.method == 'GET' && response.statusCode == 200) {
      final bytes = await response.stream.toBytes();

      _putInCache(
        key,
        CachedHttpResponse(
          bytes: bytes,
          statusCode: response.statusCode,
          headers: response.headers,
          createdAt: DateTime.now(),
        ),
      );

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
    if (isMutatingRequest(request) && response.statusCode < 400) {
      _applyInvalidation(request);
    }

    return response;
  }

  /// Applies cache invalidation based on the selected [invalidationStrategy].
  void _applyInvalidation(http.BaseRequest request) {
    stats.invalidations++;
    final url = request.url;

    switch (invalidationStrategy) {
      case CacheInvalidationStrategy.all:
        unawaited(clearCache());
      case CacheInvalidationStrategy.smart:
        final urlString = url.toString();
        _removeKey(urlString);

        final pathSegments = url.pathSegments;
        if (pathSegments.isNotEmpty) {
          final parentPath = pathSegments
              .sublist(0, pathSegments.length - 1)
              .join('/');
          if (parentPath.isNotEmpty) {
            final keysToRemove =
                _cache.keys.where((key) => key.contains(parentPath)).toList();
            keysToRemove.forEach(_removeKey);
          }
        }
      case CacheInvalidationStrategy.none:
        break;
    }
  }
}
