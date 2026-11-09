import 'models/profile.dart';

// Input rules. Each function returns an error message if the input is
// not allowed, or null if it is fine. (Flutter form fields use the same
// "message or null" convention for their validators.)

const int maxNameLength = 30;

String? validateName(String value) {
  final name = value.trim();
  if (name.isEmpty) {
    return "Name can't be empty.";
  }
  if (name.length > maxNameLength) {
    return "Name can't be longer than $maxNameLength characters.";
  }
  return null;
}

// A username is 3 to 15 letters, numbers or underscores, and must not be
// used already. "Ana" and "ana" count as the same username.
String? validateUsername(String value, List<Profile> existingProfiles) {
  final username = value.trim();
  if (!RegExp(r'^[A-Za-z0-9_]{3,15}$').hasMatch(username)) {
    return 'Username must be 3 to 15 characters: letters, numbers or _ only.';
  }
  for (final profile in existingProfiles) {
    if (profile.username.toLowerCase() == username.toLowerCase()) {
      return 'That username is already taken. Try another one.';
    }
  }
  return null;
}

// A room code is exactly 6 letters or numbers (upper or lower case).
String? validateRoomCode(String value) {
  if (!RegExp(r'^[A-Za-z0-9]{6}$').hasMatch(value.trim())) {
    return 'A room code has exactly 6 letters or numbers.';
  }
  return null;
}

// ---------- Online account rules (used by the sign-up form in a later step) ----------
// These are only friendly checks on the phone. The server makes the final decision.

const int minPasswordLength = 10;
const int maxPasswordLength = 128;

String? validateEmail(String value) {
  final email = value.trim();
  if (email.length > 254 ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    return 'Enter a valid email address.';
  }
  return null;
}

// Passwords are NOT trimmed: spaces are allowed inside them.
String? validatePassword(String value) {
  if (value.trim().isEmpty) {
    return "Password can't be blank.";
  }
  if (value.length < minPasswordLength) {
    return 'Password must be at least $minPasswordLength characters.';
  }
  if (value.length > maxPasswordLength) {
    return "Password can't be longer than $maxPasswordLength characters.";
  }
  return null;
}

String? validatePasswordConfirmation(String password, String confirmation) {
  if (password != confirmation) {
    return 'Passwords do not match.';
  }
  return null;
}