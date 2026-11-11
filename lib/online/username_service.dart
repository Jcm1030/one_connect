import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UsernameResult {
  final String username;
  final String uid;
  const UsernameResult({required this.username, required this.uid});
}

class UsernameService {
  UsernameService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static final _pattern = RegExp(r'^[a-z0-9_]{3,20}$');
  static const _reserved = {'admin', 'support', 'oneconnect', 'root', 'system'};

  // Returns an error message, or null when the name is fine.
  static String? validate(String raw) {
    final name = raw.trim().toLowerCase();
    if (!_pattern.hasMatch(name)) {
      return 'Use 3-20 letters, numbers or underscores.';
    }
    if (_reserved.contains(name)) {
      return 'That username is not available.';
    }
    return null;
  }

  Future<bool> isAvailable(String raw) async {
    final name = raw.trim().toLowerCase();
    if (validate(name) != null) {
      return false;
    }
    final snap = await _db.collection('usernames').doc(name).get();
    return !snap.exists;
  }

  // Suggests a free username based on the display name,
  // e.g. "Sam Cruz" -> "samcruz_4821".
  Future<String> suggestUsername(String displayName) async {
    final cleaned = displayName.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    // At least 3 characters, and short enough to leave room for "_1234".
    final padded = cleaned.padRight(3, 'x');
    final base = padded.length > 14 ? padded.substring(0, 14) : padded;
    final random = Random();

    for (var attempt = 0; attempt < 5; attempt++) {
      final candidate = '${base}_${1000 + random.nextInt(9000)}';
      if (await isAvailable(candidate)) {
        return candidate;
      }
    }
    // Very unlikely: five random names in a row were taken.
    return '${base}_${DateTime.now().millisecondsSinceEpoch % 100000}';
  }

  // The signed-in user's current username, or null if they have none yet.
  Future<String?> currentUsername() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return null;
    }
    final snap = await _db.collection('users').doc(uid).get();
    return snap.data()?['username'] as String?;
  }

  // Claims [raw] for the signed-in user and releases their old one.
  // Throws FormatException (bad name) or StateError (already taken).
  Future<String> setUsername(String raw) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Sign in first.');
    }
    final name = raw.trim().toLowerCase();
    final problem = validate(name);
    if (problem != null) {
      throw FormatException(problem);
    }

    final userRef = _db.collection('users').doc(uid);
    final newRef = _db.collection('usernames').doc(name);

    await _db.runTransaction((tx) async {
      final taken = await tx.get(newRef);
      if (taken.exists) {
        throw StateError('That username is already taken.');
      }
      final userSnap = await tx.get(userRef);
      final old = userSnap.data()?['username'] as String?;
      if (old == name) {
        return;
      }
      if (old != null) {
        tx.delete(_db.collection('usernames').doc(old));
      }
      tx.set(newRef, {
        'uid': uid,
        'username': name,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(userRef, {'username': name});
    });
    return name;
  }

  // Prefix search: "sa" finds "sam", "sara", "sa_dev". Never returns yourself.
  Future<List<UsernameResult>> search(String raw) async {
    final query = raw.trim().toLowerCase().replaceFirst('@', '');
    if (query.length < 2) {
      return [];
    }
    final myUid = _auth.currentUser?.uid;
    final snap = await _db
        .collection('usernames')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: query)
        .where(FieldPath.documentId, isLessThan: '$query\uf8ff')
        .limit(10)
        .get();
    return [
      for (final doc in snap.docs)
        if (doc.data()['uid'] != myUid)
          UsernameResult(username: doc.id, uid: doc.data()['uid'] as String),
    ];
  }
}
