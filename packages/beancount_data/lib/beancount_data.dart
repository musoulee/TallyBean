import 'package:beancount_bridge/beancount_bridge.dart';
import 'package:beancount_domain/beancount_domain.dart';
import 'package:ledger_io/ledger_io.dart';

export 'src/datasources/mock_beancount_datasource.dart'
    show MockBeancountDatasource;
export 'src/repositories/demo_beancount_repository.dart';
export 'src/repositories/beancount_repository_impl.dart';

import 'src/datasources/mock_beancount_datasource.dart';
import 'src/repositories/demo_beancount_repository.dart';
import 'src/repositories/beancount_repository_impl.dart';

BeancountRepository createDemoBeancountRepository() {
  return DemoBeancountRepository(
    datasource: const MockBeancountDatasource(),
    ledgerIo: const MemoryLedgerIoFacade(),
  );
}

BeancountRepository createLocalBeancountRepository() {
  return BeancountRepositoryImpl(
    ledgerIo: LocalLedgerIoFacade(),
    bridge: RustBeancountBridgeFacade(),
  );
}
