## 2.2.0

- Raise minimum Dart SDK constraint to `^3.10.0`.
- Widen `googleapis` version constraint to `>=16.0.0 <20.0.0` for compatibility with `googleapis` 16.x–19.x.
- Remove unused direct dependencies (`meta`, `_discoveryapis_commons`).
- Update locked dependencies and suppress `deprecated_member_use` infos for `googleapis/firestore/v1.dart`.

## 2.1.2

- Fix `getDocumentsByIds` database endpoint path to eliminate duplicate `/documents` in Firestore `batchGet` REST URL.

## 2.1.1

- Fix `batchWrite` database endpoint path to eliminate duplicate `/documents` in Firestore commit REST URL.
- Add `databasePath` getter to `FirestorePathUtils`.

## 2.1.0

- Add FirestoreOrder model and support advanced query features including projection, multi-order sorting, and collection group countingChore.

## 2.0.4

- Chore.

## 2.0.3

- Chore.

## 2.0.2

- Chore.

## 2.0.1

- Fix linter issue.

## 2.0.0

- Initial version.
