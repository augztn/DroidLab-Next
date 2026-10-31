import 'package:droidlab_application/droidlab_application.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('router starts at dashboard and declares feature routes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);
    expect(router.routeInformationProvider.value.uri.path, '/dashboard');
  });
}
