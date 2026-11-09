// The three colors a person can choose for the app when creating a profile.
enum ProfileColor { purple, teal, pink }

// A Profile stores who a person is: their name, username and chosen color.
// The name can be changed later; the username never changes.
class Profile {
  String name;
  final String username;
  ProfileColor color;

  // The id of this person's online account (from Firebase, later).
  // It is null for profiles that only exist on this phone.
  // Only this id is kept in the save file: never the email or the password.
  String? accountId;

  // The name of this person's photo file (inside the app's photos folder),
  // or null if they have no photo. Only the name is kept, never a full path.
  String? photoFileName;

  Profile({
    required this.name,
    required this.username,
    this.color = ProfileColor.pink,
    this.accountId,
    this.photoFileName,
  });

  @override
  String toString() => '$name (@$username)';
}
