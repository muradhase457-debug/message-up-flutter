import 'package:firebase_auth/firebase_auth.dart';
import 'package:message_up/utils/constants.dart';

/// Admin gate — synchronous, no Firestore dependency, no password.
///
/// The admin panel is reachable ONLY when the signed-in user's email
/// (lowercased + trimmed) equals the single allowlist constant defined
/// in [AppConstants.kAdminEmail] (lib/utils/constants.dart).
/// The admin screen itself double-checks this before rendering anything.
class AdminService {
  AdminService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// True only for the allowlisted admin account.
  bool get isAdmin {
    final email = _auth.currentUser?.email;
    if (email == null) return false;
    return email.trim().toLowerCase() ==
        AppConstants.kAdminEmail.toLowerCase();
  }

  /// Static helper for places that already have an email string.
  static bool isAdminEmail(String? email) {
    if (email == null) return false;
    return email.trim().toLowerCase() ==
        AppConstants.kAdminEmail.toLowerCase();
  }

  /// The signed-in user's email, or null when signed out.
  String? get currentEmail => _auth.currentUser?.email;
}
