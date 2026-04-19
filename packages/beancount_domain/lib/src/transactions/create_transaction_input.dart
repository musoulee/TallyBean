class CreateTransactionInput {
  const CreateTransactionInput({
    required this.date,
    required this.summary,
    required this.amount,
    required this.commodity,
    required this.primaryAccount,
    required this.counterAccount,
  });

  final DateTime date;
  final String summary;
  final String amount;
  final String commodity;
  final String primaryAccount;
  final String counterAccount;
}
