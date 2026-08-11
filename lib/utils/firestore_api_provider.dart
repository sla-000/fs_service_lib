// coverage:ignore-file

import 'dart:async';

import 'package:fs_service_lib/utils/caching_http_client.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';

abstract class FirestoreApiProvider {
  FirestoreApi get api;

  FutureOr<void> init();

  FutureOr<void> dispose();
}

class FirestoreApiProviderImpl implements FirestoreApiProvider {
  FirestoreApiProviderImpl({this.cachingClient});

  /// Optional caching HTTP client wrapper. If null, requests will not be cached.
  final CachingHttpClient? cachingClient;

  @override
  late FirestoreApi api;

  late AuthClient _client;

  @override
  Future<void> init() async {
    _client = await clientViaApplicationDefaultCredentials(
      scopes: [FirestoreApi.cloudPlatformScope, FirestoreApi.datastoreScope],
    );

    if (cachingClient != null) {
      cachingClient!.inner = _client;
      api = FirestoreApi(cachingClient!);
    } else {
      api = FirestoreApi(_client);
    }
  }

  @override
  Future<void> dispose() async {
    await cachingClient?.clearCache();
    _client.close();
  }
}
