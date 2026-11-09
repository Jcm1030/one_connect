# oneConnect encryption design (step 6d-1)

Status: the Android chat client uses this crypto for online messages. The
Firestore deployment and cross-device behavior still need validation.

## What it does

| Step | Algorithm (from the `cryptography` package) | Purpose |
|---|---|---|
| Key pair per person | X25519 | A public key to share, a private key to keep |
| Shared secret | X25519 key agreement | Both room members compute the same secret; nobody else can |
| Room key | HKDF-SHA256, salt "oneConnect v1 room key", info = room id | One key per room |
| Message encryption | AES-256-GCM, random 12-byte nonce | Hides the text and detects any change |
| Binding | message id + sender id as "associated data" | A message cannot be moved to another message or sender |
| Safety code | SHA-256 of both public keys, six groups of five digits | Room members compare it in person to detect swapped keys |

A stored message is one base64 text: `nonce (12) + scrambled text + check value (16)`.

## What it does NOT do (honest limits)

- **No forward secrecy.** Each person has one fixed key pair. If a phone's
  private key were ever stolen, messages encrypted with it could be read. There
  is no Signal-style "ratchet" that changes keys for every message.
- **The server still sees metadata:** who is in which room, who sent a message
  and when, and roughly how long it is.
- **Keys are only as safe as the phone.** The private key is kept in Android
  secure storage.
- **A lost or reinstalled phone loses its keys.** There is no backup, by choice.
  Both people start a new room.
- **The safety code only protects people who actually compare it** in person.
  Without that check, a dishonest server could swap a public key.
- **Not independently reviewed.** It uses a standard library and standard
  algorithms, but the way they are combined here has not been audited.

## Remaining work

- Deploy and test `firestore.rules` with the Firebase project and emulator.
- Validate room approval, message delivery, and safety-code verification across
  two physical Android devices.
- Add iOS Firebase configuration and verify secure key storage on iOS before
  supporting iPhones.
- Complete an independent security review before relying on it for sensitive
  conversations.
