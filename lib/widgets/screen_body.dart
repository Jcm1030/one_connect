import 'package:flutter/material.dart';

class ScreenBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ScreenBody({super.key, required this.child, this.maxWidth = 480});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
