import 'dart:io';

import 'package:fs_service_lib/utils/caching_http_client.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('CachingHttpClientHive tests', () {
    late Directory tempDir;
    late Box<dynamic> box;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('hive_http_test_');
      Hive.init(tempDir.path);
      box = await Hive.openBox('test_http_cache');
    });

    tearDown(() async {
      await box.close();
      await Hive.deleteBoxFromDisk('test_http_cache');
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'throws StateError when sending request without attached inner client',
      () async {
        final cachingClient = CachingHttpClientHive(box: box);
        expect(
          () => cachingClient.get(Uri.parse('https://example.com/api/doc')),
          throwsStateError,
        );
      },
    );

    test('caches GET requests and persists data', () async {
      var requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response('{"key": "value"}', 200);
      });

      final cachingClient = CachingHttpClientHive(box: box, inner: mockClient);

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
      expect(box.length, equals(1));
    });

    test('persists cache across client re-initialization', () async {
      final mockClient = MockClient(
        (request) async => http.Response('{"key": "persisted"}', 200),
      );

      final client1 = CachingHttpClientHive(box: box, inner: mockClient);
      await client1.get(Uri.parse('https://example.com/api/doc'));
      expect(client1.cacheCount, equals(1));

      // Re-initialize CachingHttpClientHive with existing populated box
      final client2 = CachingHttpClientHive(box: box, inner: mockClient);
      expect(client2.cacheCount, equals(1));
      expect(client2.currentSizeBytes, greaterThan(0));

      final response = await client2.get(
        Uri.parse('https://example.com/api/doc'),
      );
      expect(response.body, equals('{"key": "persisted"}'));
      expect(client2.stats.hits, equals(1));
    });

    test('tracks stats and triggers onCacheHit callback', () async {
      String? cacheHitUrl;
      CacheStats? cacheHitStats;
      final mockClient = MockClient(
        (request) async => http.Response('{"key": "value"}', 200),
      );

      final cachingClient = CachingHttpClientHive(
        box: box,
        inner: mockClient,
        onCacheHit: (url, stats) {
          cacheHitUrl = url;
          cacheHitStats = stats;
        },
      );

      final docUri = Uri.parse('https://example.com/api/doc');

      await cachingClient.get(docUri);
      expect(cachingClient.stats.misses, equals(1));
      expect(cachingClient.stats.hits, equals(0));

      await cachingClient.get(docUri);
      expect(cachingClient.stats.hits, equals(1));
      expect(cacheHitUrl, equals('https://example.com/api/doc'));
      expect(cacheHitStats?.hits, equals(1));
    });

    test(
      'smart invalidation removes mutated document and its parent collection',
      () async {
        final mockClient = MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response('{"key": "${request.url.path}"}', 200);
          }
          return http.Response('{"status": "ok"}', 200);
        });

        final cachingClient = CachingHttpClientHive(
          box: box,
          inner: mockClient,
        );

        final doc1Url = Uri.parse(
          'https://firestore.googleapis.com/v1/projects/p/databases/d/documents/users/doc1',
        );
        final doc2Url = Uri.parse(
          'https://firestore.googleapis.com/v1/projects/p/databases/d/documents/orders/doc2',
        );

        await cachingClient.get(doc1Url);
        await cachingClient.get(doc2Url);
        expect(cachingClient.cacheCount, equals(2));

        await cachingClient.patch(doc1Url, body: '{}');

        expect(cachingClient.cacheCount, equals(1));

        await cachingClient.get(doc2Url);
        expect(cachingClient.cacheCount, equals(1));
      },
    );

    test('clearCache manually flushes all cache entries', () async {
      final mockClient = MockClient(
        (request) async => http.Response('ok', 200),
      );

      final cachingClient = CachingHttpClientHive(box: box, inner: mockClient);

      await cachingClient.get(Uri.parse('https://example.com/1'));
      await cachingClient.get(Uri.parse('https://example.com/2'));
      expect(cachingClient.cacheCount, equals(2));

      await cachingClient.clearCache();
      expect(cachingClient.cacheCount, equals(0));
    });

    test('does not cache responses exceeding maxEntrySizeBytes', () async {
      final mockClient = MockClient(
        (request) async => http.Response('a' * 100, 200),
      );

      final cachingClient = CachingHttpClientHive(
        box: box,
        inner: mockClient,
        maxEntrySizeBytes: 50,
      );

      final res = await cachingClient.get(
        Uri.parse('https://example.com/large'),
      );
      expect(res.body.length, equals(100));
      expect(cachingClient.cacheCount, equals(0));
      expect(cachingClient.currentSizeBytes, equals(0));
    });

    test(
      'evicts oldest entries when total maxSizeBytes limit is reached',
      () async {
        final mockClient = MockClient(
          (request) async => http.Response('a' * 30, 200),
        );

        final cachingClient = CachingHttpClientHive(
          box: box,
          inner: mockClient,
          maxSizeBytes: 50,
        );

        await cachingClient.get(Uri.parse('https://example.com/1'));
        expect(cachingClient.cacheCount, equals(1));

        await cachingClient.get(Uri.parse('https://example.com/2'));
        expect(cachingClient.cacheCount, equals(1));
      },
    );
  });
}
