# oneConnect

A private messaging app for **two people** (roommates, friends, or any pair),
written in Flutter. It supports local data and an Android online-chat
implementation using Firebase.

The `app_logo.png` artwork is used in the app header and as the installed app
icon across the supported platforms.

> This project was built step by step with an AI assistant, as a way to learn
> Flutter and Dart. See "Project status" for exactly what has and has not
> been verified.

## Features

- **One profile per phone** with a name, a unique username, a color (Purple,
  Teal or Pink) and an optional **photo** (from the gallery or camera).
- **Verified email required:** link one verified email account to the profile
  before opening rooms. Email and password are handled by Firebase.
- **Online rooms** for two people, joined with a 6-character code and room
  creator approval.
- **Chat** with message bubbles, times, Sent / Seen status, unread counts and
  a 500-character limit. Online message text is encrypted end-to-end.
- **Action sound effects** play a short chime after successful room actions,
  such as creating, joining, approving, or leaving a room.
- **New-message highlights:** a room with unread messages glows softly in the
  list, and messages that were waiting when you open a chat glow briefly under
  a \"New messages\" line.
- **Closed rooms:** when one of the two people leaves, the room stops accepting
  new members, so nobody can join later and read the conversation. If the
  creator leaves, the remaining roommate becomes the room owner.
- **Settings:** light / dark / follow-the-phone theme, three text sizes, and a
  "Reduce animations" switch.
- **Friendly animations:** smooth screen changes, lists that appear row by row,
  messages that pop in, and a gently beating heart. All of it turns off with
  "Reduce animations" or the phone's own accessibility setting.
- **Saved locally:** profile and appearance settings survive closing the app.

## Project status

| Stage | What | State |
|---|---|---|
| 1-4 | Console prototype (Java), validation, saving, rooms | Done (Java version, kept as a reference) |
| 5 | Flutter app with Profile, Rooms and Chat screens | Written |
| 5+ | Messenger look, colors, dark mode, settings, animations | Written |
| 6a | Message IDs, storage behind an interface | Written |
| 6b | Account ID on profiles, email/password rules, online design | Written |
| 6c | Account screens and Firebase authentication | Written |
| 6d | Android online rooms and encrypted messages | Client implemented; Firebase deployment and device testing remain |
| 6e | Hardening, key backup | **Not started** |

**Verification status:** local unit and widget tests and `flutter analyze` are
run during development. The online client has not yet been validated against
deployed Firestore rules or between two physical devices.

## Getting started

### Requirements

- Flutter (a recent version: the code uses Dart 3 features and `TextScaler`)
- An Android phone or emulator. The screenshot block is Android-only.
- **Windows tip:** keep the project in a plain folder such as `C:\dev\oneconnect`.
  Folders synced by OneDrive lock build files and make Gradle fail.

### Set up

1. Create the project, using this exact name (the tests import
   `package:oneconnect/...`):
   ```
   flutter create oneconnect
   cd oneconnect
   flutter pub add path_provider image_picker cryptography cloud_firestore audioplayers
   ```
2. Copy this project's `lib/` and `test/` folders into it, replacing what is
   there. **Delete** the generated `test/widget_test.dart`.
3. Screenshot blocking (Android): open
   `android/app/src/main/kotlin/com/example/oneconnect/MainActivity.kt` and
   add the `onCreate` block from this project's copy of that file. Keep your
   own `package` line.

### Run and test

```
flutter analyze
flutter test
flutter run         # on your phone or emulator
```

## How it is organized

```
lib/
  main.dart               starts the Android Firebase-backed app
  app.dart                the app root: theme, text size, animations
  app_state.dart          the app's data and actions (profiles, rooms, settings)
  theme.dart              colors and the look of the app, light and dark
  animations.dart         the small animations, and "reduce animations"
  validation.dart         the rules for names, usernames, codes, emails, passwords
  formatting.dart         message times and room-member labels
  models/                 Profile, Message, ChatRoom, AppSettings (plain Dart)
  profile_avatar.dart     a person's round photo, or their initial
  photos/                 photo picking (image_picker) and the photos folder
  crypto/                 end-to-end encryption and secure key storage
  online/                 Firestore room and encrypted-message service
  storage/
    app_storage.dart      the interface any storage must follow
    data_store.dart       saves and loads one text file
    save_location.dart    finds the phone's documents folder
  accounts/
    account_service.dart  sign up / sign in / verify email (interface)
    firebase_error_codes.dart
  screens/                Profile, Rooms, Chat, Account, Settings
test/                     unit and widget tests (with fakes in test/helpers)
firestore.rules           access rules for online rooms and messages
android/.../MainActivity.kt  screenshot blocking
```

