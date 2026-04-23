import 'package:beancount_bridge/beancount_bridge.dart';
import 'package:beancount_data/beancount_data.dart';
import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_io/ledger_io.dart';

void main() {
  test(
    'loadCurrentLedger returns null when no active ledger is stored',
    () async {
      final repository = BeancountRepositoryImpl(
        ledgerIo: _FakeLedgerIoFacade(),
        bridge: _FakeBridgeFacade(),
      );

      expect(await repository.loadCurrentLedger(), isNull);
    },
  );

  test(
    'validation uses the opened ledger handle instead of reparsing fixture data',
    () async {
      final bridge = _FakeBridgeFacade();
      final repository = BeancountRepositoryImpl(
        ledgerIo: _FakeLedgerIoFacade(
          current: CurrentLedgerRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/ledgers/household',
            entryFilePath: '/app/ledgers/household/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
        ),
        bridge: bridge,
      );

      final ledger = await repository.loadCurrentLedger();
      final issues = await repository.loadValidationIssues();

      expect(ledger, isNotNull);
      expect(ledger?.id, 'recent-id');
      expect(issues, hasLength(1));
      expect(bridge.openedRoots, ['/app/ledgers/household']);
      expect(bridge.diagnosticHandles, [41]);
    },
  );

  test(
    'loadCurrentLedger keeps the stored ledger id for follow-up actions',
    () async {
      final repository = BeancountRepositoryImpl(
        ledgerIo: _FakeLedgerIoFacade(
          current: CurrentLedgerRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/ledgers/household',
            entryFilePath: '/app/ledgers/household/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
        ),
        bridge: _FakeBridgeFacade(),
      );

      final ledger = await repository.loadCurrentLedger();

      expect(ledger?.id, 'recent-id');
    },
  );

  test('loadCurrentLedger uses the Rust ledger title when available', () async {
    final ledgerIo = _FakeLedgerIoFacade(
      current: CurrentLedgerRecord(
        id: 'recent-id',
        name: 'Folder Derived Name',
        path: '/app/ledgers/household',
        entryFilePath: '/app/ledgers/household/main.beancount',
        lastImportedAt: DateTime(2026, 4, 15, 10, 0),
      ),
    );
    final repository = BeancountRepositoryImpl(
      ledgerIo: ledgerIo,
      bridge: _FakeBridgeFacade(ledgerName: 'Bean Option Title'),
    );

    final ledger = await repository.loadCurrentLedger();

    expect(ledger?.name, 'Bean Option Title');
    expect(ledgerIo.syncLedgerNameCalls, hasLength(1));
    expect(ledgerIo.syncLedgerNameCalls.single.ledgerId, 'recent-id');
    expect(ledgerIo.syncLedgerNameCalls.single.newName, 'Bean Option Title');
  });

  test(
    'loadCurrentLedger rewrites stored ledger metadata when Rust title differs',
    () async {
      final ledgerIo = _FakeLedgerIoFacade(
        current: CurrentLedgerRecord(
          id: 'recent-id',
          name: 'Folder Derived Name',
          path: '/app/ledgers/household',
          entryFilePath: '/app/ledgers/household/main.beancount',
          lastImportedAt: DateTime(2026, 4, 15, 10, 0),
        ),
      );
      final repository = BeancountRepositoryImpl(
        ledgerIo: ledgerIo,
        bridge: _FakeBridgeFacade(ledgerName: 'Bean Option Title'),
      );

      await repository.loadCurrentLedger();

      expect(ledgerIo.syncLedgerNameCalls, hasLength(1));
      expect(ledgerIo.syncLedgerNameCalls.single.ledgerId, 'recent-id');
      expect(ledgerIo.syncLedgerNameCalls.single.newName, 'Bean Option Title');
    },
  );

  test(
    'loadCurrentLedger falls back to ledger metadata name when Rust title is blank',
    () async {
      final repository = BeancountRepositoryImpl(
        ledgerIo: _FakeLedgerIoFacade(
          current: CurrentLedgerRecord(
            id: 'recent-id',
            name: 'Folder Derived Name',
            path: '/app/ledgers/household',
            entryFilePath: '/app/ledgers/household/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
        ),
        bridge: _FakeBridgeFacade(ledgerName: '   '),
      );

      final ledger = await repository.loadCurrentLedger();

      expect(ledger?.name, 'Folder Derived Name');
    },
  );

  test(
    'importLedger syncs ledger name from Rust summary title to ledger metadata',
    () async {
      final ledgerIo = _FakeLedgerIoFacade(
        importedSummary: ImportedLedgerSummary(
          ledgerId: 'recent-id',
          name: 'Folder Derived Name',
          path: '/app/ledgers/household',
          entryFilePath: '/app/ledgers/household/main.beancount',
          fileCount: 1,
          lastImportedAt: DateTime(2026, 4, 15, 10, 0),
        ),
      );
      final bridge = _FakeBridgeFacade(ledgerName: 'Bean Option Title');
      final repository = BeancountRepositoryImpl(
        ledgerIo: ledgerIo,
        bridge: bridge,
      );

      await repository.importLedger('/tmp/folder_derived_name/main.beancount');

      expect(ledgerIo.importedSourcePaths, <String>[
        '/tmp/folder_derived_name/main.beancount',
      ]);
      expect(ledgerIo.syncLedgerNameCalls, hasLength(1));
      expect(ledgerIo.syncLedgerNameCalls.single.ledgerId, 'recent-id');
      expect(ledgerIo.syncLedgerNameCalls.single.newName, 'Bean Option Title');
      expect(bridge.openedRoots, <String>['/app/ledgers/household']);
      expect(bridge.closedHandles, <int>[41]);
    },
  );

  test(
    'importLedger re-syncs the ledger name from Rust title during reimport refresh',
    () async {
      final ledgerIo = _FakeLedgerIoFacade(
        importedSummary: ImportedLedgerSummary(
          ledgerId: 'recent-id',
          name: 'My Custom Ledger',
          path: '/app/ledgers/household',
          entryFilePath: '/app/ledgers/household/main.beancount',
          fileCount: 1,
          lastImportedAt: DateTime(2026, 4, 15, 10, 0),
        ),
      );
      final bridge = _FakeBridgeFacade(ledgerName: 'Bean Option Title');
      final repository = BeancountRepositoryImpl(
        ledgerIo: ledgerIo,
        bridge: bridge,
      );

      await repository.importLedger('/tmp/folder_derived_name/main.beancount');

      expect(ledgerIo.importedSourcePaths, <String>[
        '/tmp/folder_derived_name/main.beancount',
      ]);
      expect(ledgerIo.syncLedgerNameCalls, hasLength(1));
      expect(ledgerIo.syncLedgerNameCalls.single.ledgerId, 'recent-id');
      expect(ledgerIo.syncLedgerNameCalls.single.newName, 'Bean Option Title');
      expect(bridge.openedRoots, <String>['/app/ledgers/household']);
      expect(bridge.closedHandles, <int>[41]);
    },
  );

  test(
    'importLedger closes the active session before reimporting in place',
    () async {
      final events = <String>[];
      final ledgerIo = _FakeLedgerIoFacade(
        current: CurrentLedgerRecord(
          id: 'recent-id',
          name: 'Bean Option Title',
          path: '/app/ledgers/household',
          entryFilePath: '/app/ledgers/household/main.beancount',
          lastImportedAt: DateTime(2026, 4, 15, 10, 0),
        ),
        importedSummary: ImportedLedgerSummary(
          ledgerId: 'recent-id',
          name: 'Bean Option Title',
          path: '/app/ledgers/household',
          entryFilePath: '/app/ledgers/household/main.beancount',
          fileCount: 1,
          lastImportedAt: DateTime(2026, 4, 15, 10, 0),
        ),
        events: events,
      );
      final bridge = _FakeBridgeFacade(
        ledgerName: 'Bean Option Title',
        events: events,
      );
      final repository = BeancountRepositoryImpl(
        ledgerIo: ledgerIo,
        bridge: bridge,
      );

      await repository.loadCurrentLedger();
      events.clear();

      await repository.importLedger('/tmp/folder_derived_name/main.beancount');

      expect(
        events,
        containsAllInOrder(<String>[
          'close:41',
          'import:/tmp/folder_derived_name/main.beancount',
        ]),
      );
    },
  );

  test(
    'deleteLedger delegates to ledger IO and disposes active session',
    () async {
      final ledgerIo = _FakeLedgerIoFacade(
        current: CurrentLedgerRecord(
          id: 'recent-id',
          name: 'Household',
          path: '/app/ledgers/household',
          entryFilePath: '/app/ledgers/household/main.beancount',
          lastImportedAt: DateTime(2026, 4, 15, 10, 0),
        ),
      );
      final bridge = _FakeBridgeFacade();
      final repository = BeancountRepositoryImpl(
        ledgerIo: ledgerIo,
        bridge: bridge,
      );

      await repository.loadCurrentLedger();
      await repository.deleteLedger('recent-id');

      expect(ledgerIo.deletedLedgerIds, <String>['recent-id']);
      expect(bridge.closedHandles, <int>[41]);
    },
  );

  test(
    'deleteLedger closes the active session before deleting current ledger files',
    () async {
      final events = <String>[];
      final ledgerIo = _FakeLedgerIoFacade(
        current: CurrentLedgerRecord(
          id: 'recent-id',
          name: 'Bean Option Title',
          path: '/app/ledgers/household',
          entryFilePath: '/app/ledgers/household/main.beancount',
          lastImportedAt: DateTime(2026, 4, 15, 10, 0),
        ),
        events: events,
      );
      final bridge = _FakeBridgeFacade(
        ledgerName: 'Bean Option Title',
        events: events,
      );
      final repository = BeancountRepositoryImpl(
        ledgerIo: ledgerIo,
        bridge: bridge,
      );

      await repository.loadCurrentLedger();
      events.clear();

      await repository.deleteLedger('recent-id');

      expect(
        events,
        containsAllInOrder(<String>['close:41', 'delete:recent-id']),
      );
    },
  );

  test(
    'loadRecentLedgers prefers the entry file title over other ledger files',
    () async {
      final ledgerIo = _FakeLedgerIoFacade(
        recentLedgers: <RecentLedgerRecord>[
          RecentLedgerRecord(
            id: 'archived-id',
            name: 'Folder Derived Name',
            path: '/app/ledgers/archived',
            lastOpenedAt: DateTime(2026, 4, 18, 10, 0),
            entryFilePath: '/app/ledgers/archived/journal/main.beancount',
          ),
        ],
        ledgerFiles: const <LedgerIoFileRecord>[
          LedgerIoFileRecord(
            filePath: '/app/ledgers/archived/00-shared.beancount',
            relativePath: '00-shared.beancount',
            content: 'option "title" "Wrong Title"\n',
            sizeBytes: 28,
          ),
          LedgerIoFileRecord(
            filePath: '/app/ledgers/archived/journal/main.beancount',
            relativePath: 'journal/main.beancount',
            content: 'option "title" "Bean Option Title"\n',
            sizeBytes: 34,
          ),
        ],
      );
      final repository = BeancountRepositoryImpl(
        ledgerIo: ledgerIo,
        bridge: _FakeBridgeFacade(),
      );

      final recent = await repository.loadRecentLedgers();

      expect(recent.single.name, 'Bean Option Title');
      expect(ledgerIo.syncLedgerNameCalls, hasLength(1));
      expect(ledgerIo.syncLedgerNameCalls.single.ledgerId, 'archived-id');
      expect(ledgerIo.syncLedgerNameCalls.single.newName, 'Bean Option Title');
    },
  );

  test('read models come from session-backed bridge queries', () async {
    final repository = BeancountRepositoryImpl(
      ledgerIo: _FakeLedgerIoFacade(
        current: CurrentLedgerRecord(
          id: 'recent-id',
          name: 'Household',
          path: '/app/ledgers/household',
          entryFilePath: '/app/ledgers/household/main.beancount',
          lastImportedAt: DateTime(2026, 4, 15, 10, 0),
        ),
      ),
      bridge: _FakeBridgeFacade(
        diagnosticSnapshots: const <List<BridgeValidationIssueDto>>[
          <BridgeValidationIssueDto>[],
        ],
      ),
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
    'loadReportSummaries returns an empty map when the current ledger has blocking issues',
    () async {
      final repository = BeancountRepositoryImpl(
        ledgerIo: _FakeLedgerIoFacade(
          current: CurrentLedgerRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/ledgers/household',
            entryFilePath: '/app/ledgers/household/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
        ),
        bridge: _FakeBridgeFacade(
          sessionDiagnostics: const <BridgeValidationIssueDto>[
            BridgeValidationIssueDto(
              message: 'blocking issue',
              location: 'main.beancount:1',
              blocking: true,
            ),
          ],
        ),
      );

      final reports = await repository.loadReportSummaries();

      expect(reports, isEmpty);
    },
  );

  test(
    'loadReportSummaries refreshes cached diagnostics before suppressing stale reports',
    () async {
      final bridge = _FakeBridgeFacade(
        sessionDiagnostics: const <BridgeValidationIssueDto>[],
        diagnosticSnapshots: const <List<BridgeValidationIssueDto>>[
          <BridgeValidationIssueDto>[
            BridgeValidationIssueDto(
              message: 'blocking issue',
              location: 'main.beancount:1',
              blocking: true,
            ),
          ],
        ],
      );
      final repository = BeancountRepositoryImpl(
        ledgerIo: _FakeLedgerIoFacade(
          current: CurrentLedgerRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/ledgers/household',
            entryFilePath: '/app/ledgers/household/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
        ),
        bridge: bridge,
      );

      final ledger = await repository.loadCurrentLedger();
      final reports = await repository.loadReportSummaries();

      expect(ledger?.status, LedgerStatus.ready);
      expect(reports, isEmpty);
      expect(bridge.diagnosticHandles, <int>[41]);
    },
  );

  test(
    'loadReportSummaries refreshes cached diagnostics before returning reports again',
    () async {
      final bridge = _FakeBridgeFacade(
        sessionDiagnostics: const <BridgeValidationIssueDto>[
          BridgeValidationIssueDto(
            message: 'blocking issue',
            location: 'main.beancount:1',
            blocking: true,
          ),
        ],
        diagnosticSnapshots: const <List<BridgeValidationIssueDto>>[
          <BridgeValidationIssueDto>[],
        ],
      );
      final repository = BeancountRepositoryImpl(
        ledgerIo: _FakeLedgerIoFacade(
          current: CurrentLedgerRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/ledgers/household',
            entryFilePath: '/app/ledgers/household/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
        ),
        bridge: bridge,
      );

      final ledger = await repository.loadCurrentLedger();
      final reports = await repository.loadReportSummaries();

      expect(ledger?.status, LedgerStatus.issuesFirst);
      expect(reports[ReportCategory.incomeExpense]?.single.lines, <String>[
        '本周收入 ¥ 1,000',
      ]);
      expect(bridge.diagnosticHandles, <int>[41]);
    },
  );

  test(
    'loadCurrentLedgerFiles returns entry file first and remaining files sorted by relative path',
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
        ledgerIo: _FakeLedgerIoFacade(
          current: CurrentLedgerRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/ledgers/household',
            entryFilePath: '/app/ledgers/household/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
          ledgerFiles: const <LedgerIoFileRecord>[
            LedgerIoFileRecord(
              filePath: '/app/ledgers/household/z/txn.bean',
              relativePath: 'z/txn.bean',
              content: 'txn',
              sizeBytes: 3,
            ),
            LedgerIoFileRecord(
              filePath: '/app/ledgers/household/main.beancount',
              relativePath: 'main.beancount',
              content: 'main',
              sizeBytes: 4,
            ),
            LedgerIoFileRecord(
              filePath: '/app/ledgers/household/a/assets.beancount',
              relativePath: 'a/assets.beancount',
              content: 'assets',
              sizeBytes: 6,
            ),
          ],
        ),
        bridge: bridge,
      );

      final files = await repository.loadCurrentLedgerFiles();

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
    'loadCurrentLedgerFiles still pins entry file first when file records use backslash separators',
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
        ledgerIo: _FakeLedgerIoFacade(
          current: CurrentLedgerRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/ledgers/household',
            entryFilePath: '/app/ledgers/household/journal/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
          ledgerFiles: const <LedgerIoFileRecord>[
            LedgerIoFileRecord(
              filePath: '/app/ledgers/household/journal/main.beancount',
              relativePath: r'journal\main.beancount',
              content: 'main',
              sizeBytes: 4,
            ),
            LedgerIoFileRecord(
              filePath: '/app/ledgers/household/a/assets.beancount',
              relativePath: 'a/assets.beancount',
              content: 'assets',
              sizeBytes: 6,
            ),
          ],
        ),
        bridge: bridge,
      );

      final files = await repository.loadCurrentLedgerFiles();

      expect(files.first.relativePath, r'journal\main.beancount');
      expect(files.first.fileName, 'main.beancount');
    },
  );

  test(
    'loadCurrentLedgerFiles keeps filesystem ledger files that are not in the bridge document graph',
    () async {
      final repository = BeancountRepositoryImpl(
        ledgerIo: _FakeLedgerIoFacade(
          current: CurrentLedgerRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/ledgers/household',
            entryFilePath: '/app/ledgers/household/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
          ledgerFiles: const <LedgerIoFileRecord>[
            LedgerIoFileRecord(
              filePath: '/app/ledgers/household/main.beancount',
              relativePath: 'main.beancount',
              content: 'main',
              sizeBytes: 4,
            ),
            LedgerIoFileRecord(
              filePath: '/app/ledgers/household/drafts/unincluded.bean',
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

      final files = await repository.loadCurrentLedgerFiles();

      expect(files.map((item) => item.relativePath), <String>[
        'main.beancount',
        'drafts/unincluded.bean',
      ]);
      expect(files.last.content, 'draft');
    },
  );

  test(
    'loadCurrentLedgerFiles reloads fresh file contents from ledger storage',
    () async {
      final repository = BeancountRepositoryImpl(
        ledgerIo: _FakeLedgerIoFacade(
          current: CurrentLedgerRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/ledgers/household',
            entryFilePath: '/app/ledgers/household/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
          ledgerFileSnapshots: <List<LedgerIoFileRecord>>[
            const <LedgerIoFileRecord>[
              LedgerIoFileRecord(
                filePath: '/app/ledgers/household/main.beancount',
                relativePath: 'main.beancount',
                content: 'v1',
                sizeBytes: 2,
              ),
            ],
            const <LedgerIoFileRecord>[
              LedgerIoFileRecord(
                filePath: '/app/ledgers/household/main.beancount',
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

      final firstRead = await repository.loadCurrentLedgerFiles();
      final secondRead = await repository.loadCurrentLedgerFiles();

      expect(firstRead.single.content, 'v1');
      expect(secondRead.single.content, 'v2');
    },
  );

  test(
    'appendTransaction appends the serialized entry to the current entry file and refreshes the session',
    () async {
      final ledgerIo = _FakeLedgerIoFacade(
        current: CurrentLedgerRecord(
          id: 'recent-id',
          name: 'Household',
          path: '/app/ledgers/household',
          entryFilePath: '/app/ledgers/household/main.beancount',
          lastImportedAt: DateTime(2026, 4, 15, 10, 0),
        ),
        fileContents: <String, String>{
          '/app/ledgers/household/main.beancount':
              'option "title" "Household"\n',
        },
      );
      final bridge = _FakeBridgeFacade(
        sessionDiagnostics: const <BridgeValidationIssueDto>[],
        diagnosticSnapshots: const <List<BridgeValidationIssueDto>>[
          <BridgeValidationIssueDto>[],
        ],
      );
      final repository = BeancountRepositoryImpl(
        ledgerIo: ledgerIo,
        bridge: bridge,
      );

      await repository.appendTransaction(
        CreateTransactionInput(
          date: DateTime(2026, 4, 19),
          summary: 'Coffee',
          postings: const [
            PostingInput(
              account: 'Expenses:Food',
              amount: '18.50',
              commodity: 'CNY',
            ),
            PostingInput(account: 'Assets:Cash'),
          ],
        ),
      );

      expect(ledgerIo.writeHistory, hasLength(1));
      expect(
        ledgerIo.writeHistory.single.path,
        '/app/ledgers/household/main.beancount',
      );
      expect(
        ledgerIo.writeHistory.single.content,
        'option "title" "Household"\n\n'
        '2026-04-19 * "Coffee"\n'
        '  Expenses:Food  18.50 CNY\n'
        '  Assets:Cash\n',
      );
      expect(bridge.refreshHandles, <int>[41]);
    },
  );

  test(
    'appendTransaction serializes advanced features correctly',
    () async {
      final ledgerIo = _FakeLedgerIoFacade(
        current: CurrentLedgerRecord(
          id: 'recent-id',
          name: 'Household',
          path: '/app/ledgers/household',
          entryFilePath: '/app/ledgers/household/main.beancount',
          lastImportedAt: DateTime(2026, 4, 15, 10, 0),
        ),
        fileContents: <String, String>{
          '/app/ledgers/household/main.beancount': 'option "title" "Household"\n',
        },
      );
      final bridge = _FakeBridgeFacade(
        sessionDiagnostics: const <BridgeValidationIssueDto>[],
        diagnosticSnapshots: const <List<BridgeValidationIssueDto>>[
          <BridgeValidationIssueDto>[],
        ],
      );
      final repository = BeancountRepositoryImpl(
        ledgerIo: ledgerIo,
        bridge: bridge,
      );

      await repository.appendTransaction(
        CreateTransactionInput(
          date: DateTime(2026, 4, 19),
          flag: '!',
          payee: 'Starbucks',
          summary: 'Morning Coffee',
          tags: const ['coffee', 'beverage'],
          links: const ['receipt-123'],
          metadata: const {'location': 'London'},
          postings: const [
            PostingInput(
              account: 'Expenses:Food:Coffee',
              amount: '18.50',
              commodity: 'CNY',
            ),
            PostingInput(account: 'Assets:Cash'),
          ],
        ),
      );

      expect(
        ledgerIo.fileContents['/app/ledgers/household/main.beancount'],
        'option "title" "Household"\n\n'
        '2026-04-19 ! "Starbucks" "Morning Coffee" #coffee #beverage ^receipt-123\n'
        '  location: "London"\n'
        '  Expenses:Food:Coffee  18.50 CNY\n'
        '  Assets:Cash\n',
      );
    },
  );

  test(
    'appendTransaction rejects summaries containing double quotes',
    () async {
      final ledgerIo = _FakeLedgerIoFacade(
        current: CurrentLedgerRecord(
          id: 'recent-id',
          name: 'Household',
          path: '/app/ledgers/household',
          entryFilePath: '/app/ledgers/household/main.beancount',
          lastImportedAt: DateTime(2026, 4, 15, 10, 0),
        ),
        fileContents: <String, String>{
          '/app/ledgers/household/main.beancount':
              'option "title" "Household"\n',
        },
      );
      final bridge = _FakeBridgeFacade(
        sessionDiagnostics: const <BridgeValidationIssueDto>[],
      );
      final repository = BeancountRepositoryImpl(
        ledgerIo: ledgerIo,
        bridge: bridge,
      );

      await expectLater(
        repository.appendTransaction(
          CreateTransactionInput(
            date: DateTime(2026, 4, 19),
            summary: 'He said "hi"',
            postings: const [
              PostingInput(
                account: 'Expenses:Food',
                amount: '18.50',
                commodity: 'CNY',
              ),
              PostingInput(account: 'Assets:Cash'),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('摘要暂不支持双引号'),
          ),
        ),
      );

      expect(ledgerIo.writeHistory, isEmpty);
      expect(bridge.refreshHandles, isEmpty);
    },
  );

  test(
    'appendTransaction rolls back the entry file when refresh reports blocking diagnostics',
    () async {
      final ledgerIo = _FakeLedgerIoFacade(
        current: CurrentLedgerRecord(
          id: 'recent-id',
          name: 'Household',
          path: '/app/ledgers/household',
          entryFilePath: '/app/ledgers/household/main.beancount',
          lastImportedAt: DateTime(2026, 4, 15, 10, 0),
        ),
        fileContents: <String, String>{
          '/app/ledgers/household/main.beancount':
              'option "title" "Household"\n',
        },
      );
      final bridge = _FakeBridgeFacade(
        sessionDiagnostics: const <BridgeValidationIssueDto>[],
        diagnosticSnapshots: const <List<BridgeValidationIssueDto>>[
          <BridgeValidationIssueDto>[
            BridgeValidationIssueDto(
              message: 'Transaction 不平衡',
              location: 'main.beancount:4',
              blocking: true,
            ),
          ],
          <BridgeValidationIssueDto>[],
        ],
      );
      final repository = BeancountRepositoryImpl(
        ledgerIo: ledgerIo,
        bridge: bridge,
      );

      await expectLater(
        repository.appendTransaction(
          CreateTransactionInput(
            date: DateTime(2026, 4, 19),
            summary: 'Coffee',
            postings: const [
              PostingInput(
                account: 'Expenses:Food',
                amount: '18.50',
                commodity: 'CNY',
              ),
              PostingInput(account: 'Assets:Cash'),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Transaction 不平衡'),
          ),
        ),
      );

      expect(ledgerIo.writeHistory, hasLength(2));
      expect(
        ledgerIo.writeHistory.last.content,
        'option "title" "Household"\n',
      );
      expect(bridge.refreshHandles, <int>[41, 41]);
    },
  );

  test(
    'appendTransaction keeps the saved entry when refresh only reports non-blocking diagnostics',
    () async {
      final ledgerIo = _FakeLedgerIoFacade(
        current: CurrentLedgerRecord(
          id: 'recent-id',
          name: 'Household',
          path: '/app/ledgers/household',
          entryFilePath: '/app/ledgers/household/main.beancount',
          lastImportedAt: DateTime(2026, 4, 15, 10, 0),
        ),
        fileContents: <String, String>{
          '/app/ledgers/household/main.beancount':
              'option "title" "Household"\n',
        },
      );
      final bridge = _FakeBridgeFacade(
        sessionDiagnostics: const <BridgeValidationIssueDto>[],
        diagnosticSnapshots: const <List<BridgeValidationIssueDto>>[
          <BridgeValidationIssueDto>[
            BridgeValidationIssueDto(
              message: '暂不支持 note 指令',
              location: 'main.beancount:4',
              blocking: false,
            ),
          ],
        ],
      );
      final repository = BeancountRepositoryImpl(
        ledgerIo: ledgerIo,
        bridge: bridge,
      );

      await repository.appendTransaction(
        CreateTransactionInput(
          date: DateTime(2026, 4, 19),
          summary: 'Coffee',
          postings: const [
            PostingInput(
              account: 'Expenses:Food',
              amount: '18.50',
              commodity: 'CNY',
            ),
            PostingInput(account: 'Assets:Cash'),
          ],
        ),
      );

      expect(ledgerIo.writeHistory, hasLength(1));
      expect(
        ledgerIo.fileContents['/app/ledgers/household/main.beancount'],
        contains('2026-04-19 * "Coffee"'),
      );
      expect(bridge.refreshHandles, <int>[41]);
    },
  );

  test(
    'appendTransaction rolls back the entry file when validation refresh throws',
    () async {
      final ledgerIo = _FakeLedgerIoFacade(
        current: CurrentLedgerRecord(
          id: 'recent-id',
          name: 'Household',
          path: '/app/ledgers/household',
          entryFilePath: '/app/ledgers/household/main.beancount',
          lastImportedAt: DateTime(2026, 4, 15, 10, 0),
        ),
        fileContents: <String, String>{
          '/app/ledgers/household/main.beancount':
              'option "title" "Household"\n',
        },
      );
      final bridge = _FakeBridgeFacade(
        sessionDiagnostics: const <BridgeValidationIssueDto>[],
        refreshError: StateError('refresh failed'),
      );
      final repository = BeancountRepositoryImpl(
        ledgerIo: ledgerIo,
        bridge: bridge,
      );

      await expectLater(
        repository.appendTransaction(
          CreateTransactionInput(
            date: DateTime(2026, 4, 19),
            summary: 'Coffee',
            postings: const [
              PostingInput(
                account: 'Expenses:Food',
                amount: '18.50',
                commodity: 'CNY',
              ),
              PostingInput(account: 'Assets:Cash'),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('refresh failed'),
          ),
        ),
      );

      expect(ledgerIo.writeHistory, hasLength(2));
      expect(
        ledgerIo.fileContents['/app/ledgers/household/main.beancount'],
        'option "title" "Household"\n',
      );
      expect(ledgerIo.writeHistory.map((write) => write.content), <String>[
        'option "title" "Household"\n\n'
            '2026-04-19 * "Coffee"\n'
            '  Expenses:Food  18.50 CNY\n'
            '  Assets:Cash\n',
        'option "title" "Household"\n',
      ]);
    },
  );

  test(
    'appendTransaction clears the cached session when rollback refresh fails',
    () async {
      final ledgerIo = _FakeLedgerIoFacade(
        current: CurrentLedgerRecord(
          id: 'recent-id',
          name: 'Household',
          path: '/app/ledgers/household',
          entryFilePath: '/app/ledgers/household/main.beancount',
          lastImportedAt: DateTime(2026, 4, 15, 10, 0),
        ),
        fileContents: <String, String>{
          '/app/ledgers/household/main.beancount':
              'option "title" "Household"\n',
        },
      );
      final bridge = _FakeBridgeFacade(
        sessionDiagnostics: const <BridgeValidationIssueDto>[],
        diagnosticSnapshots: const <List<BridgeValidationIssueDto>>[
          <BridgeValidationIssueDto>[
            BridgeValidationIssueDto(
              message: 'Transaction 不平衡',
              location: 'main.beancount:4',
              blocking: true,
            ),
          ],
        ],
        refreshOutcomes: <Object?>[null, StateError('rollback refresh failed')],
      );
      final repository = BeancountRepositoryImpl(
        ledgerIo: ledgerIo,
        bridge: bridge,
      );

      await expectLater(
        repository.appendTransaction(
          CreateTransactionInput(
            date: DateTime(2026, 4, 19),
            summary: 'Coffee',
            postings: const [
              PostingInput(
                account: 'Expenses:Food',
                amount: '18.50',
                commodity: 'CNY',
              ),
              PostingInput(account: 'Assets:Cash'),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Transaction 不平衡'),
          ),
        ),
      );

      await repository.loadValidationIssues();

      expect(bridge.openedRoots, <String>[
        '/app/ledgers/household',
        '/app/ledgers/household',
      ]);
      expect(bridge.closedHandles, <int>[41]);
    },
  );
}

class _FakeLedgerIoFacade implements LedgerIoFacade {
  _FakeLedgerIoFacade({
    this.current,
    this.recentLedgers = const <RecentLedgerRecord>[],
    this.ledgerFiles = const <LedgerIoFileRecord>[],
    List<List<LedgerIoFileRecord>>? ledgerFileSnapshots,
    Map<String, String>? fileContents,
    this.importedSummary,
    this.events,
  }) : _ledgerFileSnapshots = ledgerFileSnapshots,
       fileContents = fileContents ?? <String, String>{};

  final CurrentLedgerRecord? current;
  final List<RecentLedgerRecord> recentLedgers;
  final List<LedgerIoFileRecord> ledgerFiles;
  final List<List<LedgerIoFileRecord>>? _ledgerFileSnapshots;
  final ImportedLedgerSummary? importedSummary;
  final List<_FileWriteRecord> writeHistory = <_FileWriteRecord>[];
  final List<_SyncLedgerNameCall> syncLedgerNameCalls = <_SyncLedgerNameCall>[];
  final List<String> importedSourcePaths = <String>[];
  final List<String> deletedLedgerIds = <String>[];
  final Map<String, String> fileContents;
  final List<String>? events;
  int _ledgerFileLoadCount = 0;

  @override
  Future<ImportedLedgerSummary> createDefaultLedger() async =>
      _defaultImportedSummary();

  @override
  Future<void> exportLedger(String ledgerId, String destinationPath) async {}

  @override
  Future<ImportedLedgerSummary> importLedger(String sourcePath) async {
    importedSourcePaths.add(sourcePath);
    events?.add('import:$sourcePath');
    return importedSummary ?? _defaultImportedSummary();
  }

  @override
  Future<String> loadFileContent(String filePath) async =>
      fileContents[filePath] ?? '';

  @override
  Future<CurrentLedgerRecord?> loadCurrentLedger() async => current;

  @override
  Future<List<RecentLedgerRecord>> loadRecentLedgers() async => recentLedgers;

  @override
  Future<List<LedgerIoFileRecord>> loadLedgerFiles(
    String ledgerRootPath,
  ) async {
    if (_ledgerFileSnapshots != null) {
      final index = _ledgerFileLoadCount < _ledgerFileSnapshots.length
          ? _ledgerFileLoadCount
          : _ledgerFileSnapshots.length - 1;
      _ledgerFileLoadCount += 1;
      return _ledgerFileSnapshots[index];
    }
    return ledgerFiles;
  }

  @override
  Future<void> syncLedgerName(String ledgerId, String newName) async {
    syncLedgerNameCalls.add(
      _SyncLedgerNameCall(ledgerId: ledgerId, newName: newName),
    );
  }

  @override
  Future<void> setCurrentLedger(String ledgerId) async {}

  @override
  Future<void> deleteLedger(String ledgerId) async {
    deletedLedgerIds.add(ledgerId);
    events?.add('delete:$ledgerId');
  }

  @override
  Future<void> writeFileContent(String filePath, String content) async {
    fileContents[filePath] = content;
    writeHistory.add(_FileWriteRecord(path: filePath, content: content));
  }

  ImportedLedgerSummary _defaultImportedSummary() {
    return ImportedLedgerSummary(
      ledgerId: 'recent-id',
      name: 'Household',
      path: '/app/ledgers/household',
      entryFilePath: '/app/ledgers/household/main.beancount',
      fileCount: 1,
      lastImportedAt: DateTime(2026, 4, 15, 10, 0),
    );
  }
}

class _FakeBridgeFacade extends StubBeancountBridgeFacade {
  _FakeBridgeFacade({
    List<BridgeDocumentSummaryDto>? documentSummaries,
    Map<String, BridgeDocumentDto>? documentsById,
    this.sessionDiagnostics,
    List<List<BridgeValidationIssueDto>>? diagnosticSnapshots,
    this.refreshError,
    List<Object?>? refreshOutcomes,
    this.ledgerName = 'Household',
    this.events,
  }) : _documentSummaries = documentSummaries ?? _defaultDocumentSummaries,
       _documentsById = documentsById ?? _defaultDocumentsById,
       _diagnosticSnapshots = diagnosticSnapshots,
       _refreshOutcomes = refreshOutcomes;

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
  final List<int> closedHandles = <int>[];
  final List<int> diagnosticHandles = <int>[];
  final List<int> refreshHandles = <int>[];
  final List<BridgeDocumentSummaryDto> _documentSummaries;
  final Map<String, BridgeDocumentDto> _documentsById;
  final List<List<BridgeValidationIssueDto>>? _diagnosticSnapshots;
  final List<BridgeValidationIssueDto>? sessionDiagnostics;
  final Object? refreshError;
  final List<Object?>? _refreshOutcomes;
  final String ledgerName;
  final List<String>? events;
  int _diagnosticSnapshotIndex = 0;
  int _refreshOutcomeIndex = 0;

  @override
  Future<void> closeLedger(int handle) async {
    closedHandles.add(handle);
    events?.add('close:$handle');
  }

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
    if (_diagnosticSnapshots != null) {
      final index = _diagnosticSnapshotIndex < _diagnosticSnapshots.length
          ? _diagnosticSnapshotIndex
          : _diagnosticSnapshots.length - 1;
      _diagnosticSnapshotIndex += 1;
      return _diagnosticSnapshots[index];
    }
    return const <BridgeValidationIssueDto>[
      BridgeValidationIssueDto(
        message: 'blocking issue',
        location: 'main.beancount:1',
        blocking: true,
      ),
    ];
  }

  @override
  Future<BridgeLedgerSessionDto> openLedger(
    String rootPath,
    String entryFilePath,
  ) async {
    openedRoots.add(rootPath);
    events?.add('open:$rootPath');
    return BridgeLedgerSessionDto(
      handle: 41,
      summary: BridgeLedgerSummaryDto(
        ledgerId: 'parsed-ledger',
        ledgerName: ledgerName,
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
      diagnostics: sessionDiagnostics ?? const <BridgeValidationIssueDto>[],
    );
  }

  @override
  Future<BridgeRefreshResultDto> refreshLedger(int handle) async {
    refreshHandles.add(handle);
    if (_refreshOutcomes != null) {
      final index = _refreshOutcomeIndex < _refreshOutcomes.length
          ? _refreshOutcomeIndex
          : _refreshOutcomes.length - 1;
      _refreshOutcomeIndex += 1;
      final outcome = _refreshOutcomes[index];
      if (outcome != null) {
        throw outcome;
      }
    }
    if (refreshError != null) {
      throw refreshError!;
    }
    return BridgeRefreshResultDto(
      summary: BridgeLedgerSummaryDto(
        ledgerId: 'parsed-ledger',
        ledgerName: ledgerName,
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

class _FileWriteRecord {
  const _FileWriteRecord({required this.path, required this.content});

  final String path;
  final String content;
}

class _SyncLedgerNameCall {
  const _SyncLedgerNameCall({required this.ledgerId, required this.newName});

  final String ledgerId;
  final String newName;
}
