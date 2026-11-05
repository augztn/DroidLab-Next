/// Returns whether a package should be skipped for a requested batch action.
///
/// State-changing actions require the package to be installed for this user;
/// restore is only meaningful when it is no longer installed for that user.
bool shouldSkipDebloatAction({
  required String action,
  required bool installed,
  required bool disabled,
}) {
  return switch (action) {
    'disable' => !installed || disabled,
    'enable' => !installed || !disabled,
    'restore' => installed,
    'uninstall' => !installed,
    _ => false,
  };
}
