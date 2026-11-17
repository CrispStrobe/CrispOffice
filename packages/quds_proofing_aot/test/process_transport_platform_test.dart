import 'package:quds_proofing_aot/quds_proofing_aot.dart';
import 'package:test/test.dart';

void main() {
  test('process configuration rejects invalid bounds and command values', () {
    expect(() => AotProcessTransport(executable: ''), throwsArgumentError);
    expect(
      () => AotProcessTransport(executable: 'bad\u0000path'),
      throwsArgumentError,
    );
    expect(() => AotProcessTransport(rmlDirectory: ''), throwsArgumentError);
    expect(
      () => AotProcessTransport(timeout: Duration.zero),
      throwsArgumentError,
    );
    expect(
      () => AotProcessTransport(maximumPendingRequests: 33),
      throwsArgumentError,
    );
    expect(
      () => AotProcessTransport(maximumStderrBytes: 0),
      throwsArgumentError,
    );
    expect(
      () => AotProcessTransport(
        environment: <String, String>{'bad=key': 'value'},
      ),
      throwsArgumentError,
    );
  });

  if (!AotProcessTransport.isSupported) {
    test('web reports unavailable without creating an HTTP fallback', () async {
      final AotProcessTransport worker = AotProcessTransport();
      await expectLater(
        worker.request(
          action: 'syntax',
          language: AotLanguage.german,
          query: 'Ich gehe.',
        ),
        throwsA(
          isA<AotException>().having(
            (AotException error) => error.code,
            'code',
            AotErrorCode.unavailable,
          ),
        ),
      );
      await worker.dispose();
      await expectLater(
        worker.request(
          action: 'syntax',
          language: AotLanguage.german,
          query: 'Ich gehe.',
        ),
        throwsA(
          isA<AotException>().having(
            (AotException error) => error.code,
            'code',
            AotErrorCode.disposed,
          ),
        ),
      );
    });
  }
}
