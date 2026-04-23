class PostingInput {
  const PostingInput({
    required this.account,
    this.amount,
    this.commodity,
  });

  final String account;
  final String? amount;
  final String? commodity;
}

class CreateTransactionInput {
  const CreateTransactionInput({
    required this.date,
    required this.summary,
    required this.postings,
    this.flag = '*',
    this.payee,
    this.tags = const [],
    this.links = const [],
    this.metadata = const {},
  });

  final DateTime date;
  final String summary;
  final List<PostingInput> postings;
  final String flag;
  final String? payee;
  final List<String> tags;
  final List<String> links;
  final Map<String, String> metadata;
}
