import 'package:beancount_bridge/beancount_bridge.dart';
import 'package:beancount_data/beancount_data.dart';
import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workspace_io/workspace_io.dart';

void main() {
  test(
    'loadCurrentWorkspace returns null when no active workspace is stored',
    () async {
      final repository = BeancountRepositoryImpl(
        workspaceIo: _FakeWorkspaceIoFacade(),
        bridge: _FakeBridgeFacade(),
      );

      expect(await repository.loadCurrentWorkspace(), isNull);
    },
  );

  test(
    'validation uses the opened workspace handle instead of reparsing fixture data',
    () async {
      final bridge = _FakeBridgeFacade();
      final repository = BeancountRepositoryImpl(
        workspaceIo: _FakeWorkspaceIoFacade(
          current: CurrentWorkspaceRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/workspaces/household',
            entryFilePath: '/app/workspaces/household/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
        ),
        bridge: bridge,
      );

      final workspace = await repository.loadCurrentWorkspace();
      final issues = await repository.loadValidationIssues();

      expect(workspace, isNotNull);
      expect(workspace?.id, 'parsed-ledger');
      expect(issues, hasLength(1));
      expect(bridge.openedRoots, ['/app/workspaces/household']);
      expect(bridge.diagnosticHandles, [41]);
    },
  );

  test('read models come from session-backed bridge queries', () async {
    final repository = BeancountRepositoryImpl(
      workspaceIo: _FakeWorkspaceIoFacade(
        current: CurrentWorkspaceRecord(
          id: 'recent-id',
          name: 'Household',
          path: '/app/workspaces/household',
          entryFilePath: '/app/workspaces/household/main.beancount',
          lastImportedAt: DateTime(2026, 4, 15, 10, 0),
        ),
      ),
      bridge: _FakeBridgeFacade(),
    );

    final overview = await repository.loadOverviewSnapshot();
    final journal = await repository.loadJournalEntries();
    final accountTree = await repository.loadAccountTree();
    final reports = await repository.loadReportSummaries();

    expect(overview.netWorth, 'CNY 1,000');
    expect(overview.weekTrend.balance, 1000);
    expect(journal.single.title, 'Salary');
    expect(accountTree.single.name, 'Assets');
    expect(reports[ReportCategory.incomeExpense]?.single.lines, <String>[
      '本周收入 ¥ 1,000',
    ]);
  });

  test(
    'loadCurrentWorkspaceFiles returns entry file first and remaining files sorted by relative path',
    () async {
      final bridge = _FakeBridgeFacade(
        documentSummaries: const <BridgeDocumentSummaryDto>[
          BridgeDocumentSummaryDto(
            documentId: 'z/txn.bean',
            fileName: 'txn.bean',
            relativePath: 'z/txn.bean',
            sizeBytes: 3,
            isEntry: false,
          ),
          BridgeDocumentSummaryDto(
            documentId: 'main.beancount',
            fileName: 'main.beancount',
            relativePath: 'main.beancount',
            sizeBytes: 4,
            isEntry: true,
          ),
          BridgeDocumentSummaryDto(
            documentId: 'a/assets.beancount',
            fileName: 'assets.beancount',
            relativePath: 'a/assets.beancount',
            sizeBytes: 6,
            isEntry: false,
          ),
        ],
        documentsById: const <String, BridgeDocumentDto>{
          'z/txn.bean': BridgeDocumentDto(
            documentId: 'z/txn.bean',
            fileName: 'txn.bean',
            relativePath: 'z/txn.bean',
            content: 'txn',
            sizeBytes: 3,
            isEntry: false,
          ),
          'main.beancount': BridgeDocumentDto(
            documentId: 'main.beancount',
            fileName: 'main.beancount',
            relativePath: 'main.beancount',
            content: 'main',
            sizeBytes: 4,
            isEntry: true,
          ),
          'a/assets.beancount': BridgeDocumentDto(
            documentId: 'a/assets.beancount',
            fileName: 'assets.beancount',
            relativePath: 'a/assets.beancount',
            content: 'assets',
            sizeBytes: 6,
            isEntry: false,
          ),
        },
      );
      final repository = BeancountRepositoryImpl(
        workspaceIo: _FakeWorkspaceIoFacade(
          current: CurrentWorkspaceRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/workspaces/household',
            entryFilePath: '/app/workspaces/household/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
          workspaceFiles: const <WorkspaceIoFileRecord>[
            WorkspaceIoFileRecord(
              filePath: '/app/workspaces/household/z/txn.bean',
              relativePath: 'z/txn.bean',
              content: 'txn',
              sizeBytes: 3,
            ),
            WorkspaceIoFileRecord(
              filePath: '/app/workspaces/household/main.beancount',
              relativePath: 'main.beancount',
              content: 'main',
              sizeBytes: 4,
            ),
            WorkspaceIoFileRecord(
              filePath: '/app/workspaces/household/a/assets.beancount',
              relativePath: 'a/assets.beancount',
              content: 'assets',
              sizeBytes: 6,
            ),
          ],
        ),
        bridge: bridge,
      );

      final files = await repository.loadCurrentWorkspaceFiles();

      expect(files.map((item) => item.relativePath), <String>[
        'main.beancount',
        'a/assets.beancount',
        'z/txn.bean',
      ]);
      expect(files.first.fileName, 'main.beancount');
      expect(files.first.sizeBytes, 4);
      expect(files.first.content, 'main');
    },
  );

  test(
    'loadCurrentWorkspaceFiles still pins entry file first when file records use backslash separators',
    () async {
      final bridge = _FakeBridgeFacade(
        documentSummaries: const <BridgeDocumentSummaryDto>[
          BridgeDocumentSummaryDto(
            documentId: r'journal\main.beancount',
            fileName: 'main.beancount',
            relativePath: r'journal\main.beancount',
            sizeBytes: 4,
            isEntry: true,
          ),
          BridgeDocumentSummaryDto(
            documentId: 'a/assets.beancount',
            fileName: 'assets.beancount',
            relativePath: 'a/assets.beancount',
            sizeBytes: 6,
            isEntry: false,
          ),
        ],
        documentsById: const <String, BridgeDocumentDto>{
          r'journal\main.beancount': BridgeDocumentDto(
            documentId: r'journal\main.beancount',
            fileName: 'main.beancount',
            relativePath: r'journal\main.beancount',
            content: 'main',
            sizeBytes: 4,
            isEntry: true,
          ),
          'a/assets.beancount': BridgeDocumentDto(
            documentId: 'a/assets.beancount',
            fileName: 'assets.beancount',
            relativePath: 'a/assets.beancount',
            content: 'assets',
            sizeBytes: 6,
            isEntry: false,
          ),
        },
      );
      final repository = BeancountRepositoryImpl(
        workspaceIo: _FakeWorkspaceIoFacade(
          current: CurrentWorkspaceRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/workspaces/household',
            entryFilePath: '/app/workspaces/household/journal/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
          workspaceFiles: const <WorkspaceIoFileRecord>[
            WorkspaceIoFileRecord(
              filePath: '/app/workspaces/household/journal/main.beancount',
              relativePath: r'journal\main.beancount',
              content: 'main',
              sizeBytes: 4,
            ),
            WorkspaceIoFileRecord(
              filePath: '/app/workspaces/household/a/assets.beancount',
              relativePath: 'a/assets.beancount',
              content: 'assets',
              sizeBytes: 6,
            ),
          ],
        ),
        bridge: bridge,
      );

      final files = await repository.loadCurrentWorkspaceFiles();

      expect(files.first.relativePath, r'journal\main.beancount');
      expect(files.first.fileName, 'main.beancount');
    },
  );

  test(
    'loadCurrentWorkspaceFiles keeps filesystem ledger files that are not in the bridge document graph',
    () async {
      final repository = BeancountRepositoryImpl(
        workspaceIo: _FakeWorkspaceIoFacade(
          current: CurrentWorkspaceRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/workspaces/household',
            entryFilePath: '/app/workspaces/household/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
          workspaceFiles: const <WorkspaceIoFileRecord>[
            WorkspaceIoFileRecord(
              filePath: '/app/workspaces/household/main.beancount',
              relativePath: 'main.beancount',
              content: 'main',
              sizeBytes: 4,
            ),
            WorkspaceIoFileRecord(
              filePath: '/app/workspaces/household/drafts/unincluded.bean',
              relativePath: 'drafts/unincluded.bean',
              content: 'draft',
              sizeBytes: 5,
            ),
          ],
        ),
        bridge: _FakeBridgeFacade(
          documentSummaries: const <BridgeDocumentSummaryDto>[
            BridgeDocumentSummaryDto(
              documentId: 'main.beancount',
              fileName: 'main.beancount',
              relativePath: 'main.beancount',
              sizeBytes: 4,
              isEntry: true,
            ),
          ],
          documentsById: const <String, BridgeDocumentDto>{
            'main.beancount': BridgeDocumentDto(
              documentId: 'main.beancount',
              fileName: 'main.beancount',
              relativePath: 'main.beancount',
              content: 'main',
              sizeBytes: 4,
              isEntry: true,
            ),
          },
        ),
      );

      final files = await repository.loadCurrentWorkspaceFiles();

      expect(files.map((item) => item.relativePath), <String>[
        'main.beancount',
        'drafts/unincluded.bean',
      ]);
      expect(files.last.content, 'draft');
    },
  );

  test(
    'loadCurrentWorkspaceFiles reloads fresh file contents from workspace storage',
    () async {
      final repository = BeancountRepositoryImpl(
        workspaceIo: _FakeWorkspaceIoFacade(
          current: CurrentWorkspaceRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/workspaces/household',
            entryFilePath: '/app/workspaces/household/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
          workspaceFileSnapshots: <List<WorkspaceIoFileRecord>>[
            const <WorkspaceIoFileRecord>[
              WorkspaceIoFileRecord(
                filePath: '/app/workspaces/household/main.beancount',
                relativePath: 'main.beancount',
                content: 'v1',
                sizeBytes: 2,
              ),
            ],
            const <WorkspaceIoFileRecord>[
              WorkspaceIoFileRecord(
                filePath: '/app/workspaces/household/main.beancount',
                relativePath: 'main.beancount',
                content: 'v2',
                sizeBytes: 2,
              ),
            ],
          ],
        ),
        bridge: _FakeBridgeFacade(
          documentsById: const <String, BridgeDocumentDto>{
            'main.beancount': BridgeDocumentDto(
              documentId: 'main.beancount',
              fileName: 'main.beancount',
              relativePath: 'main.beancount',
              content: 'stale-from-session',
              sizeBytes: 18,
              isEntry: true,
            ),
          },
        ),
      );

      final firstRead = await repository.loadCurrentWorkspaceFiles();
      final secondRead = await repository.loadCurrentWorkspaceFiles();

      expect(firstRead.single.content, 'v1');
      expect(secondRead.single.content, 'v2');
    },
  );
}

