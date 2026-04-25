import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/app/di/app_providers.dart';
import 'package:tally_bean/app/session/quick_entry_session.dart';
import 'package:tally_bean/features/compose_transaction/application/compose_transaction_providers.dart';
import 'package:tally_bean/features/ledger/application/ledger_providers.dart';
import 'package:tally_bean/shared/widgets/async_error_view.dart';
import 'package:tally_bean/shared/widgets/async_loading_view.dart';
import 'package:tally_bean/shared/widgets/ledger_gate_view.dart';

enum TransactionMode { expense, income, transfer, advanced }

class PostingController {
  PostingController({
    String account = '',
    String amount = '',
    String? commodity,
    this.isExpanded = false,
  }) : accountController = TextEditingController(text: account),
       amountController = TextEditingController(text: amount),
       commodityController = TextEditingController(text: commodity);

  final TextEditingController accountController;
  final TextEditingController amountController;
  final TextEditingController commodityController;
  bool isExpanded;

  void dispose() {
    accountController.dispose();
    amountController.dispose();
    commodityController.dispose();
  }
}

class MetaEntryController {
  MetaEntryController({String key = '', String value = ''})
    : keyController = TextEditingController(text: key),
      valueController = TextEditingController(text: value);

  final TextEditingController keyController;
  final TextEditingController valueController;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

class ComposeTransactionPage extends ConsumerStatefulWidget {
  const ComposeTransactionPage({super.key});

