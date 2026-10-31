import 'package:droidlab_application/droidlab_application.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('router provider initializes at dashboard', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    expect(router.routeInformationProvider.value.uri.path, '/dashboard');
  });
}
