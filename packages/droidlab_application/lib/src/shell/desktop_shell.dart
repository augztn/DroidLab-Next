import 'package:flutter/material.dart';

/// The desktop shell is kept in the application layer so shared app state can
/// be provided to the header, navigation and console without leaking into pages.
class DesktopShell extends StatelessWidget {
  const DesktopShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Desktop entrypoint currently owns the responsive shell implementation.
    // This wrapper is intentionally simple until shell widgets are extracted
    // into application presentation modules.
    return child;
  }
}
