import '../entities/service_order.dart';

abstract class ServiceOrderRepository {
  Future<void> saveServiceOrderOffline(ServiceOrder os);
  Future<List<ServiceOrder>> listLocalServiceOrders({String? status, String? plate});
  Future<ServiceOrder?> getLocalServiceOrderById(String id);
  Future<void> syncServiceOrders();
  Future<void> updateStatus(String id, String status);
  Future<void> addCustomerSignature(String osId, String signaturePath);
}
