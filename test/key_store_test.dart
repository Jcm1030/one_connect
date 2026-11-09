import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/crypto/key_store.dart';
import 'package:oneconnect/crypto/message_crypto.dart';

void main() {
  test('keys survive being turned into text and back', () async {
    final keys = await MessageCrypto().generateKeys();

    final restored = decodeKeys(encodeKeys(keys))!;

    expect(restored.publicKeyBytes, keys.publicKeyBytes);
    expect(restored.privateKeyBytes, keys.privateKeyBytes);
  });

  test('damaged key text is refused instead of crashing', () {
    expect(decodeKeys(''), null);
    expect(decodeKeys('not json'), null);
    expect(decodeKeys('[1, 2, 3]'), null);
    expect(
      decodeKeys('{"public": "AAAA", "private": "AAAA"}'),
      null,
    ); // too short
    expect(decodeKeys('{"public": 5, "private": 6}'), null); // wrong types
  });
}
