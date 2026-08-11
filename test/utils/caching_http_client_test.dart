import 'package:fs_service_lib/utils/caching_http_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('CachingHttpClient tests', () {
    test('caches GET requests when enableCache is true', () async {
      var requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response('{"key": "value"}', 200);
      });

      final cachingClient = CachingHttpClient(mockClient);

      final response1 = await cachingClient.get(
        Uri.parse('https://example.com/api/doc'),
      );
      final response2 = await cachingClient.get(
        Uri.parse('https://example.com/api/doc'),
      );

      expect(response1.body, equals('{"key": "value"}'));
      expect(response2.body, equals('{"key": "value"}'));
      expect(requestCount, equals(1));
      expect(cachingClient.cacheCount, equals(1));
    });

    test('tracks stats and triggers onCacheHit callback on cache hit', () async {
      String? cacheHitUrl;
      CacheStats? cacheHitStats;
      final mockClient = MockClient(
        (request) async => http.Response('{"key": "value"}', 200),
      );

      final cachingClient = CachingHttpClient(
        mockClient,
        onCacheHit: (url, stats) {
          cacheHitUrl = url;
          cacheHitStats = stats;
        },
      );

      final docUri = Uri.parse('https://example.com/api/doc');

      // 1. First GET request -> Miss -> Store
      await cachingClient.get(docUri);
      expect(cachingClient.stats.misses, equals(1));
      expect(cachingClient.stats.hits, equals(0));
      expect(cachingClient.stats.stores, equals(1));
      expect(cachingClient.stats.totalRequests, equals(1));
      expect(cachingClient.stats.hitRatio, equals(0.0));
      expect(cacheHitUrl, isNull);

      // 2. Second GET request -> Hit
      await cachingClient.get(docUri);
      expect(cachingClient.stats.hits, equals(1));
      expect(cachingClient.stats.totalRequests, equals(2));
      expect(cachingClient.stats.hitRatio, equals(0.5));
      expect(cachingClient.stats.hitRatioPercentage, equals('50.0%'));

      // Check onCacheHit callback received accurate info
      expect(cacheHitUrl, equals('https://example.com/api/doc'));
      expect(cacheHitStats?.hits, equals(1));

      // Reset stats
      cachingClient.stats.reset();
      expect(cachingClient.stats.totalRequests, equals(0));
    });

    test('bypasses cache when enableCache is false', () async {
      var requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response('{"key": "value"}', 200);
      });

      final cachingClient = CachingHttpClient(mockClient, enableCache: false);

      await cachingClient.get(Uri.parse('https://example.com/api/doc'));
      await cachingClient.get(Uri.parse('https://example.com/api/doc'));

      expect(requestCount, equals(2));
      expect(cachingClient.cacheCount, equals(0));
    });

    test(
      'smart invalidation only removes mutated document and its parent collection',
      () async {
        final mockClient = MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response('{"key": "${request.url.path}"}', 200);
          }
          return http.Response('{"status": "ok"}', 200);
        });

        final cachingClient = CachingHttpClient(mockClient);

        final doc1Url = Uri.parse(
          'https://firestore.googleapis.com/v1/projects/p/databases/d/documents/users/doc1',
        );
        final doc2Url = Uri.parse(
          'https://firestore.googleapis.com/v1/projects/p/databases/d/documents/orders/doc2',
        );

        await cachingClient.get(doc1Url);
        await cachingClient.get(doc2Url);
        expect(cachingClient.cacheCount, equals(2));

        // Mutate doc1
        await cachingClient.patch(doc1Url, body: '{}');

        // doc1 should be invalidated, but doc2 (in orders collection) should remain cached!
        expect(cachingClient.cacheCount, equals(1));

        // Fetching doc2 hits cache
        await cachingClient.get(doc2Url);
        expect(cachingClient.cacheCount, equals(1));
      },
    );

    test(
      'runQuery, runAggregationQuery and listCollectionIds POST requests are NOT treated as mutating',
      () async {
        var getCount = 0;
        final mockClient = MockClient((request) async {
          if (request.method == 'GET') {
            getCount++;
            return http.Response('{"doc": 1}', 200);
          }
          return http.Response('[{"document": {}}]', 200);
        });

        final cachingClient = CachingHttpClient(mockClient);
        final docUrl = Uri.parse(
          'https://firestore.googleapis.com/v1/projects/p/databases/d/documents/users/doc1',
        );
        final queryUrl = Uri.parse(
          'https://firestore.googleapis.com/v1/projects/p/databases/d/documents:runQuery',
        );
        final listColsUrl = Uri.parse(
          'https://firestore.googleapis.com/v1/projects/p/databases/d/documents/users/doc1:listCollectionIds',
        );

        await cachingClient.get(docUrl);
        expect(cachingClient.cacheCount, equals(1));

        // Execute a query via POST
        await cachingClient.post(queryUrl, body: '{}');

        // Execute listCollectionIds via POST
        await cachingClient.post(listColsUrl, body: '{}');

        // Cache should NOT be invalidated because runQuery and listCollectionIds are read-only
        expect(cachingClient.cacheCount, equals(1));
        expect(getCount, equals(1));
      },
    );

    test('re-fetches after TTL expires', () async {
      var requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response('{"count": $requestCount}', 200);
      });

      final cachingClient = CachingHttpClient(
        mockClient,
        ttl: const Duration(milliseconds: 50),
      );

      final res1 = await cachingClient.get(
        Uri.parse('https://example.com/api/doc'),
      );
      expect(res1.body, equals('{"count": 1}'));

      await Future<void>.delayed(const Duration(milliseconds: 100));

      final res2 = await cachingClient.get(
        Uri.parse('https://example.com/api/doc'),
      );
      expect(res2.body, equals('{"count": 2}'));
      expect(requestCount, equals(2));
    });

    test('clearCache manually flushes all cache entries', () async {
      final mockClient = MockClient(
        (request) async => http.Response('ok', 200),
      );

      final cachingClient = CachingHttpClient(mockClient);

      await cachingClient.get(Uri.parse('https://example.com/1'));
      await cachingClient.get(Uri.parse('https://example.com/2'));
      expect(cachingClient.cacheCount, equals(2));

      cachingClient.clearCache();
      expect(cachingClient.cacheCount, equals(0));
    });

    test('evicts LRU entries when maxEntries capacity limit is reached', () async {
      final mockClient = MockClient(
        (request) async => http.Response('data:${request.url.path}', 200),
      );

      final cachingClient = CachingHttpClient(
        mockClient,
        maxEntries: 2,
      );

      final url1 = Uri.parse('https://example.com/1');
      final url2 = Uri.parse('https://example.com/2');
      final url3 = Uri.parse('https://example.com/3');

      await cachingClient.get(url1);
      await cachingClient.get(url2);
      expect(cachingClient.cacheCount, equals(2));

      // Refresh url1 to make url2 the least recently used
      await cachingClient.get(url1);

      // Store url3 -> should evict url2
      await cachingClient.get(url3);
      expect(cachingClient.cacheCount, equals(2));

      // url1 should still be in cache (Hit)
      await cachingClient.get(url1);
      expect(cachingClient.stats.hits, equals(2));
    });

    test('cleans up expired entries on cacheCheckPeriod interval', () async {
      final mockClient = MockClient(
        (request) async => http.Response('ok', 200),
      );

      final cachingClient = CachingHttpClient(
        mockClient,
        ttl: const Duration(milliseconds: 50),
        cacheCheckPeriod: const Duration(milliseconds: 50),
      );

      await cachingClient.get(Uri.parse('https://example.com/expired1'));
      await cachingClient.get(Uri.parse('https://example.com/expired2'));
      expect(cachingClient.cacheCount, equals(2));

      // Wait for entries to expire and cacheCheckPeriod to elapse
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Storing a new item triggers cleanup sweep of expired items
      await cachingClient.get(Uri.parse('https://example.com/new'));
      expect(cachingClient.cacheCount, equals(1));
    });
  });
}
