/// Returns whether a package should be skipped for a requested batch action.
///
/// Uninstalled packages cannot be disabled, enabled, or uninstalled for a user.
/// Restoring is only meaningful after the package was uninstalled for that user.
bool shouldSkipDebloatAction({
  required String action,
  required bool installed,
  required bool disabled,
}) {
  if (!installed) return true;
  return switch (action) {
    'disable' => disabled,
    'enable' => !disabled,
    'restore' => true,
    'uninstall' => false,
    _ => false,
  };
}
