import 'package:quds_tasks_graph/quds_tasks_graph_native.dart';
import 'package:test/test.dart';

void main() {
  test(
    'native transport rejects a conflicting Host header before dispatch',
    () async {
      final transport = NativeGraphTaskHttpTransport();
      try {
        await expectLater(
          transport.send(
            GraphTaskHttpRequest(
              method: 'GET',
              uri: Uri.parse('https://graph.microsoft.com/v1.0/me/todo/lists'),
              headers: {'Host': 'other.invalid'},
            ),
            timeout: const Duration(seconds: 1),
            maxResponseBytes: 1024,
          ),
          throwsA(
            isA<GraphTaskTransportException>()
                .having(
                  (error) => error.problem,
                  'problem',
                  GraphTaskTransportProblem.invalidRequest,
                )
                .having(
                  (error) => error.requestMayHaveReachedServer,
                  'requestMayHaveReachedServer',
                  isFalse,
                ),
          ),
        );
      } finally {
        transport.close();
      }
    },
  );

  test('native transport only accepts global Graph To Do HTTPS paths', () {
    expect(
      NativeGraphTaskHttpTransport.allowedUri(
        Uri.parse('https://graph.microsoft.com/v1.0/me/todo/lists/list/tasks'),
      ),
      isTrue,
    );
    for (final url in [
      'http://graph.microsoft.com/v1.0/me/todo/lists',
      'https://graph.microsoft.com.evil.invalid/v1.0/me/todo/lists',
      'https://token@graph.microsoft.com/v1.0/me/todo/lists',
      'https://graph.microsoft.com:444/v1.0/me/todo/lists',
      'https://graph.microsoft.com/v1.0/me/messages',
      'https://graph.microsoft.com/beta/me/todo/lists',
      'https://graph.microsoft.com/v1.0/me/todo/lists#fragment',
    ]) {
      expect(
        NativeGraphTaskHttpTransport.allowedUri(Uri.parse(url)),
        isFalse,
        reason: url,
      );
    }
  });

  test(
    'closed native transport rejects before transmitting any request',
    () async {
      final transport = NativeGraphTaskHttpTransport()..close();
      await expectLater(
        transport.send(
          GraphTaskHttpRequest(
            method: 'GET',
            uri: Uri.parse('https://graph.microsoft.com/v1.0/me/todo/lists'),
          ),
          timeout: const Duration(seconds: 1),
          maxResponseBytes: 1024,
        ),
        throwsA(
          isA<GraphTaskTransportException>().having(
            (error) => error.requestMayHaveReachedServer,
            'requestMayHaveReachedServer',
            isFalse,
          ),
        ),
      );
    },
  );
}
