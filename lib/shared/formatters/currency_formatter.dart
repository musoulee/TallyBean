String formatAmount(num value, {String symbol = '¥', int fractionDigits = 2}) {
  final absoluteValue = value.abs();
  final fixed = absoluteValue.toStringAsFixed(fractionDigits);
  final parts = fixed.split('.');
  final integerPart = _groupThousands(parts.first);

  final formattedNumber = fractionDigits == 0
      ? integerPart
      : '$integerPart.${parts.last}';
  final sign = value < 0 ? '-' : '';

  return '$sign$symbol $formattedNumber';
}

String _groupThousands(String digits) {
  final buffer = StringBuffer();

  for (var index = 0; index < digits.length; index++) {
    final remaining = digits.length - index;
    buffer.write(digits[index]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }

  return buffer.toString();
}
