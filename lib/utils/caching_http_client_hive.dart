import 'dart:async';
import 'dart:typed_data';

import 'package:fs_service_lib/utils/caching_http_client.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;

/// A persistent disk implementation of [CachingHttpClient] for GET requests using `hive_ce`.
///
/// Stores HTTP responses on disk in a Hive [Box], retaining cache state across application restarts.
///
/// **CAUTION for Cloud Run & Serverless environments:**
/// In Cloud Run or Cloud Functions, the local filesystem (e.g. `/tmp`) is an ephemeral in-memory filesystem (`tmpfs`).
/// Writing files to local disk in Cloud Run directly consumes container RAM! Unless an external volume
/// (such as Cloud Storage Volume Mount or Cloud Filestore NFS) is mounted, setting a large [maxSizeBytes]
/// may cause Out-Of-Memory (OOM) errors. Use appropriate limits or mount a persistent volume.
///
/// Default parameters:
/// - [maxSizeBytes]: 500 MB.
/// - [maxEntrySizeBytes]: 2 MB (covers 99% of Firestore REST documents).
/// - [ttl]: 30 minutes.
/// - [cacheCheckPeriod]: 10 minutes.
///
/// Cloud Run RAM presets:
/// - Light container (512 MB – 1 GB RAM): maxSizeBytes = 50 MB – 100 MB.
/// - Standard server (2 GB RAM): maxSizeBytes = 250 MB – 500 MB.
/// - Heavy server (4 GB+ RAM): maxSizeBytes = 500 MB – 1 GB.
class CachingHttpClientHive extends CachingHttpClient {
  CachingHttpClientHive({
    required Box<dynamic> box,
    super.inner,
    super.ttl = const Duration(minutes: 30),
    super.maxEntrySizeBytes = 2 * 1024 * 1024,
    super.maxSizeBytes = 50 * 1024 * 1024,
    super.cacheCheckPeriod = const Duration(minutes: 10),
    super.invalidationStrategy = CacheInvalidationStrategy.smart,
    super.onCacheHit,
  }) : _box = box {
    _recalculateCurrentSizeBytes();
  }

  final Box<dynamic> _box;

  @override
  int get cacheCount => _box.length;

  /// Recalculates total byte size from existing entries in Hive box.
  void _recalculateCurrentSizeBytes() {
    var total = 0;
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is Map) {
        final rawBytes = raw['bytes'];
        if (rawBytes is Uint8List) {
          total += rawBytes.length;
        } else if (rawBytes is List) {
          total += rawBytes.length;
        }
      }
    }
    currentSizeBytes = total;
  }

  /// Removes a key synchronously from Hive box and updates total byte size tracking.
  CachedHttpResponse? _removeKeySync(dynamic key) {
    final raw = _box.get(key);
    if (raw != null) {
      unawaited(_box.delete(key));
      final cached = CachedHttpResponse.fromMap(raw is Map ? raw : {});
      currentSizeBytes -= cached.bytes.length;
      if (currentSizeBytes < 0) {
        currentSizeBytes = 0;
      }
      return cached;
    }
    return null;
  }

  /// Removes a key asynchronously from Hive box and updates total byte size tracking.
  Future<CachedHttpResponse?> _removeKey(dynamic key) async {
    final raw = _box.get(key);
    if (raw != null) {
      await _box.delete(key);
      final cached = CachedHttpResponse.fromMap(raw is Map ? raw : {});
      currentSizeBytes -= cached.bytes.length;
      if (currentSizeBytes < 0) {
        currentSizeBytes = 0;
      }
      return cached;
    }
    return null;
  }

  @override
  Future<void> clearCache() async {
    await _box.clear();
    currentSizeBytes = 0;
  }

  @override
  void invalidateUrl(String urlOrPrefix) {
    final keysToRemove =
        _box.keys.where((key) => key.toString().contains(urlOrPrefix)).toList();
    keysToRemove.forEach(_removeKeySync);
    if (keysToRemove.isNotEmpty) {
      stats.invalidations++;
    }
  }

  /// Removes all expired entries from cache.
  Future<void> _cleanExpiredEntries() async {
    final expiredKeys = <dynamic>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is Map) {
        final entry = CachedHttpResponse.fromMap(raw);
        if (entry.isExpired(ttl)) {
          expiredKeys.add(key);
        }
      } else if (raw != null) {
        expiredKeys.add(key);
      }
    }
    for (final key in expiredKeys) {
      await _removeKey(key);
    }
  }

  /// Puts an entry into Hive cache, enforcing maxSizeBytes and maxEntrySizeBytes limits.
  Future<void> _putInCache(String key, CachedHttpResponse response) async {
    final now = DateTime.now();
    if (now.difference(lastCleanupTime) >= cacheCheckPeriod) {
      await _cleanExpiredEntries();
      lastCleanupTime = now;
    }

    await _removeKey(key);

    final entrySize = response.bytes.length;

    // Do not cache responses larger than maxEntrySizeBytes
    if (entrySize > maxEntrySizeBytes) {
      return;
    }

    // Evict oldest LRU entries if maxSizeBytes limit would be exceeded
    while (_box.isNotEmpty && currentSizeBytes + entrySize > maxSizeBytes) {
      final oldestKey = _box.keys.first;
      await _removeKey(oldestKey);
    }

    if (currentSizeBytes + entrySize <= maxSizeBytes) {
      await _box.put(key, response.toMap());
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
      final raw = _box.get(key);
      if (raw != null) {
        final cached = CachedHttpResponse.fromMap(raw is Map ? raw : {});
        if (!cached.isExpired(ttl)) {
          stats.hits++;
          // Refresh position in Hive box to preserve LRU order
          await _box.delete(key);
          await _box.put(key, raw);

          onCacheHit?.call(key, stats);

          return http.StreamedResponse(
            Stream.value(cached.bytes),
            cached.statusCode,
            headers: cached.headers,
            contentLength: cached.bytes.length,
            request: request,
          );
        } else {
          await _removeKey(key);
        }
      }
      stats.misses++;
    }

    final response = await client.send(request);

    // Cache successful GET responses
    if (request.method == 'GET' && response.statusCode == 200) {
      final bytes = await response.stream.toBytes();

      await _putInCache(
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
      await _applyInvalidation(request);
    }

    return response;
  }

  /// Applies cache invalidation based on the selected [invalidationStrategy].
  Future<void> _applyInvalidation(http.BaseRequest request) async {
    stats.invalidations++;
    final url = request.url;

    switch (invalidationStrategy) {
      case CacheInvalidationStrategy.all:
        await clearCache();
      case CacheInvalidationStrategy.smart:
        final urlString = url.toString();
        await _removeKey(urlString);

        final pathSegments = url.pathSegments;
        if (pathSegments.isNotEmpty) {
          final parentPath = pathSegments
              .sublist(0, pathSegments.length - 1)
              .join('/');
          if (parentPath.isNotEmpty) {
            final keysToRemove =
                _box.keys
                    .where((key) => key.toString().contains(parentPath))
                    .toList();
            for (final key in keysToRemove) {
              await _removeKey(key);
            }
          }
        }
      case CacheInvalidationStrategy.none:
        break;
    }
  }
}
