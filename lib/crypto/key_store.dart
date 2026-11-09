import 'dart:convert';

import 'message_crypto.dart';

// Somewhere to keep a person's encryption keys SAFELY. The app only knows this
// interface; the real one uses Android's secure storage, tests use a fake.
// Keys are kept per online account id, so they survive linking and unlinking.
abstract class KeyStore {
  // The keys of this account, or null if none are stored on this phone.
  Future<PersonKeys?> load(String accountId);

  Future<void> save(String accountId, PersonKeys keys);

  Future<void> delete(String accountId);
}

// Keys as one piece of text, for storing.
String encodeKeys(PersonKeys keys) => jsonEncode({
  'public': base64Encode(keys.publicKeyBytes),
  'private': base64Encode(keys.privateKeyBytes),
});

// Reads keys back. Returns null if the text is damaged or has the wrong sizes.
PersonKeys? decodeKeys(String text) {
  try {
    final map = jsonDecode(text);
    if (map is! Map) {
      return null;
    }
    final publicKey = base64Decode(map['public'] as String);
    final privateKey = base64Decode(map['private'] as String);
    if (publicKey.length != PersonKeys.keyLength ||
        privateKey.length != PersonKeys.keyLength) {
      return null;
    }
    return PersonKeys(publicKeyBytes: publicKey, privateKeyBytes: privateKey);
  } catch (_) {
    return null;
  }
}
