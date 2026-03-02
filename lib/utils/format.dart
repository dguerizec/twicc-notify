/// Format a byte count into a human-readable string.
///
/// Examples: "0 B", "512 B", "1.2 KB", "3.4 MB".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Format a number with thousand separators.
///
/// Examples: "42", "1,234", "12,345,678".
String formatNumber(int n) {
  if (n < 0) return '-${formatNumber(-n)}';
  if (n < 1000) return '$n';

  final str = n.toString();
  final buffer = StringBuffer();
  final remainder = str.length % 3;

  if (remainder > 0) {
    buffer.write(str.substring(0, remainder));
    if (str.length > remainder) buffer.write(',');
  }

  for (var i = remainder; i < str.length; i += 3) {
    buffer.write(str.substring(i, i + 3));
    if (i + 3 < str.length) buffer.write(',');
  }

  return buffer.toString();
}
