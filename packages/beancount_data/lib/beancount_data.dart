import 'package:beancount_bridge/beancount_bridge.dart';
import 'package:beancount_domain/beancount_domain.dart';
import 'package:workspace_io/workspace_io.dart';

export 'src/datasources/mock_beancount_datasource.dart'
    show MockBeancountDatasource;
export 'src/repositories/beancount_repository_impl.dart';

import 'src/datasources/mock_beancount_datasource.dart';
import 'src/repositories/beancount_repository_impl.dart';

BeancountRepository createDemoBeancountRepository() {
  return BeancountRepositoryImpl(
    workspaceIo: const MemoryWorkspaceIoFacade(),
    bridge: const StubBeancountBridgeFacade(),
    datasource: const MockBeancountDatasource(),
  );
}
