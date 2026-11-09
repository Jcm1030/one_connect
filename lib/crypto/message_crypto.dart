import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

// End-to-end encryption for messages. Everything here is plain Dart and uses
// the well-known "cryptography" package: no home-made cryptography.
//
// How it works:
//  1. Each person makes a key pair (X25519). The PUBLIC key can be shared with
//     the other person. The PRIVATE key must never leave the phone.
//  2. Each person combines their own private key with the other's public key.
//     Both get the same secret, and nobody else can compute it.
//  3. That secret is turned (HKDF) into one encryption key for the room.
//  4. Every message is encrypted with AES-GCM using a fresh random nonce. The
//     message id and the sender are "bound" to it, so a scrambled message
//     cannot be moved to another message or pretended to come from someone else.
//  5. A "safety code" lets both people check, in person, that nobody swapped
//     the keys on the way.

class MessageCryptoException implements Exception {
  final String message;

  const MessageCryptoException(this.message);

  @override
  String toString() => 'MessageCryptoException: $message';
}

// A person's key pair, as raw bytes.
class PersonKeys {
  static const int keyLength = 32;

  final List<int> publicKeyBytes; // safe to share
  final List<int> privateKeyBytes; // NEVER share or send anywhere

  const PersonKeys({
    required this.publicKeyBytes,
    required this.privateKeyBytes,
  });

  static const int publicKeyTextLength = 44;

  // The public key as text, so it can be stored online.
  String get publicKeyText => base64Encode(publicKeyBytes);

  // Reads a public key from its text form.
  // Throws FormatException if it is not a valid 32-byte key.
  static List<int> publicKeyFromText(String text) {
    final bytes = base64Decode(text);
    if (bytes.length != keyLength) {
      throw const FormatException('A public key must be 32 bytes long.');
    }
    return bytes;
  }
}

// The encryption key shared by the two people of one room.
class RoomKey {
  final SecretKey _secret;

  RoomKey._(this._secret);
}

class MessageCrypto {
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  final X25519 _x25519 = X25519();
  final AesGcm _aes = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final Random _random = Random.secure();

  SimplePublicKey _publicKeyOf(List<int> bytes) {
    if (bytes.length != PersonKeys.keyLength) {
      throw const MessageCryptoException('A public key must be 32 bytes long.');
    }
    return SimplePublicKey(bytes, type: KeyPairType.x25519);
  }

  // Makes a new key pair for one person.
  Future<PersonKeys> generateKeys() async {
    final pair = await _x25519.newKeyPair();
    final publicKey = await pair.extractPublicKey();
    final privateBytes = await pair.extractPrivateKeyBytes();
    return PersonKeys(
      publicKeyBytes: publicKey.bytes,
      privateKeyBytes: privateBytes,
    );
  }

  // Both room members derive the same key from their private key and the
  // other person's public key.
  Future<RoomKey> deriveRoomKey({
    required PersonKeys mine,
    required List<int> otherPublicKey,
    required String roomId,
  }) async {
    final myPair = SimpleKeyPairData(
      mine.privateKeyBytes,
      publicKey: _publicKeyOf(mine.publicKeyBytes),
      type: KeyPairType.x25519,
    );
    final shared = await _x25519.sharedSecretKey(
      keyPair: myPair,
      remotePublicKey: _publicKeyOf(otherPublicKey),
    );
    final key = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('oneConnect v1 room key'),
      info: utf8.encode(roomId),
    );
    return RoomKey._(key);
  }

  // What the message is "bound" to, so it cannot be reused elsewhere.
  List<int> _boundData(String messageId, String senderId, String? replyToId) =>
      utf8.encode(
        replyToId == null
            ? '$messageId|$senderId'
            : '$messageId|$senderId|$replyToId',
      );

  // Scrambles a message. The result is text (nonce + scrambled text + check
  // value, in base64) that is safe to store online.
  Future<String> encrypt({
    required RoomKey key,
    required String text,
    required String messageId,
    required String senderId,
    String? replyToId,
  }) async {
    final nonce = List<int>.generate(_nonceLength, (_) => _random.nextInt(256));
    final box = await _aes.encrypt(
      utf8.encode(text),
      secretKey: key._secret,
      nonce: nonce,
      aad: _boundData(messageId, senderId, replyToId),
    );
    return base64Encode([...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  // Unscrambles a message. Throws MessageCryptoException if the text was
  // changed, if the key is wrong, or if it belongs to another message or sender.
  Future<String> decrypt({
    required RoomKey key,
    required String payload,
    required String messageId,
    required String senderId,
    String? replyToId,
  }) async {
    final List<int> bytes;
    try {
      bytes = base64Decode(payload);
    } on FormatException {
      throw const MessageCryptoException('The message is not valid.');
    }
    if (bytes.length < _nonceLength + _macLength) {
      throw const MessageCryptoException('The message is too short.');
    }

    final nonce = bytes.sublist(0, _nonceLength);
    final macBytes = bytes.sublist(bytes.length - _macLength);
    final cipherText = bytes.sublist(_nonceLength, bytes.length - _macLength);

    try {
      final plain = await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: key._secret,
        aad: _boundData(messageId, senderId, replyToId),
      );
      return utf8.decode(plain);
    } on SecretBoxAuthenticationError {
      throw const MessageCryptoException(
        'The message could not be verified. It may have been changed.',
      );
    } on FormatException {
      throw const MessageCryptoException('The message is not valid text.');
    }
  }

  int _compareBytes(List<int> a, List<int> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) {
        return a[i] < b[i] ? -1 : 1;
      }
    }
    return a.length.compareTo(b.length);
  }

  // A code made from BOTH public keys, shown as six groups of five digits,
  // for example "12345 67890 12345 67890 12345 67890".
  // Both people get the same code. If the codes match when they compare
  // them in person, nobody has swapped the keys on the way.
  Future<String> safetyCode({
    required List<int> myPublicKey,
    required List<int> otherPublicKey,
  }) async {
    // Put the keys in a fixed order, so both phones compute the same thing.
    final ordered = _compareBytes(myPublicKey, otherPublicKey) <= 0
        ? [...myPublicKey, ...otherPublicKey]
        : [...otherPublicKey, ...myPublicKey];
    final hash = await Sha256().hash(ordered);
    final bytes = hash.bytes;

    final groups = <String>[];
    for (var i = 0; i < 6; i++) {
      final number =
          (bytes[i * 4] << 24) |
          (bytes[i * 4 + 1] << 16) |
          (bytes[i * 4 + 2] << 8) |
          bytes[i * 4 + 3];
      groups.add((number % 100000).toString().padLeft(5, '0'));
    }
    return groups.join(' ');
  }
}
