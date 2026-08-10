import 'package:flutter_test/flutter_test.dart';
import 'package:autocenter_app/features/service_order/data/models/service_order_model.dart';
import 'package:autocenter_app/features/service_order/domain/entities/service_order.dart';

void main() {
  group('ServiceOrderModel Tests', () {
    test('should parse ServiceOrderModel from JSON correctly', () {
      final json = {
        'id': 'os_1234567890',
        'quoteId': 'quote_uuid_placeholder',
        'deviceId': 'device_test_123',
        'plate': 'ABC1D23',
        'customerId': 1001,
        'customerName': 'Pedro de Souza',
        'customerPhone': '(67) 98888-7766',
        'status': 'ABERTA',
        'totalAmount': 350.50,
        'observation': 'Troca de pastilhas de freio dianteiras.',
        'createdAt': '2026-07-09T12:00:00Z',
        'updatedAt': '2026-07-09T12:00:00Z',
        'syncStatus': 'synced',
        'items': [
          {
            'id': 'item_1',
            'service_order_id': 'os_1234567890',
            'product_code': 'PAST-01',
            'product_description': 'Pastilha de Freio Cobreq',
            'quantity': 1.0,
            'unit_price': 150.50,
            'total_price': 150.50,
            'item_type': 'PART',
            'technician_id': 5,
            'created_at': '2026-07-09T12:00:00Z'
          },
          {
            'id': 'item_2',
            'service_order_id': 'os_1234567890',
            'product_code': 'MAO-DE-OBRA',
            'product_description': 'Serviço de troca de pastilhas',
            'quantity': 1.0,
            'unit_price': 200.00,
            'total_price': 200.00,
            'item_type': 'SERVICE',
            'technician_id': 5,
            'created_at': '2026-07-09T12:00:00Z'
          }
        ],
        'photos': [
          {
            'id': 'photo_1',
            'service_order_id': 'os_1234567890',
            'photo_url': '/uploads/photo_frente.jpg',
            'photo_type': 'FRONT',
            'created_at': '2026-07-09T12:00:00Z'
          }
        ],
        'checklist': [
          {
            'id': 'checklist_1',
            'service_order_id': 'os_1234567890',
            'item_name': 'Nível de Óleo',
            'status': 'OK',
            'observation': 'Nível ideal',
            'created_at': '2026-07-09T12:00:00Z',
            'updated_at': '2026-07-09T12:00:00Z'
          }
        ]
      };

      final os = ServiceOrderModel.fromJson(json);

      expect(os.id, 'os_1234567890');
      expect(os.quoteId, 'quote_uuid_placeholder');
      expect(os.deviceId, 'device_test_123');
      expect(os.plate, 'ABC1D23');
      expect(os.customerId, 1001);
      expect(os.customerName, 'Pedro de Souza');
      expect(os.customerPhone, '(67) 98888-7766');
      expect(os.status, 'ABERTA');
      expect(os.totalAmount, 350.50);
      expect(os.observation, 'Troca de pastilhas de freio dianteiras.');
      expect(os.createdAt, '2026-07-09T12:00:00Z');
      expect(os.updatedAt, '2026-07-09T12:00:00Z');
      expect(os.syncStatus, 'synced');
      
      expect(os.items.length, 2);
      expect(os.items[0].productDescription, 'Pastilha de Freio Cobreq');
      expect(os.items[0].itemType, 'PART');
      expect(os.items[1].productDescription, 'Serviço de troca de pastilhas');
      expect(os.items[1].itemType, 'SERVICE');

      expect(os.photos.length, 1);
      expect(os.photos[0].photoType, 'FRONT');

      expect(os.checklist.length, 1);
      expect(os.checklist[0].itemName, 'Nível de Óleo');
      expect(os.checklist[0].status, 'OK');
    });

    test('should convert ServiceOrderModel to JSON correctly', () {
      final items = [
        ServiceOrderItem(
          id: 'item_1',
          serviceOrderId: 'os_9988',
          productCode: 'O-20W50',
          productDescription: 'Óleo Motor 20W50 Lubrax',
          quantity: 4.0,
          unitPrice: 35.0,
          totalPrice: 140.0,
          itemType: 'PART',
          createdAt: '2026-07-09T12:00:00Z',
        )
      ];

      final os = ServiceOrderModel(
        id: 'os_9988',
        deviceId: 'device_test_99',
        plate: 'XYZ9K88',
        customerId: null,
        customerName: 'Cliente Balcão',
        customerPhone: null,
        status: 'EM_EXECUCAO',
        totalAmount: 140.0,
        observation: 'Troca de óleo.',
        createdAt: '2026-07-09T12:00:00Z',
        updatedAt: '2026-07-09T12:00:00Z',
        syncStatus: 'pending',
        items: items,
      );

      final json = os.toJson();

      expect(json['id'], 'os_9988');
      expect(json['device_id'], 'device_test_99');
      expect(json['plate'], 'XYZ9K88');
      expect(json['customer_id'], isNull);
      expect(json['customer_name'], 'Cliente Balcão');
      expect(json['status'], 'EM_EXECUCAO');
      expect(json['total_amount'], 140.0);
      expect(json['items'].length, 1);
      expect(json['items'][0]['product_code'], 'O-20W50');
      expect(json['items'][0]['quantity'], 4.0);
    });

    test('should copyWith updated entity values and map correctly', () {
      final entity = ServiceOrder(
        id: 'os_11',
        deviceId: 'dev_11',
        plate: 'AAA0A00',
        createdAt: '2026-07-09T12:00:00Z',
        updatedAt: '2026-07-09T12:00:00Z',
        syncStatus: 'pending',
      );

      final updated = entity.copyWith(status: 'FINALIZADA', syncStatus: 'synced');
      final model = ServiceOrderModel.fromEntity(updated);

      expect(model.id, 'os_11');
      expect(model.status, 'FINALIZADA');
      expect(model.syncStatus, 'synced');
    });
  });
}
