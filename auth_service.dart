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
  Future<void> _upsertProfile(User user) async {
    final ref =
        _firestore.collection(AppConstants.usersCollection).doc(user.uid);
    final existing = await ref.get();
    if (existing.exists) {
      await ref.update(<String, dynamic>{
        'displayName': user.displayName ?? '',
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? '',
        'online': true,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.set(ChatUser(
        uid: user.uid,
        displayName: user.displayName ?? 'Message Up user',
        email: user.email ?? '',
        photoUrl: user.photoURL ?? '',
        online: true,
      ).toMap());
    }
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

  /// Update the signed-in user's display name / about text.
  Future<void> updateProfile({String? displayName, String? about}) async {
    final uid = currentUid;
    if (uid == null) return;
    final updates = <String, dynamic>{};
    if (displayName != null) updates['displayName'] = displayName;
    if (about != null) updates['about'] = about;
    if (updates.isEmpty) return;
    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .update(updates);
  }
}
