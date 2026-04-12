class ValidationIssue {
  const ValidationIssue({
    required this.message,
    required this.location,
    required this.blocking,
  });

  final String message;
  final String location;
  final bool blocking;
}
