import 'create_transaction_input.dart';

String serializeTransactionInput(CreateTransactionInput input) {
  final date = _formatDate(input.date);
  final flag = input.flag;
  final escapedPayee = _escapeString(input.payee ?? '');
  final payeeStr = escapedPayee.isNotEmpty ? '"$escapedPayee" ' : '';
  final summaryStr = '"${_escapeString(input.summary)}"';
  final tagsStr = input.tags.isEmpty
      ? ''
      : ' ${input.tags.map((e) => '#$e').join(' ')}';
  final linksStr = input.links.isEmpty
      ? ''
      : ' ${input.links.map((e) => '^$e').join(' ')}';

  final buffer = StringBuffer();
  buffer.writeln('$date $flag $payeeStr$summaryStr$tagsStr$linksStr');

  for (final meta in input.metadata.entries) {
    buffer.writeln('  ${meta.key}: "${_escapeString(meta.value)}"');
  }

  for (final posting in _postingsWithExplicitAutoBalance(input.postings)) {
    final amount = posting.amount;
    final commodity = posting.commodity;
    // 使用至少两个空格分隔账户和金额，符合 Beancount 推荐风格
    final amountPart = (amount != null && amount.isNotEmpty)
        ? '  $amount ${commodity ?? ''}'
        : '';
    buffer.writeln('  ${posting.account}$amountPart');
  }

  return buffer.toString();
}

String _escapeString(String s) {
  return s.replaceAll('"', '\\"');
}

List<PostingInput> _postingsWithExplicitAutoBalance(
  List<PostingInput> postings,
) {
  final missingPostings = postings
      .where((posting) => posting.amount == null || posting.amount!.isEmpty)
      .toList(growable: false);
  if (missingPostings.length != 1) {
    return postings;
  }

  String? commodity;
  var scale = 0;
  var totalUnits = BigInt.zero;
  for (final posting in postings) {
    final amount = posting.amount;
    if (amount == null || amount.isEmpty) {
      continue;
    }
    final parsedAmount = _parseScaledAmount(amount);
    final postingCommodity = posting.commodity;
    if (parsedAmount == null ||
        postingCommodity == null ||
        postingCommodity.isEmpty) {
      return postings;
    }
    commodity ??= postingCommodity;
    if (commodity != postingCommodity) {
      return postings;
    }
    if (parsedAmount.scale > scale) {
      totalUnits *= BigInt.from(10).pow(parsedAmount.scale - scale);
      scale = parsedAmount.scale;
    }
    totalUnits +=
        parsedAmount.units * BigInt.from(10).pow(scale - parsedAmount.scale);
  }
  if (commodity == null) {
    return postings;
  }

  final missingPosting = missingPostings.single;
  return postings
      .map(
        (posting) => identical(posting, missingPosting)
            ? PostingInput(
                account: posting.account,
                amount: _formatScaledAmount(
                  _ScaledAmount(units: -totalUnits, scale: scale),
                ),
                commodity: commodity,
              )
            : posting,
      )
      .toList(growable: false);
}

_ScaledAmount? _parseScaledAmount(String input) {
  final normalized = input.trim();
  final match = RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?$').firstMatch(normalized);
  if (match == null) {
    return null;
  }

  final sign = match.group(1) == '-' ? BigInt.from(-1) : BigInt.one;
  final whole = BigInt.parse(match.group(2)!);
  final fraction = match.group(3) ?? '';
  final scale = fraction.length;
  final fractionUnits = fraction.isEmpty ? BigInt.zero : BigInt.parse(fraction);
  final units = (whole * BigInt.from(10).pow(scale) + fractionUnits) * sign;
  return _ScaledAmount(units: units, scale: scale);
}

String _formatScaledAmount(_ScaledAmount amount) {
  final isNegative = amount.units.isNegative;
  final absolute = isNegative ? -amount.units : amount.units;
  final scaleFactor = BigInt.from(10).pow(amount.scale);
  final whole = absolute ~/ scaleFactor;
  final fraction = (absolute % scaleFactor).toString().padLeft(
    amount.scale,
    '0',
  );
  final sign = isNegative && absolute != BigInt.zero ? '-' : '';
  if (amount.scale == 0) {
    return '$sign$whole';
  }
  return '$sign$whole.$fraction';
}

class _ScaledAmount {
  const _ScaledAmount({required this.units, required this.scale});

  final BigInt units;
  final int scale;
}

String _formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
