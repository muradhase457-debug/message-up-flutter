/// App-wide constants.
///
/// SECURITY: the admin allowlist email lives HERE and ONLY here.
/// Every other file must import [kAdminEmail] from this file and must
/// never repeat the literal. It is an allowlist identifier, not a
/// credential — there is no password anywhere in this app.
library;

class AppConstants {
  AppConstants._();

  /// The single admin account (allowlist). Compared case-insensitively
  /// after trimming, in [AdminService]. See lib/services/admin_service.dart.
  static const String kAdminEmail = 'muradhase457@gmail.com';

  static const String appName = 'Message Up';
  static const String appTagline = 'WhatsApp + Messenger + Facebook — one app';

  // Firestore collection names.
  static const String usersCollection = 'users';
  static const String chatsCollection = 'chats';
  static const String messagesCollection = 'messages';
  static const String postsCollection = 'posts';
  static const String statusCollection = 'waStatus';

  // SharedPreferences keys.
  static const String keyThemeDark = 'mu_theme_dark';
  static const String keySpeedMode = 'mu_speed_mode';
  static const String keyGhostMode = 'mu_ghost_mode';
  static const String keyAppLockEnabled = 'mu_app_lock_enabled';
  static const String keyVaultPinHash = 'mu_vault_pin_hash';
  static const String keyPinnedChatIds = 'mu_pinned_chat_ids';
}

/// Backwards-compatible top-level alias so call sites can write
/// `kAdminEmail` without the class prefix.
const String kAdminEmail = AppConstants.kAdminEmail;
