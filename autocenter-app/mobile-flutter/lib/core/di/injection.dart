import 'package:get_it/get_it.dart';
import '../database/database_helper.dart';
import '../network/api_client.dart';
import '../network/auth/auth_token_manager.dart';
import '../../features/vehicle/data/datasources/vehicle_local_datasource.dart';
import '../../features/vehicle/data/datasources/vehicle_remote_datasource.dart';
import '../../features/vehicle/data/repositories/vehicle_repository_impl.dart';
import '../../features/vehicle/domain/repositories/vehicle_repository.dart';
import '../../features/customer/data/datasources/customer_local_data_source.dart';
import '../../features/customer/data/datasources/customer_remote_data_source.dart';
import '../../features/customer/data/repositories/customer_repository_impl.dart';
import '../../features/service_order/data/datasources/service_order_local_datasource.dart';
import '../../features/service_order/data/datasources/service_order_remote_datasource.dart';
import '../../features/service_order/data/repositories/service_order_repository_impl.dart';
import '../../features/service_order/domain/repositories/service_order_repository.dart';
import '../../features/auth/data/datasources/sellers_remote_datasource.dart';
import '../../features/auth/data/repositories/sellers_repository_impl.dart';
import '../../features/auth/domain/repositories/sellers_repository.dart';

final getIt = GetIt.instance;

void setupDependencies() {
  getIt.registerLazySingleton<AuthTokenManager>(() => AuthTokenManager());
  getIt.registerLazySingleton<ApiClient>(() => ApiClient());

  getIt.registerLazySingleton<DatabaseHelper>(() => DatabaseHelper.instance);

  // Sellers / Auth Feature
  getIt.registerLazySingleton<SellersRemoteDataSource>(() => SellersRemoteDataSource());
  getIt.registerLazySingleton<SellersRepository>(() => SellersRepositoryImpl(
        remoteDataSource: getIt<SellersRemoteDataSource>(),
        dbHelper: getIt<DatabaseHelper>(),
      ));

  // Vehicle Feature
  getIt.registerLazySingleton<VehicleLocalDataSource>(() => VehicleLocalDataSourceImpl(dbHelper: getIt<DatabaseHelper>()));
  getIt.registerLazySingleton<VehicleRemoteDataSource>(() => VehicleRemoteDataSourceImpl(apiClient: getIt<ApiClient>()));
  getIt.registerLazySingleton<VehicleRepository>(() => VehicleRepositoryImpl(
        localDataSource: getIt<VehicleLocalDataSource>(),
        remoteDataSource: getIt<VehicleRemoteDataSource>(),
      ));

  // Customer Feature
  getIt.registerLazySingleton<CustomerLocalDataSource>(() => CustomerLocalDataSource());
  getIt.registerLazySingleton<CustomerRemoteDataSource>(() => CustomerRemoteDataSource());
  getIt.registerLazySingleton<CustomerRepositoryImpl>(() => CustomerRepositoryImpl(
        getIt<CustomerLocalDataSource>(),
        getIt<CustomerRemoteDataSource>(),
      ));

  // Service Order Feature
  getIt.registerLazySingleton<ServiceOrderLocalDataSource>(() => ServiceOrderLocalDataSource());
  getIt.registerLazySingleton<ServiceOrderRemoteDataSource>(() => ServiceOrderRemoteDataSource());
  getIt.registerLazySingleton<ServiceOrderRepository>(() => ServiceOrderRepositoryImpl(
        getIt<ServiceOrderLocalDataSource>(),
        getIt<ServiceOrderRemoteDataSource>(),
      ));
}
