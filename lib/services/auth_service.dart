import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'user_profile_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  // Web Client ID từ google-services.json
  static const String serverClientId =
      '968316148144-1fakb6qd0ih48pvhmtutsphqh70k76fd.apps.googleusercontent.com';

  bool _initialized = false;

  /// Khởi tạo Google Sign-In singleton
  Future<void> initialize() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: serverClientId);
    _initialized = true;
  }

  /// Stream theo dõi trạng thái đăng nhập
  Stream<User?> get authStateChanges {
    try {
      return _auth.authStateChanges();
    } catch (_) {
      return const Stream.empty();
    }
  }

  /// Người dùng hiện tại
  User? get currentUser {
    try {
      return _auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  /// 1. Đăng ký tài khoản bằng Email & Mật khẩu
  /// Sau khi tạo tài khoản thành công, tự động tạo hồ sơ Firestore.
  Future<UserCredential> registerWithEmailPassword({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final name = displayName?.trim() ?? '';
      if (name.isNotEmpty) {
        await credential.user?.updateDisplayName(name);
        await credential.user?.reload();
      }

      // Tạo hồ sơ Firestore — lỗi Firestore không rollback Auth
      if (credential.user != null) {
        try {
          await UserProfileService().createProfileForEmailUser(
            uid: credential.user!.uid,
            email: email.trim(),
            displayName: name,
          );
        } catch (firestoreError) {
          // Hồ sơ sẽ được tạo lại khi đăng nhập tiếp theo qua ensureProfileExists
          // ignore: avoid_print
          print(
            '[AuthService] Firestore profile creation failed: $firestoreError',
          );
        }
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _getReadableAuthErrorMessage(e);
    } catch (e) {
      throw 'Đăng ký không thành công: ${e.toString()}';
    }
  }

  /// 2. Đăng nhập bằng Email & Mật khẩu
  /// Sau khi thành công, kiểm tra và phục hồi hồ sơ Firestore nếu thiếu.
  Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // Phục hồi hồ sơ nếu lần đăng ký trước bị lỗi Firestore
      if (credential.user != null) {
        UserProfileService().ensureProfileExists(credential.user!);
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _getReadableAuthErrorMessage(e);
    } catch (e) {
      throw 'Đăng nhập không thành công: ${e.toString()}';
    }
  }

  /// 3. Đăng nhập bằng tài khoản Google (google_sign_in v7+)
  /// Sau khi thành công, upsert hồ sơ Firestore (tạo mới hoặc cập nhật).
  Future<UserCredential?> signInWithGoogle() async {
    try {
      await initialize();

      // Kích hoạt giao diện chọn tài khoản Google
      final GoogleSignInAccount googleUser = await GoogleSignIn.instance
          .authenticate();

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      if (googleAuth.idToken == null) {
        throw 'Không nhận được mã xác thực idToken từ Google.';
      }

      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      // Upsert hồ sơ Firestore — không ghi đè dữ liệu đã tùy chỉnh
      if (userCredential.user != null) {
        final user = userCredential.user!;
        try {
          await UserProfileService().upsertProfileForGoogleUser(
            uid: user.uid,
            email: user.email ?? '',
            googleDisplayName: user.displayName ?? '',
            googlePhotoUrl: user.photoURL,
          );
        } catch (firestoreError) {
          // ignore: avoid_print
          print(
            '[AuthService] Firestore Google upsert failed: $firestoreError',
          );
        }
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _getReadableAuthErrorMessage(e);
    } catch (e) {
      // Nếu người dùng hủy hoặc đóng hộp thoại Google
      if (e.toString().contains('canceled') ||
          e.toString().contains('cancelled')) {
        return null;
      }
      final message = e.toString();
      if (message.contains('DEVELOPER_ERROR') ||
          message.contains('12500') ||
          message.contains('10:')) {
        throw 'Google Sign-In bị từ chối do chữ ký Android chưa khớp cấu hình Firebase OAuth. SHA-1 ứng dụng hiện tại là B2:3A:80:FF:37:59:24:B4:FD:31:79:61:DC:73:27:3F:B7:65:AF:B8.';
      }
      if (message.contains('network_error') || message.contains('7:')) {
        throw 'Không thể kết nối Google. Kiểm tra mạng và thử lại.';
      }
      throw 'Đăng nhập Google thất bại: $message';
    }
  }

  /// 4. Đăng xuất khỏi Firebase và Google
  Future<void> signOut() async {
    try {
      await initialize();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Bỏ qua lỗi nếu GoogleSignIn chưa từng đăng nhập
    }
    await _auth.signOut();
  }

  /// 5. Gửi email đặt lại mật khẩu
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw _getReadableAuthErrorMessage(e);
    } catch (e) {
      throw 'Không thể gửi email đặt lại mật khẩu: ${e.toString()}';
    }
  }

  /// Chuyển đổi mã lỗi Firebase sang tiếng Việt dễ hiểu
  static String _getReadableAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Không tìm thấy tài khoản với email này.';
      case 'wrong-password':
        return 'Mật khẩu không chính xác.';
      case 'invalid-credential':
        return 'Email hoặc mật khẩu không chính xác.';
      case 'email-already-in-use':
        return 'Email này đã được đăng ký trước đó. Vui lòng đăng nhập.';
      case 'invalid-email':
        return 'Địa chỉ email không hợp lệ.';
      case 'weak-password':
        return 'Mật khẩu quá yếu (tối thiểu 6 ký tự).';
      case 'user-disabled':
        return 'Tài khoản này đã bị khóa hoặc vô hiệu hóa.';
      case 'too-many-requests':
        return 'Quá nhiều lần thử thất bại. Vui lòng thử lại sau ít phút.';
      case 'network-request-failed':
        return 'Lỗi kết nối mạng. Vui lòng kiểm tra lại Internet.';
      case 'operation-not-allowed':
        return 'Phương thức đăng nhập này chưa được kích hoạt trên Firebase.';
      default:
        return e.message ?? 'Đã xảy ra lỗi xác thực (${e.code}).';
    }
  }
}
