import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/app/di/app_providers.dart';
import 'package:tally_bean/features/compose_transaction/application/compose_transaction_providers.dart';
import 'package:tally_bean/features/settings/application/settings_providers.dart';
import 'package:tally_bean/features/workspace/application/workspace_providers.dart';
import 'package:tally_bean/shared/widgets/async_error_view.dart';
import 'package:tally_bean/shared/widgets/async_loading_view.dart';
import 'package:tally_bean/shared/widgets/workspace_gate_view.dart';

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
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  String? _primaryAccount;
  String? _counterAccount;

  @override
  void initState() {
    super.initState();
    _summaryController = TextEditingController();
    _amountController = TextEditingController();
    _commodityController = TextEditingController(
      text: ref.read(settingsBaseCurrencyProvider),
    );
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
    final workspaceState = ref.watch(currentWorkspaceProvider);
    final workspace = workspaceState.asData?.value;
    final title = ref.watch(composeTransactionTitleProvider);
    final submitState = ref.watch(composeTransactionActionControllerProvider);
    final accountOptionsState = ref.watch(
      composeTransactionAccountOptionsProvider,
    );
    final isDemoMode = ref.watch(appConfigProvider).useDemoData;
    final summaryErrorText = _summaryValidationMessage(
      _summaryController.text.trim(),
    );

    if (workspaceState.hasError && workspace == null) {
      return Scaffold(
        body: AsyncErrorView(
          error: workspaceState.error!,
          message: '工作区加载失败',
          onRetry: () => ref.invalidate(currentWorkspaceProvider),
        ),
      );
    }
    if (workspaceState.isLoading) {
      return const Scaffold(body: AsyncLoadingView());
    }
    if (workspace == null) {
      return const Scaffold(
        body: WorkspaceGateView(title: '还没有账本', message: '导入工作区后才能开始录入交易。'),
      );
    }
    if (workspace.status == WorkspaceStatus.issuesFirst) {
      return const Scaffold(
        body: WorkspaceGateView(
          title: '录入已锁定',
          message: '当前账本存在阻塞性问题，请先前往工作区处理 issues。',
        ),
      );
    }

    final canSubmit =
        !isDemoMode &&
        !submitState.isLoading &&
        _isFormValid(accountOptionsState.hasValue);

    return Scaffold(
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
                    border: OutlineInputBorder(),
                    errorText: summaryErrorText,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('compose-amount-field'),
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '金额',
                    border: OutlineInputBorder(),
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
    required ValueChanged<String> onSelected,
  }) async {
    final options = accountOptionsState.asData?.value;
    if (options == null || options.isEmpty) {
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final option = options[index];
              return ListTile(
                title: Text(option.fullPath),
                onTap: () => Navigator.of(ctx).pop(option.fullPath),
              );
            },
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
    final success = await ref
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
    if (!success || !mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('交易已保存')));
    Navigator.of(context).pop();
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
