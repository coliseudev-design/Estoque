import 'package:flutter_test/flutter_test.dart';

/// Testes de lógica de negócio para o fluxo de autenticação de vendedor.
///
/// rule-10: Cobre os casos de borda críticos do login offline via PIN.
/// Não depende de Flutter widgets (sem pump) — testa a lógica pura.
void main() {
  group('Login — validação de PIN offline', () {
    // Simula a comparação de PIN que ocorre em AuthService.verifyPin()
    bool verifyPin(String inputPin, String storedPin) {
      if (inputPin.isEmpty) return false;
      return inputPin.trim() == storedPin.trim();
    }

    test('PIN correto retorna true', () {
      expect(verifyPin('1234', '1234'), isTrue);
    });

    test('PIN incorreto retorna false', () {
      expect(verifyPin('0000', '1234'), isFalse);
    });

    test('PIN vazio retorna false (sem bypass)', () {
      expect(verifyPin('', '1234'), isFalse,
          reason: 'PIN vazio não deve autenticar — critical security check');
    });

    test('PIN com espaços extras é trimado antes da comparação', () {
      expect(verifyPin(' 1234 ', '1234'), isTrue);
    });

    test('PIN diferente de comprimento retorna false', () {
      expect(verifyPin('123', '1234'), isFalse);
    });
  });

  group('Login — restrição de empresa/filial', () {
    // Simula a lógica de verificação de permissão de empresa
    bool verifyCompanyPermission({
      required int? sellerErpEmpresaId,
      required int? activeBranchEmpresaId,
    }) {
      if (activeBranchEmpresaId == null) {
        // Se a filial não está configurada com ID de empresa, não permite login
        return false;
      }
      if (sellerErpEmpresaId == null) {
        // Se o vendedor não tem empresa setada (TODAS), ele pode acessar qualquer filial
        return true;
      }
      return sellerErpEmpresaId == activeBranchEmpresaId;
    }

    test('Vendedor com ID de empresa correspondente pode fazer login', () {
      expect(verifyCompanyPermission(sellerErpEmpresaId: 1, activeBranchEmpresaId: 1), isTrue);
    });

    test('Vendedor com ID de empresa diferente é bloqueado', () {
      expect(verifyCompanyPermission(sellerErpEmpresaId: 1, activeBranchEmpresaId: 2), isFalse);
    });

    test('Vendedor sem empresa setada (null/TODAS) é permitido', () {
      expect(verifyCompanyPermission(sellerErpEmpresaId: null, activeBranchEmpresaId: 1), isTrue);
      expect(verifyCompanyPermission(sellerErpEmpresaId: null, activeBranchEmpresaId: 2), isTrue);
    });

    test('Filial sem ID de empresa (null) bloqueia login de todos', () {
      expect(verifyCompanyPermission(sellerErpEmpresaId: 1, activeBranchEmpresaId: null), isFalse);
      expect(verifyCompanyPermission(sellerErpEmpresaId: null, activeBranchEmpresaId: null), isFalse);
    });
  });

  group('Pedido — validação de payload antes do envio ao servidor', () {
    /// Simula a validação que ocorre em OrderRepository antes de aceitar um pedido.
    String? validateOrderPayload({
      required String? customerId,
      required List<Map<String, dynamic>> items,
      required double totalAmount,
    }) {
      if (customerId == null || customerId.isEmpty) {
        return 'Cliente obrigatório';
      }
      if (items.isEmpty) {
        return 'O pedido deve ter pelo menos 1 item';
      }
      for (final item in items) {
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        if (qty <= 0) return 'Quantidade inválida no item ${item['productCode']}';
        final price = (item['unitPrice'] as num?)?.toDouble() ?? -1.0;
        if (price < 0) return 'Preço inválido no item ${item['productCode']}';
      }
      if (totalAmount < 0) return 'Valor total não pode ser negativo';
      return null; // válido
    }

    test('Payload válido retorna null (sem erro)', () {
      final error = validateOrderPayload(
        customerId: 'cust-001',
        items: [
          {'productCode': 'P001', 'quantity': 2, 'unitPrice': 50.0},
        ],
        totalAmount: 100.0,
      );
      expect(error, isNull);
    });

    test('Payload sem customerId retorna mensagem de erro', () {
      final error = validateOrderPayload(
        customerId: null,
        items: [{'productCode': 'P001', 'quantity': 1, 'unitPrice': 10.0}],
        totalAmount: 10.0,
      );
      expect(error, isNotNull);
      expect(error, contains('Cliente'));
    });

    test('Payload com items vazios retorna erro', () {
      final error = validateOrderPayload(
        customerId: 'cust-001',
        items: [],
        totalAmount: 0.0,
      );
      expect(error, isNotNull);
      expect(error, contains('item'));
    });

    test('Item com quantidade zero retorna erro', () {
      final error = validateOrderPayload(
        customerId: 'cust-001',
        items: [{'productCode': 'P001', 'quantity': 0, 'unitPrice': 10.0}],
        totalAmount: 0.0,
      );
      expect(error, isNotNull);
      expect(error, contains('Quantidade'));
    });

    test('Item com preço negativo retorna erro', () {
      final error = validateOrderPayload(
        customerId: 'cust-001',
        items: [{'productCode': 'P001', 'quantity': 1, 'unitPrice': -5.0}],
        totalAmount: -5.0,
      );
      expect(error, isNotNull);
      expect(error, contains('Preço'));
    });

    test('Total negativo retorna erro', () {
      final error = validateOrderPayload(
        customerId: 'cust-001',
        items: [{'productCode': 'P001', 'quantity': 1, 'unitPrice': 0.0}],
        totalAmount: -1.0,
      );
      expect(error, isNotNull);
      expect(error, contains('negativo'));
    });
  });
}
