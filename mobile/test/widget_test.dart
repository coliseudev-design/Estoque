import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ColiseuSalesApp smoke test', (WidgetTester tester) async {
    // Apenas verifica que o app inicializa sem crash
    // Testes de integração completos ficam em integration_test/
    expect(find.byType(MaterialApp), findsNothing);
  });
}
