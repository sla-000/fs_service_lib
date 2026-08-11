# fs_service_lib

[![CI](https://github.com/sla-000/fs_service_lib/actions/workflows/ci.yaml/badge.svg)](https://github.com/sla-000/fs_service_lib/actions/workflows/ci.yaml)
[![Coverage Status](https://coveralls.io/repos/github/sla-000/fs_service_lib/badge.svg?branch=dev)](https://coveralls.io/github/sla-000/fs_service_lib?branch=dev)
[![Pub Version](https://img.shields.io/pub/v/fs_service_lib.svg)](https://pub.dev/packages/fs_service_lib)

A Dart library for interacting with Google Cloud Firestore REST API via `googleapis`. It simplifies creating, reading, updating, and deleting Firestore documents and collections with built-in JSON mapping, typed value prefixes, and configurable in-memory HTTP response caching.

---

## Features

- **Firestore REST API Integration**: Direct interaction with Cloud Firestore using `googleapis` and standard Google Auth credentials.
- **Collection Queries & Filtering**: Powerful collection filtering via `queryCollection` using `FirestoreFilter` and `FirestoreOperator` (`isEqualTo`, `isGreaterThan`, `arrayContains`, etc.).
- **Collection Group Queries**: Easily query subcollections across all documents by `collectionId` with sorting and pagination.
- **Batch Operations**: Atomic `batchWrite` for multiple update and delete operations in a single HTTP request.
- **Batch Read**: Fast `getDocumentsByIds` fetching multiple specific documents by ID in one REST call.
- **Aggregations & Existence**: Built-in `countCollection` for document counts and `documentExists` for fast presence checks.
- **Subcollection Discovery**: Inspection of document subcollections via `getCollectionIds`.
- **Simplified JSON Mapping**: Convert raw JSON maps into Firestore documents and collections seamlessly, including recursive nested collections.
- **Typed Value Prefixes**: Easily handle non-standard JSON types (timestamps, geopoints, document references, and byte arrays) using simple string prefixes:
  - `datetime://` for UTC ISO-8601 Timestamps
  - `location://` for GeoPoints (`latitude/longitude`)
  - `reference://` for Document References
  - `bytes://` for Base64 Binary Data
- **Metadata Management**: Automatic injection and extraction of document metadata (e.g. `$name`, `$createTime`, `$updateTime`, `$collections`, `$documents`). Custom metadata prefixes are supported.
- **Smart In-Memory HTTP Caching**:
  - Transparent HTTP caching layer via `CachingHttpClient`.
  - Flexible cache invalidation strategies (`smart`, `all`, `none`).
  - Automatic invalidation on write/delete operations while safely bypassing read-only query endpoints.
  - Comprehensive cache statistics tracking (`hits`, `misses`, `stores`, `invalidations`, `hitRatioPercentage`).

---

## Getting Started

Add `fs_service_lib` to your `pubspec.yaml` dependencies:

```yaml
dependencies:
  fs_service_lib: ^2.0.0
```

Import the library in your Dart code:

```dart
import 'package:fs_service_lib/fs_service_lib.dart';
```

---

## Authentication & Environment Setup

`fs_service_lib` uses `clientViaApplicationDefaultCredentials` from `googleapis_auth` to authenticate requests against Google Cloud APIs (Firestore).

To run the application successfully, your environment must provide Google Application Default Credentials (ADC) through one of the following methods:

### 1. Service Account Key File (Environment Variable)
Set the `GOOGLE_APPLICATION_CREDENTIALS` environment variable to the absolute path of your GCP Service Account JSON key file:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"
```

> [!NOTE]
> Ensure the service account has appropriate IAM roles (e.g., `Cloud Datastore User` or `Firebase Admin`) for accessing your Firestore database.

### 2. Google Cloud Managed Infrastructure
When running on Google Cloud Platform (GCP) services such as Cloud Run, Google Kubernetes Engine (GKE), Compute Engine (GCE), App Engine, or Cloud Functions, credentials are acquired automatically via the GCP Metadata Server. No `GOOGLE_APPLICATION_CREDENTIALS` environment variable is required if the runtime service account has the necessary permissions.

### 3. Local Development with `gcloud` CLI
For local development without downloading a JSON key file, authenticate using the Google Cloud SDK CLI:

```bash
gcloud auth application-default login
```

This creates local user credentials (typically saved at `~/.config/gcloud/application_default_credentials.json` on Linux/macOS or `%APPDATA%\gcloud\application_default_credentials.json` on Windows) which `googleapis_auth` discovers automatically.

---

## Usage

### 1. Initialization

Initialize `FsServiceLib` with your Firebase/Google Cloud `projectId` and optional parameters:

```dart
final fsService = FsServiceLib();

Future<void> main() async {
  await fsService.init(
    projectId: 'your-firebase-project-id',
    databaseId: '(default)', // Default database ID
    cachingClient: CachingHttpClientMemory(
      ttl: const Duration(minutes: 30),
      cacheCheckPeriod: const Duration(minutes: 5),
      invalidationStrategy: CacheInvalidationStrategy.smart,
      onCacheHit: (url, stats) =>
          print('CACHE HIT: $url (${stats.hitRatioPercentage})'),
    ),
  );
}
```

### 2. Document & Collection Operations

#### Get a Single Document
```dart
final doc = await fsService.db.getDocument(
  documentPath: '/users/user-123',
);

print(doc);
// Output includes document fields + metadata:
// {
//   'name': 'John Doe',
//   '$name': 'user-123',
//   '$createTime': '2026-01-01T12:00:00.000Z',
//   '$updateTime': '2026-01-02T12:00:00.000Z'
// }
```

#### Check Document Existence
```dart
final exists = await fsService.db.documentExists(
  documentPath: '/users/user-123',
);
print('Exists: $exists');
```

#### Get Multiple Documents by IDs
```dart
final docs = await fsService.db.getDocumentsByIds(
  collectionPath: '/users',
  documentIds: ['user-123', 'user-456'],
);
print(docs);
```

#### Fetch a Collection
```dart
final collection = await fsService.db.getCollection(
  collectionPath: '/users',
  pageSize: 20,
  orderBy: 'name asc',
);

print(collection['$documents']); // List of document JSON objects
```

#### Query Collection with Filters
```dart
final activeUsers = await fsService.db.queryCollection(
  collectionPath: '/users',
  filters: [
    const FirestoreFilter(
      field: 'age',
      op: FirestoreOperator.isGreaterThanOrEqualTo,
      value: 18,
    ),
    const FirestoreFilter(
      field: 'status',
      op: FirestoreOperator.isEqualTo,
      value: 'active',
    ),
  ],
  limit: 10,
  orderBy: 'age',
  descending: false,
);
```

#### Count Documents in Collection
```dart
final totalCount = await fsService.db.countCollection(
  collectionPath: '/users',
  filters: [
    const FirestoreFilter(
      field: 'status',
      op: FirestoreOperator.isEqualTo,
      value: 'active',
    ),
  ],
);
print('Active users count: $totalCount');
```

#### Query a Collection Group
```dart
final posts = await fsService.db.getCollectionGroup(
  collectionId: 'posts',
  limit: 20,
  orderBy: 'dateTime',
  descending: true,
);

print(posts); // List of document JSON maps across all `posts` subcollections
```

#### Get Subcollection Names
```dart
final collectionIds = await fsService.db.getCollectionIds(
  documentPath: '/users/user-123',
);
print('Subcollections: $collectionIds');
```

#### Add a Document
```dart
await fsService.db.addDocument(
  collectionPath: '/users',
  json: {
    r'$name': 'user-123', // Optional custom document ID
    'name': 'Alice Smith',
    'age': 30,
    'location': 'location://37.7749/-122.4194',
    'createdAt': 'datetime://2026-08-05T18:00:00.000Z',
    'avatar': 'bytes://AAECAwQFBg==',
  },
);
```

#### Update a Document
```dart
await fsService.db.updateDocument(
  documentPath: '/users/user-123',
  json: {
    'age': 31,
  },
);
```

#### Atomic Batch Write (Update & Delete)
```dart
await fsService.db.batchWrite(
  writes: [
    const UpdateWrite(
      documentPath: '/users/user-123',
      json: {'status': 'active'},
    ),
    const DeleteWrite(
      documentPath: '/users/user-old',
    ),
  ],
);
```

#### Delete a Document or Collection
```dart
// Delete a specific document
await fsService.db.deleteDocument(
  documentPath: '/users/user-123',
);

// Delete an entire collection
await fsService.db.deleteCollection(
  collectionPath: '/tempCollection',
);
```

---

## Data Type Prefixes

`fs_service_lib` uses prefixed strings to map complex Firestore data types in standard JSON maps:

| Data Type | Prefix Syntax | Example |
|---|---|---|
| **Timestamp** | `datetime://<ISO-8601>` | `'datetime://2026-08-05T18:00:00Z'` |
| **GeoPoint** | `location://<lat>/<lon>` | `'location://37.7749/-122.4194'` |
| **Reference** | `reference://<path>` | `'reference://projects/my-proj/databases/(default)/documents/users/123'` |
| **Bytes** | `bytes://<base64>` | `'bytes://AAECAwQFBg=='` |

Custom prefixes can be configured when initializing `FsServiceLib`.

---

## Metadata Keys

Document metadata fields are prefixed with `$` by default:

- `$name`: Document ID or path.
- `$createTime`: Creation timestamp (UTC ISO-8601 string).
- `$updateTime`: Last modification timestamp (UTC ISO-8601 string).
- `$documents`: List of documents within a collection response.
- `$collections`: List of nested subcollections within a document JSON response.

---

## HTTP Caching & Invalidation

`fs_service_lib` supports transparent HTTP caching via the abstract `CachingHttpClient` interface to reduce Firestore REST API read operations and bandwidth costs.

### Configuring `CachingHttpClientMemory`

To enable in-memory caching, pass a configured instance of `CachingHttpClientMemory` when initializing `FsServiceLib` (or `FirestoreApiProviderImpl`):

```dart
final cachingClient = CachingHttpClientMemory(
  ttl: const Duration(minutes: 15),
  maxEntrySizeBytes: 512 * 1024, // 512 KB per response limit
  maxSizeBytes: 50 * 1024 * 1024, // 50 MB total memory limit
  cacheCheckPeriod: const Duration(minutes: 5),
  invalidationStrategy: CacheInvalidationStrategy.smart,
  onCacheHit: (url, stats) => print('CACHE HIT: $url'),
);

await fsService.init(
  projectId: 'your-firebase-project-id',
  cachingClient: cachingClient,
);
```

### Configuring `CachingHttpClientHive` (Persistent Disk Caching)

For persistent disk caching across application restarts using `hive_ce`, initialize Hive and pass an open `Box` to `CachingHttpClientHive`:

```dart
import 'package:hive_ce/hive.dart';

// Initialize Hive and open a cache box
Hive.init('/path/to/cache_dir');
final box = await Hive.openBox('http_cache');

final cachingClient = CachingHttpClientHive(
  box: box,
  ttl: const Duration(minutes: 30),
  maxEntrySizeBytes: 2 * 1024 * 1024, // 2 MB per response limit
  maxSizeBytes: 50 * 1024 * 1024,      // 50 MB total disk cache limit
  cacheCheckPeriod: const Duration(minutes: 10),
  invalidationStrategy: CacheInvalidationStrategy.smart,
  onCacheHit: (url, stats) => print('DISK CACHE HIT: $url'),
);

await fsService.init(
  projectId: 'your-firebase-project-id',
  cachingClient: cachingClient,
);
```

> [!CAUTION]
> **Cloud Run & Serverless Environments:** In Cloud Run or Cloud Functions, local files (e.g. in `/tmp`) use an in-memory filesystem (`tmpfs`). Writing files to disk consumes container RAM! Unless an external volume is mounted, set `maxSizeBytes` appropriately to avoid Out-Of-Memory (OOM) errors.

If `cachingClient` is omitted or passed as `null`, caching is completely disabled and all HTTP requests go directly to the Firestore REST API.

### Direct Cache Control & Memory Inspection

Since `CachingHttpClient` is managed directly, stats, memory usage, and cache operations are accessed on the `CachingHttpClient` instance:

```dart
// Inspect cache performance stats & current memory consumption
print(cachingClient.stats.hitRatioPercentage);
print('Current cache memory: ${cachingClient.currentSizeBytes} bytes');

// Manually flush all cached entries
cachingClient.clearCache();
```

### Cache Invalidation Strategies

- **`smart`** *(default)*: Clears the mutated document's cached URL and any parent collection cached responses upon successful mutating requests (PATCH, DELETE, non-query POST).
- **`all`**: Flushes the entire cache whenever a write or delete operation occurs.
- **`none`**: Bypasses auto-invalidation (requires manual cache management).

---

## Clean Up

Remember to dispose of resources when shutting down:

```dart
await fsService.dispose();
```
