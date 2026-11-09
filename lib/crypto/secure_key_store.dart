import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'key_store.dart';
import 'message_crypto.dart';

// The real key store: Android's secure storage (the Keystore). The private key
// never goes anywhere else. If the app is uninstalled, the keys are gone.
class SecureKeyStore implements KeyStore {
  final FlutterSecureStorage _storage;

  SecureKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  String _name(String accountId) => 'oneconnect_keys_$accountId';

  @override
  Future<PersonKeys?> load(String accountId) async {
    try {
      final text = await _storage.read(key: _name(accountId));
      if (text == null) {
        return null;
      }
      final keys = decodeKeys(text);
      if (keys == null) {
        await _storage.delete(key: _name(accountId)); // damaged: remove it
      }
      return keys;
    } catch (_) {
      // Unreadable (for example after a restore without the Keystore key):
      // treat it as "no keys on this phone".
      return null;
    }
  }

  @override
  Future<void> save(String accountId, PersonKeys keys) =>
      _storage.write(key: _name(accountId), value: encodeKeys(keys));

  @override
  Future<void> delete(String accountId) =>
      _storage.delete(key: _name(accountId));
}
