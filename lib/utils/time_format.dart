import 'package:intl/intl.dart';

/// Human-friendly timestamps, WhatsApp-style.
String formatChatTime(DateTime? dt) {
  if (dt == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return DateFormat('h:mm a').format(dt);
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return DateFormat('EEEE').format(dt);
  return DateFormat('dd/MM/yyyy').format(dt);
}

String formatMessageTime(DateTime? dt) {
  if (dt == null) return '';
  return DateFormat('h:mm a').format(dt);
}

String formatFullDate(DateTime? dt) {
  if (dt == null) return '';
  return DateFormat('dd MMM yyyy, h:mm a').format(dt);
}

/// "5m ago", "2h ago", "3d ago" — for feed / status.
String timeAgo(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return DateFormat('dd MMM yyyy').format(dt);
}

/// Remaining time for a 24h status item.
String statusRemaining(DateTime? createdAt) {
  if (createdAt == null) return '';
  final expiry = createdAt.add(const Duration(hours: 24));
  final left = expiry.difference(DateTime.now());
  if (left.isNegative) return 'Expired';
  if (left.inHours >= 1) return '${left.inHours}h left';
  return '${left.inMinutes}m left';
}
