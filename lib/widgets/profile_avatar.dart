import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/profile.dart';
import '../theme.dart';

// A round picture for a person: their photo if they have one, otherwise
// their initial in their own color. With no profile it shows a heart.
class ProfileAvatar extends StatelessWidget {
  final AppState appState;
  final Profile? profile;
  final double radius;

  const ProfileAvatar({
    super.key,
    required this.appState,
    required this.profile,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final person = profile;
    if (person == null) {
      return CircleAvatar(
        radius: radius,
        child: Icon(Icons.person_outline, size: radius * 0.9),
      );
    }

    final photo = appState.photoFileOf(person);
    if (photo != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: seedColorFor(person.color),
        backgroundImage: FileImage(photo),
        // If the picture cannot be read, the colored circle stays.
        onBackgroundImageError: (_, _) {},
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: seedColorFor(person.color),
      foregroundColor: Colors.white,
      child: Text(
        String.fromCharCode(person.name.runes.first).toUpperCase(),
        style: TextStyle(fontSize: radius * 0.8),
      ),
    );
  }
}
