import 'package:flutter_test/flutter_test.dart';
import 'package:autocenter_app/features/customer/data/models/customer_model.dart';

void main() {
  group('CustomerModel Tests', () {
    test('should parse CustomerModel from JSON correctly', () {
      final json = {
        'id': 1,
        'erpId': 1001,
        'localId': 'local_99882233',
        'name': 'João da Silva',
        'fantasyName': 'Silva Auto',
        'cpfCnpj': '123.456.789-00',
        'phone': '(67) 99999-1122',
        'phone2': '(67) 3322-1100',
        'email': 'joao@silva.com',
        'city': 'Campo Grande',
        'address': 'Rua Principal, 123, Bairro Centro, Campo Grande, MS',
        'street': 'Rua Principal',
        'number': '123',
        'complement': 'Sala A',
        'neighborhood': 'Centro',
        'zip': '79002-000',
        'state': 'MS',
        'active': true,
        'syncStatus': 'synced',
      };

      final customer = CustomerModel.fromJson(json);

      expect(customer.id, 1);
      expect(customer.erpId, 1001);
      expect(customer.localId, 'local_99882233');
      expect(customer.name, 'João da Silva');
      expect(customer.fantasyName, 'Silva Auto');
      expect(customer.cpfCnpj, '123.456.789-00');
      expect(customer.phone, '(67) 99999-1122');
      expect(customer.phone2, '(67) 3322-1100');
      expect(customer.email, 'joao@silva.com');
      expect(customer.city, 'Campo Grande');
      expect(customer.address, 'Rua Principal, 123, Bairro Centro, Campo Grande, MS');
      expect(customer.street, 'Rua Principal');
      expect(customer.number, '123');
      expect(customer.complement, 'Sala A');
      expect(customer.neighborhood, 'Centro');
      expect(customer.zip, '79002-000');
      expect(customer.state, 'MS');
      expect(customer.active, true);
      expect(customer.syncStatus, 'synced');
    });

    test('should serialize CustomerModel to JSON correctly', () {
      final customer = CustomerModel(
        id: 2,
        erpId: null,
        localId: 'local_776655',
        name: 'Maria Santos',
        fantasyName: null,
        cpfCnpj: '987.654.321-11',
        phone: '(67) 98888-2233',
        zip: '79003-100',
        street: 'Avenida Getúlio Vargas',
        number: '456',
        neighborhood: 'Jardins',
        city: 'Campo Grande',
        state: 'MS',
        address: 'Avenida Getúlio Vargas, 456, Jardins, Campo Grande, MS',
        active: true,
        syncStatus: 'pending',
      );

      final json = customer.toJson();

      expect(json['id'], 2);
      expect(json['erp_id'], isNull);
      expect(json['local_id'], 'local_776655');
      expect(json['name'], 'Maria Santos');
      expect(json['fantasy_name'], isNull);
      expect(json['cpf_cnpj'], '987.654.321-11');
      expect(json['phone'], '(67) 98888-2233');
      expect(json['zip'], '79003-100');
      expect(json['street'], 'Avenida Getúlio Vargas');
      expect(json['number'], '456');
      expect(json['neighborhood'], 'Jardins');
      expect(json['city'], 'Campo Grande');
      expect(json['state'], 'MS');
      expect(json['active'], 1);
      expect(json['sync_status'], 'pending');
    });

    test('should copyWith updated values', () {
      final customer = CustomerModel(
        name: 'Carlos Cruz',
        syncStatus: 'pending',
      );

      final updated = customer.copyWith(
        erpId: 1050,
        syncStatus: 'synced',
      );

      expect(updated.name, 'Carlos Cruz');
      expect(updated.erpId, 1050);
      expect(updated.syncStatus, 'synced');
    });
  });
}