class _FakeWorkspaceIoFacade implements WorkspaceIoFacade {
  _FakeWorkspaceIoFacade({
    this.current,
    this.workspaceFiles = const <WorkspaceIoFileRecord>[],
    List<List<WorkspaceIoFileRecord>>? workspaceFileSnapshots,
  }) : _workspaceFileSnapshots = workspaceFileSnapshots;

  final CurrentWorkspaceRecord? current;
  final List<WorkspaceIoFileRecord> workspaceFiles;
  final List<List<WorkspaceIoFileRecord>>? _workspaceFileSnapshots;
  int _workspaceFileLoadCount = 0;

  @override
  Future<ImportedWorkspaceSummary> createDefaultWorkspace() {
    throw UnimplementedError();
  }

  @override
  Future<void> exportWorkspace(
    String workspaceId,
    String destinationPath,
  ) async {}

  @override
  Future<ImportedWorkspaceSummary> importWorkspace(String sourcePath) {
    throw UnimplementedError();
  }

  @override
  Future<String> loadFileContent(String filePath) {
    throw UnimplementedError();
  }

  @override
  Future<CurrentWorkspaceRecord?> loadCurrentWorkspace() async => current;

  @override
  Future<List<RecentWorkspaceRecord>> loadRecentWorkspaces() async => const [];

