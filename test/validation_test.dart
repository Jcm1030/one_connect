import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/models/profile.dart';
import 'package:oneconnect/validation.dart';

void main() {
  group('validateName', () {
    test('rejects an empty or blank name', () {
      expect(validateName(''), isNotNull);
      expect(validateName('   '), isNotNull);
    });

    test('rejects a name longer than 30 characters', () {
      expect(validateName('X' * 31), isNotNull);
    });

    test('accepts a normal name, ignoring spaces around it', () {
      expect(validateName('Ana'), null);
      expect(validateName('  ${'X' * 30}  '), null);
    });
  });

  group('validateUsername', () {
    final existing = [Profile(name: 'Ana', username: 'ana')];

    test('rejects usernames with the wrong length or characters', () {
      expect(validateUsername('', existing), isNotNull);
      expect(validateUsername('ab', existing), isNotNull);
      expect(validateUsername('a b!', existing), isNotNull);
      expect(validateUsername('abcdefghijklmnop', existing), isNotNull); // 16
    });

    test('accepts a good username', () {
      expect(validateUsername('ben', existing), null);
      expect(validateUsername('ben_1', existing), null);
      expect(validateUsername('abcdefghijklmno', existing), null); // 15
    });

    test('rejects a taken username, ignoring upper/lower case', () {
      expect(validateUsername('ana', existing), isNotNull);
      expect(validateUsername('ANA', existing), isNotNull);
    });
  });

  group('validateRoomCode', () {
    test('rejects codes that are not exactly 6 letters or numbers', () {
      expect(validateRoomCode(''), isNotNull);
      expect(validateRoomCode('abc'), isNotNull);
      expect(validateRoomCode('ABC2345'), isNotNull);
      expect(validateRoomCode('!!!!!!'), isNotNull);
    });

    test('accepts 6 letters or numbers in any case', () {
      expect(validateRoomCode('ABC234'), null);
      expect(validateRoomCode('abc234'), null);
      expect(validateRoomCode('  abc234  '), null);
    });
  });

  group('validateEmail', () {
    test('accepts normal email addresses, ignoring spaces around them', () {
      expect(validateEmail('ana@example.com'), null);
      expect(validateEmail('  ana.b+chat@mail.example.ph '), null);
    });

    test('rejects text that is not an email address', () {
      expect(validateEmail(''), isNotNull);
      expect(validateEmail('ana'), isNotNull);
      expect(validateEmail('ana@'), isNotNull);
      expect(validateEmail('ana@example'), isNotNull);
      expect(validateEmail('a na@example.com'), isNotNull);
      expect(validateEmail('ana@@example.com'), isNotNull);
    });
  });

  group('validatePassword', () {
    test('rejects blank, too short and too long passwords', () {
      expect(validatePassword(''), isNotNull);
      expect(validatePassword('           '), isNotNull); // only spaces
      expect(validatePassword('123456789'), isNotNull); // 9 characters
      expect(validatePassword('x' * 129), isNotNull);
    });

    test('accepts 10 to 128 characters, spaces included, and checks the '
        'confirmation', () {
      expect(validatePassword('1234567890'), null);
      expect(validatePassword('my long phrase'), null);
      expect(validatePassword('x' * 128), null);

      expect(validatePasswordConfirmation('abcdefghij', 'abcdefghij'), null);
      expect(validatePasswordConfirmation('abcdefghij', 'abcdefghiJ'),
          isNotNull);
    });
  });
}