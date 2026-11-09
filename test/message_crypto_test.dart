import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/crypto/message_crypto.dart';

// Matches a call that fails because a message could not be verified.
final Matcher failsToDecrypt = throwsA(isA<MessageCryptoException>());

void main() {
  late MessageCrypto crypto;
  late PersonKeys ana;
  late PersonKeys ben;
  late RoomKey anaKey; // Ana's copy of the room key
  late RoomKey benKey; // Ben's copy of the room key

  setUp(() async {
    crypto = MessageCrypto();
    ana = await crypto.generateKeys();
    ben = await crypto.generateKeys();
    anaKey = await crypto.deriveRoomKey(
      mine: ana,
      otherPublicKey: ben.publicKeyBytes,
      roomId: 'room1',
    );
    benKey = await crypto.deriveRoomKey(
      mine: ben,
      otherPublicKey: ana.publicKeyBytes,
      roomId: 'room1',
    );
  });

  test('every key pair is new and has 32-byte keys', () async {
    final other = await crypto.generateKeys();

    expect(ana.publicKeyBytes.length, 32);
    expect(ana.privateKeyBytes.length, 32);
    expect(ana.publicKeyText == other.publicKeyText, false);
    expect(
      ana.privateKeyBytes.toString() == other.privateKeyBytes.toString(),
      false,
    );
  });

  test(
    'a message Ana encrypts can be read by Ben, and not seen in the text',
    () async {
      final payload = await crypto.encrypt(
        key: anaKey,
        text: 'See you at 8',
        messageId: 'm1',
        senderId: 'ana',
      );

      expect(payload.contains('See you'), false);
      expect(payload == base64Encode(utf8.encode('See you at 8')), false);
      expect(
        await crypto.decrypt(
          key: benKey,
          payload: payload,
          messageId: 'm1',
          senderId: 'ana',
        ),
        'See you at 8',
      );
    },
  );

  test('emoji, accents and | characters survive the round trip', () async {
    const text = 'Café ❤️ | 你好 | ñ';
    final payload = await crypto.encrypt(
      key: benKey,
      text: text,
      messageId: 'm2',
      senderId: 'ben',
    );

    expect(
      await crypto.decrypt(
        key: anaKey,
        payload: payload,
        messageId: 'm2',
        senderId: 'ben',
      ),
      text,
    );
  });

  test('the same message encrypted twice gives different results', () async {
    final first = await crypto.encrypt(
      key: anaKey,
      text: 'hi',
      messageId: 'm3',
      senderId: 'ana',
    );
    final second = await crypto.encrypt(
      key: anaKey,
      text: 'hi',
      messageId: 'm3',
      senderId: 'ana',
    );

    expect(first == second, false);
  });

  test('a message that was changed is refused', () async {
    final payload = await crypto.encrypt(
      key: anaKey,
      text: 'pay me 5',
      messageId: 'm4',
      senderId: 'ana',
    );
    final bytes = base64Decode(payload);
    bytes[bytes.length ~/ 2] ^= 1; // flip a single bit in the middle
    final tampered = base64Encode(bytes);

    await expectLater(
      crypto.decrypt(
        key: benKey,
        payload: tampered,
        messageId: 'm4',
        senderId: 'ana',
      ),
      failsToDecrypt,
    );
    await expectLater(
      crypto.decrypt(
        key: benKey,
        payload: 'not base64!!',
        messageId: 'm4',
        senderId: 'ana',
      ),
      failsToDecrypt,
    );
    await expectLater(
      crypto.decrypt(
        key: benKey,
        payload: 'AAAA',
        messageId: 'm4',
        senderId: 'ana',
      ),
      failsToDecrypt,
    );
  });

  test('a third person, or another room, cannot read the message', () async {
    final cara = await crypto.generateKeys();
    final caraKey = await crypto.deriveRoomKey(
      mine: cara,
      otherPublicKey: ana.publicKeyBytes,
      roomId: 'room1',
    );
    final otherRoomKey = await crypto.deriveRoomKey(
      mine: ben,
      otherPublicKey: ana.publicKeyBytes,
      roomId: 'room2',
    );
    final payload = await crypto.encrypt(
      key: anaKey,
      text: 'private',
      messageId: 'm5',
      senderId: 'ana',
    );

    await expectLater(
      crypto.decrypt(
        key: caraKey,
        payload: payload,
        messageId: 'm5',
        senderId: 'ana',
      ),
      failsToDecrypt,
    );
    await expectLater(
      crypto.decrypt(
        key: otherRoomKey,
        payload: payload,
        messageId: 'm5',
        senderId: 'ana',
      ),
      failsToDecrypt,
    );
  });

  test('a message is tied to its id and its sender', () async {
    final payload = await crypto.encrypt(
      key: anaKey,
      text: 'only for m6',
      messageId: 'm6',
      senderId: 'ana',
    );

    await expectLater(
      crypto.decrypt(
        key: benKey,
        payload: payload,
        messageId: 'm7',
        senderId: 'ana',
      ),
      failsToDecrypt,
    );
    await expectLater(
      crypto.decrypt(
        key: benKey,
        payload: payload,
        messageId: 'm6',
        senderId: 'ben',
      ),
      failsToDecrypt,
    );
  });

  test('a reply is authenticated by its original message id', () async {
    final payload = await crypto.encrypt(
      key: anaKey,
      text: 'Reply',
      messageId: 'reply1',
      senderId: 'ana',
      replyToId: 'original1',
    );

    await expectLater(
      crypto.decrypt(
        key: benKey,
        payload: payload,
        messageId: 'reply1',
        senderId: 'ana',
        replyToId: 'different-original',
      ),
      failsToDecrypt,
    );
    expect(
      await crypto.decrypt(
        key: benKey,
        payload: payload,
        messageId: 'reply1',
        senderId: 'ana',
        replyToId: 'original1',
      ),
      'Reply',
    );
  });

  test('the safety code is the same for both people and changes if a key '
      'is swapped', () async {
    final anaSees = await crypto.safetyCode(
      myPublicKey: ana.publicKeyBytes,
      otherPublicKey: ben.publicKeyBytes,
    );
    final benSees = await crypto.safetyCode(
      myPublicKey: ben.publicKeyBytes,
      otherPublicKey: ana.publicKeyBytes,
    );

    expect(anaSees, benSees);
    expect(RegExp(r'^\d{5}( \d{5}){5}$').hasMatch(anaSees), true);

    // Someone in the middle puts their own key in place of Ben's:
    final attacker = await crypto.generateKeys();
    final swapped = await crypto.safetyCode(
      myPublicKey: ana.publicKeyBytes,
      otherPublicKey: attacker.publicKeyBytes,
    );
    expect(swapped == anaSees, false);
  });

  test('public keys can be turned into text and back, and bad ones are '
      'rejected', () {
    final text = ana.publicKeyText;

    expect(PersonKeys.publicKeyFromText(text), ana.publicKeyBytes);
    expect(() => PersonKeys.publicKeyFromText('AAAA'), throwsFormatException);
    expect(() => PersonKeys.publicKeyFromText('!!!'), throwsFormatException);
  });
}