  @override
  Future<List<WorkspaceIoFileRecord>> loadWorkspaceFiles(
    String workspaceRootPath,
  ) async {
    if (_workspaceFileSnapshots != null) {
      final index = _workspaceFileLoadCount < _workspaceFileSnapshots.length
          ? _workspaceFileLoadCount
          : _workspaceFileSnapshots.length - 1;
      _workspaceFileLoadCount += 1;
      return _workspaceFileSnapshots[index];
    }
    return workspaceFiles;
  }

  @override
  Future<void> renameWorkspace(String workspaceId, String newName) async {}

  @override
  Future<void> setCurrentWorkspace(String workspaceId) async {}
}

class _FakeBridgeFacade extends StubBeancountBridgeFacade {
  _FakeBridgeFacade({
    List<BridgeDocumentSummaryDto>? documentSummaries,
    Map<String, BridgeDocumentDto>? documentsById,
  }) : _documentSummaries = documentSummaries ?? _defaultDocumentSummaries,
       _documentsById = documentsById ?? _defaultDocumentsById;

  static const List<BridgeDocumentSummaryDto> _defaultDocumentSummaries =
      <BridgeDocumentSummaryDto>[
        BridgeDocumentSummaryDto(
          documentId: 'main.beancount',
          fileName: 'main.beancount',
          relativePath: 'main.beancount',
          sizeBytes: 4,
          isEntry: true,
        ),
      ];

  static const Map<String, BridgeDocumentDto> _defaultDocumentsById =
      <String, BridgeDocumentDto>{
        'main.beancount': BridgeDocumentDto(
          documentId: 'main.beancount',
          fileName: 'main.beancount',
          relativePath: 'main.beancount',
          content: 'main',
          sizeBytes: 4,
          isEntry: true,
        ),
      };

