import 'package:flutter_test/flutter_test.dart';
import 'package:autocenter_app/features/auth/presentation/pages/branch_selection_screen.dart';

void main() {
  group('BranchItem Model Tests', () {
    test('should parse BranchItem from JSON correctly', () {
      final json = {
        'id': 10,
        'nome': 'Filial Principal',
        'documento': '12.345.678/0001-99',
        'deptoId': 2,
        'empresaErp': 1,
        'isDefault': true,
      };

      final branch = BranchItem.fromJson(json);

      expect(branch.id, 10);
      expect(branch.name, 'Filial Principal');
      expect(branch.document, '12.345.678/0001-99');
      expect(branch.deptoId, 2);
      expect(branch.empresaErp, 1);
      expect(branch.isDefault, true);
    });

    test('should use default values for missing JSON fields', () {
      final json = {
        'id': 20,
        'nome': 'Filial Secundária',
      };

      final branch = BranchItem.fromJson(json);

      expect(branch.id, 20);
      expect(branch.name, 'Filial Secundária');
      expect(branch.document, isNull);
      expect(branch.deptoId, 1);
      expect(branch.empresaErp, 1);
      expect(branch.isDefault, false);
    });
  });
}

