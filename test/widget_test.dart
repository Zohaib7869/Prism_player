import 'package:flutter_test/flutter_test.dart';

import 'package:prism_player/main.dart';

void main() {
  testWidgets('Prism Player app widget can be created', (WidgetTester tester) async {
    expect(const PrismPlayerApp(), isA<PrismPlayerApp>());
  });
}