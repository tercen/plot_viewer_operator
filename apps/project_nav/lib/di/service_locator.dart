import 'package:get_it/get_it.dart';
import 'package:sci_tercen_client/sci_client_service_factory.dart'
    show ServiceFactory;

import '../domain/services/data_service.dart';
import '../implementations/services/tercen_data_service.dart';

final GetIt serviceLocator = GetIt.instance;

/// Register services. Called once from main() after receiving init-context.
void setupServiceLocator({
  required ServiceFactory tercenFactory,
  required String teamId,
}) {
  if (serviceLocator.isRegistered<DataService>()) return;

  serviceLocator.registerSingleton<ServiceFactory>(tercenFactory);
  serviceLocator.registerLazySingleton<DataService>(
    () => TercenDataService(
      tercenFactory,
      teamId: teamId,
    ),
  );
}
