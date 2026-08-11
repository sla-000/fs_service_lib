// coverage:ignore-file

import 'dart:async';

import 'package:fs_service_lib/utils/caching_http_client.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';

abstract class FirestoreApiProvider {
  FirestoreApi get api;

  /// Whether caching is enabled for HTTP requests.
  bool get enableCache;
  set enableCache(bool value);

  /// Statistics for cache operations (hits, misses, ratios).
  CacheStats? get cacheStats;

  /// Clears any cached HTTP responses.
  void clearCache();

  FutureOr<void> init();

  FutureOr<void> dispose();
}

class FirestoreApiProviderImpl implements FirestoreApiProvider {
  FirestoreApiProviderImpl({
    bool enableCache = true,
    this.cacheTtl = const Duration(minutes: 5),
    this.invalidationStrategy = CacheInvalidationStrategy.smart,
    this.onCacheHit,
  }) : _enableCache = enableCache;

  bool _enableCache;

  @override
  bool get enableCache => _cachingClient?.enableCache ?? _enableCache;

  @override
  set enableCache(bool value) {
    _enableCache = value;
    _cachingClient?.enableCache = value;
  }

  /// Time-to-live for cached HTTP responses.
  Duration cacheTtl;

  /// Invalidation strategy for mutating requests.
  CacheInvalidationStrategy invalidationStrategy;

  /// Optional callback triggered on cache hit events.
  void Function(String url, CacheStats stats)? onCacheHit;

  @override
  CacheStats? get cacheStats => _cachingClient?.stats;

  @override
  late FirestoreApi api;

  late AuthClient _client;
  CachingHttpClient? _cachingClient;

  @override
  void clearCache() {
    _cachingClient?.clearCache();
  }

  @override
  Future<void> init() async {
    _client = await clientViaApplicationDefaultCredentials(
      scopes: [
        FirestoreApi.cloudPlatformScope,
        FirestoreApi.datastoreScope,
      ],
    );

    _cachingClient = CachingHttpClient(
      _client,
      enableCache: _enableCache,
      ttl: cacheTtl,
      invalidationStrategy: invalidationStrategy,
      onCacheHit: onCacheHit,
    );

    api = FirestoreApi(_cachingClient!);
  }

  @override
  void dispose() {
    _cachingClient?.clearCache();
    _client.close();
  }
}
