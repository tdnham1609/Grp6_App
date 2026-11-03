import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

class DemoAlertResult {
  final int sentCount;
  final int failedCount;
  final int totalCount;

  const DemoAlertResult({
    required this.sentCount,
    required this.failedCount,
    required this.totalCount,
  });

  factory DemoAlertResult.fromMap(Map<String, dynamic> data) {
    return DemoAlertResult(
      sentCount: data['sentCount'] as int? ?? 0,
      failedCount: data['failedCount'] as int? ?? 0,
      totalCount: data['totalCount'] as int? ?? 0,
    );
  }
}

class DemoAlertService {
  final FirebaseFunctions? _providedFunctions;

  DemoAlertService({FirebaseFunctions? functions})
    : _providedFunctions = functions;

  FirebaseFunctions get _functions {
    if (_providedFunctions != null) return _providedFunctions;
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase chưa được khởi tạo.');
    }
    return FirebaseFunctions.instance;
  }

  Future<DemoAlertResult> sendDemoAlert() async {
    final callable = _functions.httpsCallable(
      'sendDemoAlert',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );
    final response = await callable.call<Map<String, dynamic>>({});
    return DemoAlertResult.fromMap(response.data);
  }
}
