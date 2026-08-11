import 'package:fs_service_lib/utils/caching_http_client.dart';
import 'package:fs_service_lib/utils/firestore_api_provider.dart';
import 'package:test/test.dart';

void main() {
  group('FirestoreApiProviderImpl tests', () {
    test('instantiates with null cachingClient by default', () {
      final provider = FirestoreApiProviderImpl();
      expect(provider.cachingClient, isNull);
    });

    test('retains passed cachingClient instance', () {
      final cachingClient = CachingHttpClientMemory();
      final provider = FirestoreApiProviderImpl(cachingClient: cachingClient);

      expect(provider.cachingClient, same(cachingClient));
    });
  });
}
