import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/app/di/app_providers.dart';
import 'package:tally_bean/app/session/quick_entry_session.dart';
import 'package:tally_bean/features/compose_transaction/application/compose_transaction_providers.dart';
import 'package:tally_bean/features/settings/application/settings_providers.dart';
import 'package:tally_bean/features/ledger/application/ledger_providers.dart';
import 'package:tally_bean/shared/widgets/async_error_view.dart';
import 'package:tally_bean/shared/widgets/async_loading_view.dart';
import 'package:tally_bean/shared/widgets/ledger_gate_view.dart';

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

  late final TextEditingController _summaryController;
  late final TextEditingController _amountController;
  late final TextEditingController _commodityController;
  late final DateTime _initialDate;
  late final String _initialCommodity;
  late DateTime _selectedDate;
  String? _primaryAccount;
  String? _counterAccount;
  bool _allowImmediatePop = false;

  @override
  void initState() {
    super.initState();
    _initialDate = DateUtils.dateOnly(DateTime.now());
    _selectedDate = _initialDate;
    _initialCommodity = ref.read(settingsBaseCurrencyProvider);
    _summaryController = TextEditingController();
    _amountController = TextEditingController();
    _commodityController = TextEditingController(text: _initialCommodity);
    _summaryController.addListener(_handleDraftChanged);
    _amountController.addListener(_handleDraftChanged);
    _commodityController.addListener(_handleDraftChanged);
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _amountController.dispose();
    _commodityController.dispose();
    super.dispose();
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
    final summaryErrorText = _summaryValidationMessage(
      _summaryController.text.trim(),
    );

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
        if (didPop) {
          return;
        }
        final shouldPop = await _confirmDiscardIfNeeded();
        if (!shouldPop || !mounted) {
          return;
        }
        setState(() {
          _allowImmediatePop = true;
        });
        _popPage();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (isDemoMode) ...[
              const _ReadOnlyNotice(message: '演示数据模式当前为只读，不能保存新交易。'),
              const SizedBox(height: 16),
            ],
            TallySectionCard(
              title: '交易草稿',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldLabel(
                    label: '日期',
                    child: OutlinedButton.icon(
                      key: const Key('compose-date-field'),
                      onPressed: submitState.isLoading ? null : _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(_formatDisplayDate(_selectedDate)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('compose-summary-field'),
                    controller: _summaryController,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: '摘要',
                      border: const OutlineInputBorder(),
                      errorText: summaryErrorText,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.36),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          key: const Key('compose-amount-field'),
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.next,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                          decoration: const InputDecoration(
                            labelText: '金额',
                            prefixIcon: Icon(Icons.payments_outlined),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '优先为日常支出做快录，也兼容收入与转账。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('compose-commodity-field'),
                    controller: _commodityController,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: '币种',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (recentPairs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      '最近使用组合',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var index = 0; index < recentPairs.length; index++)
                          ActionChip(
                            key: Key('compose-recent-pair-chip-$index'),
                            avatar: const Icon(Icons.history, size: 18),
                            label: Text(recentPairs[index].label),
                            onPressed: submitState.isLoading
                                ? null
                                : () {
                                    setState(() {
                                      _primaryAccount =
                                          recentPairs[index].primaryAccount;
                                      _counterAccount =
                                          recentPairs[index].counterAccount;
                                    });
                                    _handleDraftChanged();
                                  },
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  _FieldLabel(
                    label: '记到账户',
                    child: _AccountPickerButton(
                      fieldKey: const Key('compose-primary-account-field'),
                      value: _primaryAccount,
                      placeholder: _accountPlaceholder(accountOptionsState),
                      onTap: submitState.isLoading
                          ? null
                          : () => _selectAccount(
                              context: context,
                              accountOptionsState: accountOptionsState,
                              recentAccounts: recentPrimaryAccounts,
                              onSelected: (value) {
                                setState(() {
                                  _primaryAccount = value;
                                });
                                _handleDraftChanged();
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FieldLabel(
                    label: '对方账户',
                    child: _AccountPickerButton(
                      fieldKey: const Key('compose-counter-account-field'),
                      value: _counterAccount,
                      placeholder: _accountPlaceholder(accountOptionsState),
                      onTap: submitState.isLoading
                          ? null
                          : () => _selectAccount(
                              context: context,
                              accountOptionsState: accountOptionsState,
                              recentAccounts: recentCounterAccounts,
                              onSelected: (value) {
                                setState(() {
                                  _counterAccount = value;
                                });
                                _handleDraftChanged();
                              },
                            ),
                    ),
                  ),
                  if (accountOptionsState.hasError) ...[
                    const SizedBox(height: 12),
                    Text(
                      '账户加载失败: ${accountOptionsState.error}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (submitState.hasError) ...[
                    const SizedBox(height: 12),
                    Text(
                      '保存失败: ${submitState.error}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('compose-submit-button'),
                      onPressed: canSubmit ? _submit : null,
                      child: submitState.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('保存'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleDraftChanged() {
    ref.read(composeTransactionActionControllerProvider.notifier).clearError();
    if (mounted) {
      setState(() {});
    }
  }

  bool _isFormValid(bool accountOptionsLoaded) {
    final summary = _summaryController.text.trim();
    final amount = _parsePositiveAmount(_amountController.text.trim());
    final commodity = _commodityController.text.trim();
    return accountOptionsLoaded &&
        summary.isNotEmpty &&
        _summaryValidationMessage(summary) == null &&
        amount != null &&
        commodity.isNotEmpty &&
        _primaryAccount != null &&
        _counterAccount != null &&
        _primaryAccount != _counterAccount;
  }

  String? _summaryValidationMessage(String summary) {
    if (summary.contains('"')) {
      return _unsupportedSummaryQuoteMessage;
    }
    return null;
  }

  String _accountPlaceholder(AsyncValue<List<ComposeAccountOption>> state) {
    if (state.isLoading) {
      return '账户加载中';
    }
    if (state.hasError) {
      return '账户加载失败';
    }
    return '选择账户';
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (selected == null) {
      return;
    }
    setState(() {
      _selectedDate = DateUtils.dateOnly(selected);
    });
    _handleDraftChanged();
  }

  Future<void> _selectAccount({
    required BuildContext context,
    required AsyncValue<List<ComposeAccountOption>> accountOptionsState,
    required List<String> recentAccounts,
    required ValueChanged<String> onSelected,
  }) async {
    final options = accountOptionsState.asData?.value;
    if (options == null || options.isEmpty) {
      return;
    }
    final allPaths = options.map((option) => option.fullPath).toList();
    final recentChoices = recentAccounts
        .where((path) => allPaths.contains(path))
        .toList(growable: false);
    final remainingChoices = allPaths
        .where((path) => !recentChoices.contains(path))
        .toList(growable: false);

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
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
                    onTap: () => Navigator.of(ctx).pop(remainingChoices[index]),
                  ),
                  if (index != remainingChoices.length - 1)
                    const Divider(height: 1),
                ],
              ],
            ],
          ),
        );
      },
    );

    if (selected != null) {
      onSelected(selected);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final receipt = await ref
        .read(composeTransactionActionControllerProvider.notifier)
        .submit(
          CreateTransactionInput(
            date: _selectedDate,
            summary: _summaryController.text.trim(),
            amount: _amountController.text.trim(),
            commodity: _commodityController.text.trim(),
            primaryAccount: _primaryAccount!,
            counterAccount: _counterAccount!,
          ),
        );
    if (receipt == null || !mounted) {
      return;
    }

    _popPage(receipt);
  }

  bool get _hasUnsavedChanges {
    return _summaryController.text.trim().isNotEmpty ||
        _amountController.text.trim().isNotEmpty ||
        _commodityController.text.trim() != _initialCommodity ||
        _primaryAccount != null ||
        _counterAccount != null ||
        !_isSameDate(_selectedDate, _initialDate);
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    final submitState = ref.read(composeTransactionActionControllerProvider);
    if (submitState.isLoading) {
      return false;
    }
    if (!_hasUnsavedChanges) {
      return true;
    }

    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('放弃这次录入？'),
          content: const Text('当前表单还有未保存内容，返回后这些输入会丢失。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('保留内容'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('放弃'),
            ),
          ],
        );
      },
    );
    return shouldDiscard ?? false;
  }

  num? _parsePositiveAmount(String input) {
    if (input.isEmpty || !_positiveDecimalAmountPattern.hasMatch(input)) {
      return null;
    }
    final parsed = num.tryParse(input);
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  String _formatDisplayDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  void _popPage([Object? result]) {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator.canPop()) {
      rootNavigator.pop(result);
      return;
    }
    Navigator.of(context).pop(result);
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
    required this.fieldKey,
    required this.value,
    required this.placeholder,
    required this.onTap,
  });

  final Key fieldKey;
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
          child: Text(value ?? placeholder),
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
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: colors.onSecondaryContainer),
      ),
    );
  }
}
