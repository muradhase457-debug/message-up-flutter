/// Small input validators. Pure functions — no I/O, no secrets.
bool isValidEmail(String value) {
  final v = value.trim();
  if (v.isEmpty) return false;
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
}

bool isValidDisplayName(String value) {
  final v = value.trim();
  return v.length >= 2 && v.length <= 40;
}

bool isValidMessageText(String value) {
  final v = value.trim();
  return v.isNotEmpty && v.length <= 5000;
}

bool isValidPin(String value) {
  return RegExp(r'^\d{4,6}$').hasMatch(value.trim());
}

String? validateMessageText(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Message cannot be empty';
  }
  if (value.trim().length > 5000) return 'Message is too long';
  return null;
}

String? validateDisplayName(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Name cannot be empty';
  }
  if (value.trim().length < 2) return 'Name is too short';
  return null;
}