**Why it is built this way**

- **Models know nothing about screens or files.** They hold the rules (a room
  has two members, a closed room refuses newcomers, and so on), so those rules
  are easy to test.
- **`AppState` is the single place screens go to** for data and actions. After a
  change, a screen redraws with `setState`, and saves.
- **Storage sits behind `AppStorage`,** so another storage could replace the
  text file without touching the screens. Tests use fake storage.
- **No state-management package.** Plain Flutter is enough at this size.

## The save file

One plain text file, `oneconnect-data.txt`, in the phone's documents folder.
Each line is one record, fields separated by `|`. Free text (a name or a
message) is always last, so a `|` inside it is safe.

```
SETTING|theme|dark                 (also textSize, reduceAnimations)
PROFILE|username|name
COLOR|username|teal
ACCOUNT|username|accountId         (only for profiles with an online account)
PHOTO|username|fileName            (only for profiles with a photo)
ROOM|code|username1|username2      (a closed room ends with |#closed)
MSG2|code|senderUsername|timestamp|seen|messageId|text
```

Older files still load: `MESSAGE|...` lines (no id) are upgraded, and missing
`COLOR` or `SETTING` lines use defaults. Damaged lines are skipped with a
warning instead of crashing, and the file is written to a temporary file first,
so a crash while saving cannot ruin the old data.

## Privacy and security (honest summary)

- **Local save files are plain text.** Anyone with access to the phone's app
  files could read locally saved profiles and offline messages.
- **Online message text is end-to-end encrypted** using keys held in Android
  secure storage. Firestore stores ciphertext and room metadata, not message
  text. The safety code must be compared over a trusted channel before sending.
- **The online implementation is not independently security-reviewed.** It
  has not yet been validated against a deployed Firestore database and rules.
- **Screenshots and screen recording are blocked on Android** (needs the
  `MainActivity.kt` change). Another phone can still photograph the screen.
- **Messages cannot be selected or copied,** and the message box has no Copy or
  Cut. Room codes have a Copy button for convenience. A copied code stays on the
  clipboard where other apps could read it.
- **Emails and passwords are never saved by the app.** Only an account ID is.
- **Profile photos** are copied into a private `photos` folder inside the app's
  storage, shrunk to at most 512 x 512 pixels. They are not encrypted. Photos
  are local only: sharing them with another person on another phone is not designed
  yet and would need extra work.

## Enabling online messaging

The Android client uses Firebase Authentication and Cloud Firestore. Joining
with a room code creates a request; the room creator must approve it. Before
either person can send messages, both phones show the same encryption safety
code and each person must confirm that they compared it. Push notifications
while the app is closed are not implemented.

To enable it in the Firebase project:

1. Enable **Cloud Firestore** and **Email/Password Authentication** in the
   Firebase Console. If the app reports that the Firestore API has not been
   used or is disabled, enable the [Cloud Firestore API in Google Cloud
   Console](https://console.developers.google.com/apis/api/firestore.googleapis.com/overview?project=oneconnect-a3007)
   and wait a few minutes for the change to take effect.
2. Deploy the latest rules in `firestore.rules` using
   `firebase deploy --only firestore:rules --project oneconnect-a3007`.
   Firestore uses the deployed rules, not the local file; deploy again after
   pulling any rule updates.
3. Run the Android app with a verified email account on each phone.

The current Firebase app configuration is Android-only. iOS requires
registering an iOS Firebase app and generating iOS Firebase options.

## Known limitations

- Messages are single-line. Pasted line breaks become spaces.
- One phone can hold several profiles. That is a testing aid, not how online use
  would work.
- Leaving a room as its last member deletes the room and its messages.
- There is no message deletion, search, or media.
- The Java reference version still lets a third person join after someone has
  left a room (the closed-room rule exists only in the Flutter app).

## The Java reference version

The original console prototype lives in a separate folder (`oneConnect/`). It
is the working design the Flutter code was ported from. See its own README.#   o n e _ c o n n e c t  
 