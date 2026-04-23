import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/app/di/app_providers.dart';
import 'package:tally_bean/app/session/quick_entry_session.dart';
import 'package:tally_bean/features/compose_transaction/application/compose_transaction_providers.dart';
import 'package:tally_bean/features/settings/application/settings_providers.dart';
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
  }) : accountController = TextEditingController(text: account),
       amountController = TextEditingController(text: amount),
       commodityController = TextEditingController(text: commodity);

  final TextEditingController accountController;
  final TextEditingController amountController;
  final TextEditingController commodityController;

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
  static const String _unsupportedSummaryQuoteMessage = '摘要暂不支持双引号';

  String? _summaryValidationMessage(String summary) {
    if (summary.contains('"')) {
      return _unsupportedSummaryQuoteMessage;
    }
    return null;
  }

  TransactionMode _mode = TransactionMode.expense;
  String _flag = '*';
  late DateTime _selectedDate;
  late final TextEditingController _payeeController;
  late final TextEditingController _narrationController;
  late final TextEditingController _tagsController;
  late final TextEditingController _linksController;

  String? _primaryAccount;
  String? _counterAccount;

  final List<PostingController> _advancedPostings = [];
  final List<MetaEntryController> _metadata = [];

  bool _allowImmediatePop = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateUtils.dateOnly(DateTime.now());
    _payeeController = TextEditingController();
    _narrationController = TextEditingController();
    _tagsController = TextEditingController();
    _linksController = TextEditingController();

    _advancedPostings.add(PostingController());
    _advancedPostings.add(PostingController());

    _payeeController.addListener(_handleDraftChanged);
    _narrationController.addListener(_handleDraftChanged);
  }

  @override
  void dispose() {
    _payeeController.dispose();
    _narrationController.dispose();
    _tagsController.dispose();
    _linksController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final ledgerState = ref.watch(currentLedgerProvider);
    final ledger = ledgerState.asData?.value;
    final title = ref.watch(composeTransactionTitleProvider);
    final submitState = ref.watch(composeTransactionActionControllerProvider);
    final accountOptionsState = ref.watch(
      composeTransactionAccountOptionsProvider,
    );
    final recentPairs = ref.watch(recentAccountPairsProvider);
    final recentPrimaryAccounts = ref.watch(recentPrimaryAccountsProvider);
    final recentCounterAccounts = ref.watch(recentCounterAccountsProvider);
    final isDemoMode = ref.watch(appConfigProvider).useDemoData;
    final baseCurrency = ref.watch(settingsBaseCurrencyProvider);

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

    final canSubmit =
        !isDemoMode &&
        !submitState.isLoading &&
        _isFormValid(accountOptionsState.hasValue);
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
          title: Text(title),
          actions: [
            if (submitState.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              TextButton(
                onPressed: canSubmit ? _submit : null,
                child: const Text(
                  '保存',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            children: [
              if (isDemoMode) ...[
                _ReadOnlyNotice(message: '演示数据模式当前为只读，不能保存新交易。'),
                const SizedBox(height: 16),
              ],

              _buildModeSelector(),
              const SizedBox(height: 24),

              TallySectionCard(
                title: '交易草稿',
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildFlagSelector(),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _FieldLabel(
                            label: '日期',
                            child: _buildDatePicker(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('compose-payee-field'),
                      controller: _payeeController,
                      decoration: const InputDecoration(
                        labelText: '交易对手 (Payee)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('compose-summary-field'),
                      controller: _narrationController,
                      decoration: InputDecoration(
                        labelText: '摘要',
                        border: const OutlineInputBorder(),
                        errorText: _summaryValidationMessage(_narrationController.text),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              TallySectionCard(
                title:
                    _mode == TransactionMode.advanced ? '分录 (Postings)' : '交易明细',
                trailing:
                    _mode == TransactionMode.advanced
                        ? IconButton(
                          onPressed: _addPostingRow,
                          icon: const Icon(Icons.add_circle_outline),
                        )
                        : null,
                child: _buildPostingsSection(
                  accountOptionsState,
                  recentPairs,
                  recentPrimaryAccounts,
                  recentCounterAccounts,
                  baseCurrency,
                ),
              ),
              const SizedBox(height: 16),

              _buildExtendedMetaSection(),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('compose-submit-button'),
                  onPressed: canSubmit ? _submit : null,
                  child:
                      submitState.isLoading
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('保存'),
                ),
              ),

              if (submitState.hasError) ...[
                const SizedBox(height: 12),
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
          setState(() {
            _mode = val.first;
          });
        },
      ),
    );
  }

  Widget _buildFlagSelector() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: '*', label: Text('*')),
        ButtonSegment(value: '!', label: Text('!')),
      ],
      selected: {_flag},
      onSelectionChanged: (val) => setState(() => _flag = val.first),
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
    String baseCurrency,
  ) {
    if (_mode == TransactionMode.advanced) {
      return Column(
        children: [
          for (int i = 0; i < _advancedPostings.length; i++)
            _buildAdvancedPostingRow(i, optionsState, []),
        ],
      );
    }

    return Column(
      children: [
        _FieldLabel(
          label: _mode == TransactionMode.expense ? '记到账户 (支出类别)' : '目标账户',
          child: _AccountPickerButton(
            fieldKey: const Key('compose-primary-account-field'),
            value: _primaryAccount,
            placeholder: '选择账户',
            onTap:
                () => _selectAccount(
                  optionsState: optionsState,
                  recentAccounts: recentPrimary,
                  onSelected: (val) => setState(() => _primaryAccount = val),
                ),
          ),
        ),
        const SizedBox(height: 16),
        _FieldLabel(
          label: _mode == TransactionMode.expense ? '从账户 (资金流出)' : '来源账户',
          child: _AccountPickerButton(
            fieldKey: const Key('compose-counter-account-field'),
            value: _counterAccount,
            placeholder: '选择账户',
            onTap:
                () => _selectAccount(
                  optionsState: optionsState,
                  recentAccounts: recentCounter,
                  onSelected: (val) => setState(() => _counterAccount = val),
                ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSimpleAmountField(baseCurrency),

        if (recentPairs.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildRecentPairs(recentPairs),
        ],
      ],
    );
  }

  Widget _buildSimpleAmountField(String baseCurrency) {
    final controller = _advancedPostings.first.amountController;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('compose-amount-field'),
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: '金额',
              suffixText: baseCurrency,
              prefixIcon: const Icon(Icons.payments_outlined),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '快录模式将自动使用 $baseCurrency 作为记账币种。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedPostingRow(
    int index,
    AsyncValue<List<ComposeAccountOption>> optionsState,
    List<String> recent,
  ) {
    final posting = _advancedPostings[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: _AccountPickerButton(
              value:
                  posting.accountController.text.isEmpty
                      ? null
                      : posting.accountController.text,
              placeholder: '账户',
              onTap:
                  () => _selectAccount(
                    optionsState: optionsState,
                    recentAccounts: recent,
                    onSelected: (val) {
                      setState(() => posting.accountController.text = val);
                    },
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: posting.amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                hintText: '金额',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (_advancedPostings.length > 2)
            IconButton(
              onPressed:
                  () => setState(() => _advancedPostings.removeAt(index)),
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
            ),
        ],
      ),
    );
  }

  Widget _buildExtendedMetaSection() {
    return ExpansionTile(
      title: const Text('扩展属性 (Tags, Links, Meta)'),
      leading: const Icon(Icons.more_horiz),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: '标签 (用空格分隔)',
                  hintText: 'travel shopping',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _linksController,
                decoration: const InputDecoration(
                  labelText: '链接 (用空格分隔)',
                  hintText: 'receipt-123',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('自定义元数据'),
                  IconButton(
                    onPressed: _addMetadataRow,
                    icon: const Icon(Icons.add_box_outlined),
                  ),
                ],
              ),
              for (var meta in _metadata)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: meta.keyController,
                          decoration: const InputDecoration(
                            hintText: 'Key',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: meta.valueController,
                          decoration: const InputDecoration(
                            hintText: 'Value',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed:
                            () => setState(() => _metadata.remove(meta)),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
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
            onPressed:
                () => setState(() {
                  _primaryAccount = pairs[i].primaryAccount;
                  _counterAccount = pairs[i].counterAccount;
                }),
          ),
      ],
    );
  }

  void _addPostingRow() =>
      setState(() => _advancedPostings.add(PostingController()));
  void _addMetadataRow() =>
      setState(() => _metadata.add(MetaEntryController()));

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null) setState(() => _selectedDate = date);
  }

  Future<void> _selectAccount({
    required AsyncValue<List<ComposeAccountOption>> optionsState,
    required List<String> recentAccounts,
    required ValueChanged<String> onSelected,
  }) async {
    final options = optionsState.asData?.value;
    if (options == null || options.isEmpty) return;

    final allPaths = options.map((option) => option.fullPath).toList();
    final recentChoices =
        recentAccounts
            .where((path) => allPaths.contains(path))
            .toList(growable: false);
    final remainingChoices =
        allPaths
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
                            onTap:
                                () =>
                                    Navigator.of(ctx).pop(
                                      remainingChoices[index],
                                    ),
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
      final validPostings =
          _advancedPostings
              .where((p) => p.accountController.text.isNotEmpty)
              .toList();
      return validPostings.length >= 2;
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

  void _handlePostingChanged() {
    _handleDraftChanged();
  }

  num? _parsePositiveAmount(String input) {
    if (input.isEmpty) return null;
    final parsed = num.tryParse(input);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final baseCurrency = ref.read(settingsBaseCurrencyProvider);
    final List<PostingInput> postings = [];

    if (_mode == TransactionMode.advanced) {
      for (var p in _advancedPostings) {
        if (p.accountController.text.isNotEmpty) {
          postings.add(
            PostingInput(
              account: p.accountController.text,
              amount:
                  p.amountController.text.isEmpty
                      ? null
                      : p.amountController.text,
              commodity:
                  p.amountController.text.isEmpty ? null : baseCurrency,
            ),
          );
        }
      }
    } else {
      final amount = _advancedPostings.first.amountController.text;
      postings.add(
        PostingInput(
          account: _primaryAccount!,
          amount: amount,
          commodity: baseCurrency,
        ),
      );
      postings.add(PostingInput(account: _counterAccount!));
    }

    final tags =
        _tagsController.text.split(' ').where((s) => s.isNotEmpty).toList();
    final links =
        _linksController.text.split(' ').where((s) => s.isNotEmpty).toList();
    final Map<String, String> metadata = {};
    for (var m in _metadata) {
      if (m.keyController.text.isNotEmpty) {
        metadata[m.keyController.text] = m.valueController.text;
      }
    }

    final receipt = await ref
        .read(composeTransactionActionControllerProvider.notifier)
        .submit(
          CreateTransactionInput(
            date: _selectedDate,
            flag: _flag,
            payee: _payeeController.text,
            summary: _narrationController.text,
            postings: postings,
            tags: tags,
            links: links,
            metadata: metadata,
          ),
        );

    if (receipt != null && mounted) _popPage(receipt);
  }

  bool get _hasUnsavedChanges {
    return _narrationController.text.isNotEmpty ||
        _payeeController.text.isNotEmpty ||
        (_mode == TransactionMode.advanced && _advancedPostings.length > 2);
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_hasUnsavedChanges) return true;
    final res = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        child,
      ],
    );
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