  final List<String> openedRoots = <String>[];
  final List<int> diagnosticHandles = <int>[];
  final List<BridgeDocumentSummaryDto> _documentSummaries;
  final Map<String, BridgeDocumentDto> _documentsById;

  @override
  Future<void> closeWorkspace(int handle) async {}

  @override
  Future<BridgeAccountTreeDto> getAccountTree(int handle) async {
    return const BridgeAccountTreeDto(
      nodes: <BridgeAccountNodeDto>[
        BridgeAccountNodeDto(
          name: 'Assets',
          subtitle: '活跃',
          balance: 'CNY 1,000',
          children: <BridgeAccountNodeDto>[],
        ),
      ],
    );
  }

  @override
  Future<BridgeDocumentDto> getDocument(int handle, String documentId) async {
    final document = _documentsById[documentId];
    if (document == null) {
      throw StateError('Unknown document: $documentId');
    }
    return document;
  }

  @override
  Future<List<BridgeJournalEntryDto>> getJournalEntries(int handle) async {
    return <BridgeJournalEntryDto>[
      BridgeJournalEntryDto(
        date: DateTime(2026, 4, 2),
        type: BridgeJournalEntryType.transaction,
        title: 'Salary',
        primaryAccount: 'Assets:Cash',
        secondaryAccount: 'Income:Salary',
      ),
    ];
  }

  @override
  Future<BridgeOverviewDto> getOverview(int handle) async {
    return const BridgeOverviewDto(
      netWorth: 'CNY 1,000',
      totalAssets: 'CNY 1,000',
      totalLiabilities: '--',
      changeDescription: '较上月 + CNY 1,000',
      weekTrend: BridgeTrendSummaryDto(
        chartLabel: '本周收支趋势',
        income: 1000,
        expense: 0,
        balance: 1000,
      ),
      monthTrend: BridgeTrendSummaryDto(
        chartLabel: '本月收支趋势',
        income: 1000,
        expense: 0,
        balance: 1000,
      ),
    );
  }

  @override
  Future<List<BridgeDocumentSummaryDto>> listDocuments(int handle) async {
    return _documentSummaries;
  }

  @override
  Future<List<BridgeValidationIssueDto>> listDiagnostics(int handle) async {
    diagnosticHandles.add(handle);
    return const <BridgeValidationIssueDto>[
      BridgeValidationIssueDto(
        message: 'blocking issue',
        location: 'main.beancount:1',
        blocking: true,
      ),
    ];
  }

  @override
  Future<BridgeWorkspaceSessionDto> openWorkspace(
    String rootPath,
    String entryFilePath,
  ) async {
    openedRoots.add(rootPath);
    return BridgeWorkspaceSessionDto(
      handle: 41,
      summary: const BridgeWorkspaceSummaryDto(
        workspaceId: 'parsed-ledger',
        workspaceName: 'Household',
        loadedFileCount: 2,
        openAccountCount: 2,
        closedAccountCount: 0,
        netWorth: 'CNY 1,000',
        totalAssets: 'CNY 1,000',
        totalLiabilities: '--',
        changeDescription: '较上月 + CNY 1,000',
        weekTrend: BridgeTrendSummaryDto(
          chartLabel: '本周收支趋势',
          income: 1000,
          expense: 0,
          balance: 1000,
        ),
        monthTrend: BridgeTrendSummaryDto(
          chartLabel: '本月收支趋势',
          income: 1000,
          expense: 0,
          balance: 1000,
        ),
      ),
      diagnostics: const <BridgeValidationIssueDto>[],
    );
  }

  @override
  Future<BridgeRefreshResultDto> refreshWorkspace(int handle) async {
    return BridgeRefreshResultDto(
      summary: const BridgeWorkspaceSummaryDto(
        workspaceId: 'parsed-ledger',
        workspaceName: 'Household',
        loadedFileCount: 2,
        openAccountCount: 2,
        closedAccountCount: 0,
        netWorth: 'CNY 1,000',
        totalAssets: 'CNY 1,000',
        totalLiabilities: '--',
        changeDescription: '较上月 + CNY 1,000',
        weekTrend: BridgeTrendSummaryDto(
          chartLabel: '本周收支趋势',
          income: 1000,
          expense: 0,
          balance: 1000,
        ),
        monthTrend: BridgeTrendSummaryDto(
          chartLabel: '本月收支趋势',
          income: 1000,
          expense: 0,
          balance: 1000,
        ),
      ),
      diagnosticsCount: 0,
    );
  }

  @override
  Future<List<BridgeReportResultDto>> getReportSnapshot(int handle) async {
    return const <BridgeReportResultDto>[
      BridgeReportResultDto(
        key: 'income_expense',
        lines: <String>['本周收入 ¥ 1,000'],
      ),
    ];
  }
}
