import 'package:oneconnect/crypto/key_store.dart';
import 'package:oneconnect/crypto/message_crypto.dart';

// A key store that lives in memory, for tests. Set "failSave" to pretend the
// phone's secure storage is broken.
class MemoryKeyStore implements KeyStore {
  final Map<String, PersonKeys> keys = {};
  bool failSave = false;

  @override
  Future<PersonKeys?> load(String accountId) async => keys[accountId];

  @override
  Future<void> save(String accountId, PersonKeys newKeys) async {
    if (failSave) {
      throw StateError('secure storage is broken');
    }
    keys[accountId] = newKeys;
  }

  @override
  Future<void> delete(String accountId) async {
    keys.remove(accountId);
  }
}
