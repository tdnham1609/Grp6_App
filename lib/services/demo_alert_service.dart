import 'package:cloud_functions/cloud_functions.dart';

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
  final FirebaseFunctions _functions;

  DemoAlertService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  Future<DemoAlertResult> sendDemoAlert() async {
    final callable = _functions.httpsCallable(
      'sendDemoAlert',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );
    final response = await callable.call<Map<String, dynamic>>({});
    return DemoAlertResult.fromMap(response.data);
  }
}
