import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:message_up/models/user_model.dart';
import 'package:message_up/utils/constants.dart';

/// Google Sign-In + Firebase Auth wrapper.
///
/// No passwords anywhere: sign-in is Google only. The user profile is
/// mirrored into the `users` collection so chats can resolve names/photos.
class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  /// Emits the current Firebase user (null when signed out).
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  String? get currentUid => _auth.currentUser?.uid;

  /// Live profile document of the signed-in user, if one exists.
  Stream<ChatUser?> currentProfileStream() {
    final uid = currentUid;
    if (uid == null) return Stream.value(null);
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .snapshots()
        .map((doc) =>
            doc.exists ? ChatUser.fromDoc(doc) : null);
  }

  /// Sign in with Google. Returns the Firebase user on success.
  Future<User?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // user cancelled the picker
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final result = await _auth.signInWithCredential(credential);
    final user = result.user;
    if (user != null) {
      await _upsertProfile(user);
    }
    return user;
  }

  /// Sign out from Firebase + Google.
  Future<void> signOut() async {
    await _setOnline(false);
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  /// Create / update the `users/{uid}` profile after sign-in.
  ///
  /// A name / photo the user already set (in this app or on the website)
  /// is NEVER overwritten by an empty Google value: only blank fields
  /// are filled in. Online + lastSeen are always refreshed.
  Future<void> _upsertProfile(User user) async {
    final ref =
        _firestore.collection(AppConstants.usersCollection).doc(user.uid);
    final existing = await ref.get();
    if (existing.exists) {
      final data = existing.data() ?? <String, dynamic>{};
      final oldName = _firstString(data, const ['displayName', 'name']);
      final oldPhoto = _firstString(
          data, const ['photoUrl', 'photoURL', 'photo', 'avatar']);
      final googleName = (user.displayName ?? '').trim();
      final googlePhoto = user.photoURL ?? '';
      final updates = <String, dynamic>{
        'email': user.email ?? '',
        'online': true,
        'lastSeen': FieldValue.serverTimestamp(),
      };
      // Fill blanks only — never wipe a name/photo the user already has.
      if (oldName.isEmpty && googleName.isNotEmpty) {
        updates['displayName'] = googleName;
      }
      if (oldPhoto.isEmpty && googlePhoto.isNotEmpty) {
        updates['photoUrl'] = googlePhoto;
      }
      await ref.update(updates);
    } else {
      await ref.set(ChatUser(
        uid: user.uid,
        displayName: (user.displayName ?? '').trim().isEmpty
            ? 'Message Up user'
            : user.displayName!,
        email: user.email ?? '',
        photoUrl: user.photoURL ?? '',
        online: true,
      ).toMap());
    }
  }

  static String _firstString(
      Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return '';
  }

  Future<void> _setOnline(bool online) async {
    final uid = currentUid;
    if (uid == null) return;
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update(<String, dynamic>{
        'online': online,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best effort — sign-out must not fail because of presence.
    }
  }

  /// Update the signed-in user's display name / about text / photo.
  Future<void> updateProfile({
    String? displayName,
    String? about,
    String? photoUrl,
  }) async {
    final uid = currentUid;
    if (uid == null) return;
    final updates = <String, dynamic>{};
    if (displayName != null) updates['displayName'] = displayName;
    if (about != null) updates['about'] = about;
    if (photoUrl != null) updates['photoUrl'] = photoUrl;
    if (updates.isEmpty) return;
    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .update(updates);
  }
}