  @override
  ConsumerState<ComposeTransactionPage> createState() =>
      _ComposeTransactionPageState();
}

class _ComposeTransactionPageState
    extends ConsumerState<ComposeTransactionPage> {
  static final RegExp _positiveDecimalAmountPattern = RegExp(
    r'^\d+(?:\.\d+)?$',
  );
  static const String _unsupportedSummaryQuoteMessage = '摘要暂不支持双引号';
  static const String _unsupportedPayeeQuoteMessage = '交易对手暂不支持双引号';

  String? _summaryValidationMessage(String summary) {
    if (summary.contains('"')) {
      return _unsupportedSummaryQuoteMessage;
    }
    return null;
  }

  String? _payeeValidationMessage(String payee) {
    if (payee.contains('"')) {
      return _unsupportedPayeeQuoteMessage;
    }
    return null;
  }

  TransactionMode _mode = TransactionMode.expense;
  String _flag = '*';
  late final DateTime _initialDate;
  late DateTime _selectedDate;
  late final TextEditingController _payeeController;
  late final TextEditingController _narrationController;
  final List<String> _tags = [];
  final List<String> _links = [];

  String? _primaryAccount;
  String? _counterAccount;

  final List<PostingController> _advancedPostings = [];
  final List<MetaEntryController> _metadata = [];

  bool _allowImmediatePop = false;

  @override
  void initState() {
    super.initState();
    _initialDate = DateUtils.dateOnly(DateTime.now());
    _selectedDate = _initialDate;
    _payeeController = TextEditingController();
    _narrationController = TextEditingController();

    _advancedPostings.add(_createPostingController());
    _advancedPostings.add(_createPostingController());

    _payeeController.addListener(_handleDraftChanged);
    _narrationController.addListener(_handleDraftChanged);
  }

  @override
  void dispose() {
    _payeeController.dispose();
    _narrationController.dispose();
    for (var p in _advancedPostings) {
      p.dispose();
    }
    for (var m in _metadata) {
      m.dispose();
    }
    super.dispose();
  }

  void _handleDraftChanged() {
    ref.read(composeTransactionActionControllerProvider.notifier).clearError();
    if (mounted) {
      setState(() {});
    }
  }

  PostingController _createPostingController({
    String account = '',
    String amount = '',
    String? commodity,
  }) {
    final controller = PostingController(
      account: account,
      amount: amount,
      commodity: commodity,
    );
    controller.accountController.addListener(_handleDraftChanged);
    controller.amountController.addListener(_handleDraftChanged);
    controller.commodityController.addListener(_handleDraftChanged);
    return controller;
  }

  MetaEntryController _createMetaEntryController({
    String key = '',
    String value = '',
  }) {
    final controller = MetaEntryController(key: key, value: value);
    controller.keyController.addListener(_handleDraftChanged);
    controller.valueController.addListener(_handleDraftChanged);
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final ledgerState = ref.watch(currentLedgerProvider);
    final ledger = ledgerState.asData?.value;
    final submitState = ref.watch(composeTransactionActionControllerProvider);
    final accountOptionsState = ref.watch(
      composeTransactionAccountOptionsProvider,
    );
    final recentPairs = ref.watch(recentAccountPairsProvider);
    final recentPrimaryAccounts = ref.watch(recentPrimaryAccountsProvider);
    final recentCounterAccounts = ref.watch(recentCounterAccountsProvider);
    final isDemoMode = ref.watch(appConfigProvider).useDemoData;

    if (ledgerState.hasError && ledger == null) {
      return Scaffold(
        body: AsyncErrorView(
          error: ledgerState.error!,
          message: '账本加载失败',
          onRetry: () => ref.invalidate(currentLedgerProvider),
        ),
      );
    }
    if (ledgerState.isLoading) {
      return const Scaffold(body: AsyncLoadingView());
    }
    if (ledger == null) {
      return const Scaffold(
        body: LedgerGateView(title: '还没有账本', message: '导入账本后才能开始录入交易。'),
      );
    }
    if (ledger.status == LedgerStatus.issuesFirst) {
      return const Scaffold(
        body: LedgerGateView(
          title: '录入已锁定',
          message: '当前账本存在阻塞性问题，请先前往账本页处理 issues。',
        ),
      );
    }

    final operatingCurrencies = ledger.operatingCurrencies.isEmpty
        ? ['CNY']
        : ledger.operatingCurrencies;
    final defaultCurrency = operatingCurrencies.first;

    final canSubmit =
        !isDemoMode &&
        !submitState.isLoading &&
        _isFormValid(accountOptionsState.hasValue);
    final canPreview = !submitState.isLoading;
    final shouldBlockPop =
        !_allowImmediatePop && (submitState.isLoading || _hasUnsavedChanges);

    return PopScope<Object?>(
      canPop: !shouldBlockPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscardIfNeeded();
        if (!shouldPop || !mounted) return;
        setState(() => _allowImmediatePop = true);
        _popPage();
      },
      child: Scaffold(
        appBar: AppBar(
          title: null,
          actions: [
            IconButton(
              key: const Key('compose-preview-button'),
              tooltip: '预览',
              onPressed: canPreview
                  ? () => _showPreview(defaultCurrency)
                  : null,
              icon: const Icon(Icons.article_outlined),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            children: [
              if (isDemoMode) ...[
                _ReadOnlyNotice(message: '演示数据模式当前为只读，不能保存新交易。'),
                const SizedBox(height: 8),
              ],

              _buildModeSelector(),
              const SizedBox(height: 12),

              // 标记 + 日期 (同一行，无 label)
              Row(
                children: [
                  _buildFlagSelector(),
                  const SizedBox(width: 12),
                  Expanded(child: _buildDatePicker()),
                ],
              ),
              const SizedBox(height: 12),

              // 分录区
              TallySectionCard(
                trailing: _mode == TransactionMode.advanced
                    ? IconButton(
                        onPressed: _addPostingRow,
                        icon: const Icon(Icons.add_circle_outline),
                        visualDensity: VisualDensity.compact,
                      )
                    : null,
                child: _buildPostingsSection(
                  accountOptionsState,
                  recentPairs,
                  recentPrimaryAccounts,
                  recentCounterAccounts,
                  operatingCurrencies,
                  defaultCurrency,
                ),
              ),
              const SizedBox(height: 12),

              // 交易对手 + 摘要 (移到分录下方)
              TallySectionCard(
                child: Column(
                  children: [
                    TextField(
                      key: const Key('compose-payee-field'),
                      controller: _payeeController,
                      decoration: InputDecoration(
                        labelText: '交易对手',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        errorText: _payeeValidationMessage(
                          _payeeController.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('compose-summary-field'),
                      controller: _narrationController,
                      decoration: InputDecoration(
                        labelText: '摘要',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        errorText: _summaryValidationMessage(
                          _narrationController.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              _buildExtendedMetaSection(),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('compose-submit-button'),
                  onPressed: canSubmit ? () => _submit(defaultCurrency) : null,
                  child: submitState.isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存'),
                ),
              ),

              if (submitState.hasError) ...[
                const SizedBox(height: 8),
                Text(
                  '保存失败: ${submitState.error}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Center(
      child: SegmentedButton<TransactionMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: TransactionMode.expense,
            label: Text('支出'),
            icon: Icon(Icons.outbox),
          ),
          ButtonSegment(
            value: TransactionMode.income,
            label: Text('收入'),
            icon: Icon(Icons.inbox),
          ),
          ButtonSegment(
            value: TransactionMode.transfer,
            label: Text('转账'),
            icon: Icon(Icons.swap_horiz),
          ),
          ButtonSegment(
            value: TransactionMode.advanced,
            label: Text('专业'),
            icon: Icon(Icons.layers),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (val) {
          _mode = val.first;
          _handleDraftChanged();
        },
      ),
    );
  }

  Widget _buildFlagSelector() {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: '*', label: Text('*')),
        ButtonSegment(value: '!', label: Text('!')),
      ],
      selected: {_flag},
      onSelectionChanged: (val) {
        _flag = val.first;
        _handleDraftChanged();
      },
    );
  }

  Widget _buildDatePicker() {
    return OutlinedButton.icon(
      onPressed: _pickDate,
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  Widget _buildPostingsSection(
    AsyncValue<List<ComposeAccountOption>> optionsState,
    List<RecentAccountPair> recentPairs,
    List<String> recentPrimary,
    List<String> recentCounter,
    List<String> operatingCurrencies,
    String defaultCurrency,
  ) {
    if (_mode == TransactionMode.advanced) {
      return Column(
        children: [
          for (int i = 0; i < _advancedPostings.length; i++)
            _buildAdvancedPostingRow(
              i,
              optionsState,
              [],
              operatingCurrencies,
              defaultCurrency,
            ),
        ],
      );
    }

    return Column(
      children: [
        _buildSimpleAmountField(operatingCurrencies, defaultCurrency),
        const SizedBox(height: 10),
        // 两个账户放同一行
        Row(
          children: [
            Expanded(
              child: _AccountPickerButton(
                fieldKey: const Key('compose-primary-account-field'),
                value: _primaryAccount,
                placeholder: _sourceAccountPlaceholder,
                onTap: () => _selectAccount(
                  optionsState: optionsState,
                  recentAccounts: recentPrimary,
                  onSelected: (val) {
                    _primaryAccount = val;
                    _handleDraftChanged();
                  },
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
            ),
            Expanded(
              child: _AccountPickerButton(
                fieldKey: const Key('compose-counter-account-field'),
                value: _counterAccount,
                placeholder: _destinationAccountPlaceholder,
                onTap: () => _selectAccount(
                  optionsState: optionsState,
                  recentAccounts: recentCounter,
                  onSelected: (val) {
                    _counterAccount = val;
                    _handleDraftChanged();
                  },
                ),
              ),
            ),
          ],
        ),

        if (recentPairs.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildRecentPairs(recentPairs),
        ],
      ],
    );
  }

  String get _sourceAccountPlaceholder {
    return switch (_mode) {
      TransactionMode.expense => '资金来源',
      TransactionMode.income => '收入来源',
      TransactionMode.transfer => '来源账户',
      TransactionMode.advanced => '账户',
    };
  }

  String get _destinationAccountPlaceholder {
    return switch (_mode) {
      TransactionMode.expense => '支出类别',
      TransactionMode.income => '入账账户',
      TransactionMode.transfer => '目标账户',
      TransactionMode.advanced => '账户',
    };
  }

  Widget _buildSimpleAmountField(
    List<String> operatingCurrencies,
    String defaultCurrency,
  ) {
    final controller = _advancedPostings.first.amountController;
    final commodityController = _advancedPostings.first.commodityController;
    final currentCurrency = _resolveCurrency(
      commodityController.text,
      defaultCurrency,
    );
    final dropdownItems = operatingCurrencies.contains(currentCurrency)
        ? operatingCurrencies
        : [...operatingCurrencies, currentCurrency];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          DropdownButton<String>(
            value: currentCurrency,
            underline: const SizedBox(),
            isDense: true,
            items: dropdownItems
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (val) {
              if (val != null) {
                commodityController.text = val;
                _handleDraftChanged();
              }
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const Key('compose-amount-field'),
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: '金额',
                border: OutlineInputBorder(),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedPostingRow(
    int index,
    AsyncValue<List<ComposeAccountOption>> optionsState,
    List<String> recent,
    List<String> operatingCurrencies,
    String defaultCurrency,
  ) {
    final posting = _advancedPostings[index];
    final currentCurrency = _resolveCurrency(
      posting.commodityController.text,
      defaultCurrency,
    );
    final dropdownItems = operatingCurrencies.contains(currentCurrency)
        ? operatingCurrencies
        : [...operatingCurrencies, currentCurrency];
    final isExpanded = posting.isExpanded;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      posting.isExpanded = !isExpanded;
                    });
                  },
                  child: AbsorbPointer(
                    child: _AccountPickerButton(
                      value: posting.accountController.text.isEmpty
                          ? null
                          : posting.accountController.text,
                      placeholder: '账户',
                      onTap: () {},
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                visualDensity: VisualDensity.compact,
                onPressed: () => _selectAccount(
                  optionsState: optionsState,
                  recentAccounts: recent,
                  onSelected: (val) {
                    posting.accountController.text = val;
                    setState(() {
                      posting.isExpanded = true;
                    });
                    _handleDraftChanged();
                  },
                ),
              ),
              if (_advancedPostings.length > 2)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final removed = _advancedPostings.removeAt(index);
                    removed.dispose();
                    _handleDraftChanged();
                  },
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    color: Colors.red,
                    size: 20,
                  ),
                ),
            ],
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  DropdownButton<String>(
                    value: currentCurrency,
                    underline: const SizedBox(),
                    isDense: true,
                    items: dropdownItems
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        posting.commodityController.text = val;
                        _handleDraftChanged();
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: posting.amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        hintText: '金额',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExtendedMetaSection() {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      title: const Text('扩展属性'),
      leading: const Icon(Icons.more_horiz, size: 20),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        // 标签
        _buildChipRow(
          label: '标签',
          items: _tags,
          onAdd: () =>
              _showAddItemDialog('新建标签', (val) => _addItemTokens(_tags, val)),
          onRemove: (index) {
            _tags.removeAt(index);
            _handleDraftChanged();
          },
          prefix: '#',
        ),
        const SizedBox(height: 8),
        // 链接
        _buildChipRow(
          label: '链接',
          items: _links,
          onAdd: () =>
              _showAddItemDialog('新建链接', (val) => _addItemTokens(_links, val)),
          onRemove: (index) {
            _links.removeAt(index);
            _handleDraftChanged();
          },
          prefix: '^',
        ),
        const SizedBox(height: 8),
        // 元数据
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('元数据', style: Theme.of(context).textTheme.bodySmall),
            IconButton(
              onPressed: _addMetadataRow,
              icon: const Icon(Icons.add_circle_outline, size: 20),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        for (int i = 0; i < _metadata.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _metadata[i].keyController,
                    decoration: const InputDecoration(
                      hintText: 'Key',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _metadata[i].valueController,
                    decoration: const InputDecoration(
                      hintText: 'Value',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    final removed = _metadata.removeAt(i);
                    removed.dispose();
                    _handleDraftChanged();
                  },
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildChipRow({
    required String label,
    required List<String> items,
    required VoidCallback onAdd,
    required void Function(int) onRemove,
    String prefix = '',
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (int i = 0; i < items.length; i++)
                Chip(
                  label: Text(
                    '$prefix${items[i]}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => onRemove(i),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: onAdd,
          icon: const Icon(Icons.add_circle_outline, size: 20),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Future<void> _showAddItemDialog(
    String title,
    ValueChanged<String> onConfirm,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _AddItemDialog(title: title),
    );
    if (!mounted) return;
    if (result != null) onConfirm(result);
  }

  void _addItemTokens(List<String> items, String input) {
    final tokens = input
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) return;
    items.addAll(tokens);
    _handleDraftChanged();
  }

  Widget _buildRecentPairs(List<RecentAccountPair> pairs) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 0; i < pairs.length && i < 3; i++)
          ActionChip(
            key: Key('compose-recent-pair-chip-$i'),
            avatar: const Icon(Icons.history, size: 16),
            label: Text(pairs[i].label, style: const TextStyle(fontSize: 12)),
            onPressed: () {
              _primaryAccount = pairs[i].primaryAccount;
              _counterAccount = pairs[i].counterAccount;
              _handleDraftChanged();
            },
          ),
      ],
    );
  }

  void _addPostingRow() {
    _advancedPostings.add(_createPostingController());
    _handleDraftChanged();
  }

  void _addMetadataRow() {
    _metadata.add(_createMetaEntryController());
    _handleDraftChanged();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    _selectedDate = DateUtils.dateOnly(date);
    _handleDraftChanged();
  }

  Future<void> _selectAccount({
    required AsyncValue<List<ComposeAccountOption>> optionsState,
    required List<String> recentAccounts,
    required ValueChanged<String> onSelected,
  }) async {
    final options = optionsState.asData?.value;
    if (options == null || options.isEmpty) return;

    final allPaths = options.map((option) => option.fullPath).toList();
    final recentChoices = recentAccounts
        .where((path) => allPaths.contains(path))
        .toList(growable: false);
    final remainingChoices = allPaths
        .where((path) => !recentChoices.contains(path))
        .toList(growable: false);

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '选择账户',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      if (recentChoices.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Text('最近使用'),
                        ),
                        for (final path in recentChoices) ...[
                          ListTile(
                            title: Text(path),
                            onTap: () => Navigator.of(ctx).pop(path),
                          ),
                          const Divider(height: 1),
                        ],
                      ],
                      if (remainingChoices.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Text('全部账户'),
                        ),
                        for (
                          var index = 0;
                          index < remainingChoices.length;
                          index++
                        ) ...[
                          ListTile(
                            title: Text(remainingChoices[index]),
                            onTap: () =>
                                Navigator.of(ctx).pop(remainingChoices[index]),
                          ),
                          if (index != remainingChoices.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null) onSelected(selected);
  }

  bool _isFormValid(bool accountOptionsLoaded) {
    if (!accountOptionsLoaded) return false;
    final summary = _narrationController.text.trim();
    if (summary.isEmpty || _summaryValidationMessage(summary) != null) {
      return false;
    }

    if (_mode == TransactionMode.advanced) {
      var accountCount = 0;
      var hasAmount = false;
      for (final posting in _advancedPostings) {
        final account = posting.accountController.text.trim();
        final amount = posting.amountController.text.trim();
        if (account.isEmpty) {
          if (amount.isNotEmpty) return false;
          continue;
        }
        accountCount += 1;
        if (amount.isNotEmpty) {
          if (_parsePositiveAmount(amount) == null) return false;
          hasAmount = true;
        }
      }
      return accountCount >= 2 && hasAmount;
    } else {
      final amountStr = _advancedPostings.first.amountController.text;
      final parsedAmount = _parsePositiveAmount(amountStr);
      final isValid =
          _primaryAccount != null &&
          _counterAccount != null &&
          _primaryAccount != _counterAccount &&
          parsedAmount != null;
      return isValid;
    }
  }

  num? _parsePositiveAmount(String input) {
    final normalized = input.trim();
    if (normalized.isEmpty ||
        !_positiveDecimalAmountPattern.hasMatch(normalized)) {
      return null;
    }
    final parsed = num.tryParse(normalized);
    if (parsed == null || !parsed.isFinite || parsed <= 0) return null;
    return parsed;
  }

  String _resolveCurrency(String input, String defaultCurrency) {
    final selected = input.trim();
    return selected.isEmpty ? defaultCurrency : selected;
  }

  Future<void> _showPreview(String defaultCurrency) async {
    FocusScope.of(context).unfocus();

    final previewText = _buildTransactionPreviewText(defaultCurrency);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('交易预览'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              previewText,
              key: const Key('compose-preview-text'),
              style: Theme.of(
                ctx,
              ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _buildTransactionPreviewText(String defaultCurrency) {
    return serializeTransactionInput(
      _buildPreviewTransactionInput(defaultCurrency),
    );
  }

  Future<void> _submit(String defaultCurrency) async {
    FocusScope.of(context).unfocus();

    final saved = await ref
        .read(composeTransactionActionControllerProvider.notifier)
        .submit(_buildTransactionInput(defaultCurrency));

    if (saved && mounted) _popPage();
  }

  CreateTransactionInput _buildPreviewTransactionInput(String defaultCurrency) {
    final postings = <PostingInput>[];

    if (_mode == TransactionMode.advanced) {
      for (var p in _advancedPostings) {
        final account = p.accountController.text.trim();
        final amount = p.amountController.text.trim();
        final commodity = p.commodityController.text.trim();
        if (account.isEmpty && amount.isEmpty && commodity.isEmpty) {
          continue;
        }
        postings.add(
          PostingInput(
            account: account.isEmpty ? '<账户>' : account,
            amount: amount.isEmpty ? null : amount,
            commodity: amount.isEmpty
                ? null
                : _resolveCurrency(commodity, defaultCurrency),
          ),
        );
      }
    } else {
      final amount = _advancedPostings.first.amountController.text.trim();
      final commodity = _resolveCurrency(
        _advancedPostings.first.commodityController.text,
        defaultCurrency,
      );
      final sourcePlaceholder = '<$_sourceAccountPlaceholder>';
      final destinationPlaceholder = '<$_destinationAccountPlaceholder>';
      if (_primaryAccount != null ||
          _counterAccount != null ||
          amount.isNotEmpty) {
        postings.add(
          PostingInput(account: _primaryAccount ?? sourcePlaceholder),
        );
      }
      if (_counterAccount != null ||
          _primaryAccount != null ||
          amount.isNotEmpty) {
        postings.add(
          PostingInput(
            account: _counterAccount ?? destinationPlaceholder,
            amount: amount.isEmpty ? null : amount,
            commodity: amount.isEmpty ? null : commodity,
          ),
        );
      }
    }

    return _buildBaseTransactionInput(postings);
  }

  CreateTransactionInput _buildTransactionInput(String defaultCurrency) {
    final List<PostingInput> postings = [];

    if (_mode == TransactionMode.advanced) {
      for (var p in _advancedPostings) {
        final account = p.accountController.text.trim();
        if (account.isNotEmpty) {
          final amount = p.amountController.text.trim();
          postings.add(
            PostingInput(
              account: account,
              amount: amount.isEmpty ? null : amount,
              commodity: amount.isEmpty
                  ? null
                  : _resolveCurrency(
                      p.commodityController.text,
                      defaultCurrency,
                    ),
            ),
          );
        }
      }
    } else {
      final amount = _advancedPostings.first.amountController.text.trim();
      final commodity = _resolveCurrency(
        _advancedPostings.first.commodityController.text,
        defaultCurrency,
      );
      postings.add(PostingInput(account: _primaryAccount!));
      postings.add(
        PostingInput(
          account: _counterAccount!,
          amount: amount,
          commodity: commodity,
        ),
      );
    }

    return _buildBaseTransactionInput(postings);
  }

  CreateTransactionInput _buildBaseTransactionInput(
    List<PostingInput> postings,
  ) {
    final tags = List<String>.from(_tags);
    final links = List<String>.from(_links);
    final metadata = _buildMetadataInput();
    final payee = _payeeController.text.trim();
    return CreateTransactionInput(
      date: _selectedDate,
      flag: _flag,
      payee: payee.isEmpty ? null : payee,
      summary: _narrationController.text.trim(),
      postings: postings,
      tags: tags,
      links: links,
      metadata: metadata,
      recordQuickEntry: _mode != TransactionMode.advanced,
    );
  }

  Map<String, String> _buildMetadataInput() {
    final metadata = <String, String>{};
    for (var m in _metadata) {
      final key = m.keyController.text.trim();
      if (key.isNotEmpty) {
        metadata[key] = m.valueController.text.trim();
      }
    }
    return metadata;
  }

  bool get _hasUnsavedChanges {
    return _mode != TransactionMode.expense ||
        _flag != '*' ||
        !_isSameDate(_selectedDate, _initialDate) ||
        _narrationController.text.trim().isNotEmpty ||
        _payeeController.text.trim().isNotEmpty ||
        _primaryAccount != null ||
        _counterAccount != null ||
        _tags.isNotEmpty ||
        _links.isNotEmpty ||
        _advancedPostings.length != 2 ||
        _advancedPostings.any(_postingHasInput) ||
        _metadata.isNotEmpty;
  }

  bool _postingHasInput(PostingController posting) {
    return posting.accountController.text.trim().isNotEmpty ||
        posting.amountController.text.trim().isNotEmpty ||
        posting.commodityController.text.trim().isNotEmpty;
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (ref.read(composeTransactionActionControllerProvider).isLoading) {
      return false;
    }
    if (!_hasUnsavedChanges) return true;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃这次录入？'),
        content: const Text('当前表单还有未保存内容，返回后这些输入会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('保留内容'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  void _popPage([Object? result]) {
    final root = Navigator.of(context, rootNavigator: true);
    if (root.canPop()) {
      root.pop(result);
    } else {
      Navigator.of(context).pop(result);
    }
  }
}

class _AccountPickerButton extends StatelessWidget {
  const _AccountPickerButton({
    this.fieldKey,
    this.value,
    required this.placeholder,
    required this.onTap,
  });
  final Key? fieldKey;
  final String? value;
  final String placeholder;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        key: fieldKey,
        onPressed: onTap,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(value ?? placeholder, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog({required this.title});

  final String title;

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '输入内容',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        onSubmitted: (val) {
          final trimmed = val.trim();
          if (trimmed.isNotEmpty) Navigator.pop(context, trimmed);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final val = _controller.text.trim();
            if (val.isNotEmpty) Navigator.pop(context, val);
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(color: colors.onSecondaryContainer),
      ),
    );
  }
}
