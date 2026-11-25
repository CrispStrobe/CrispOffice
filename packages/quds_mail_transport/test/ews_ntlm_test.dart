import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/src/ews/errors.dart';
import 'package:quds_mail_transport/src/ews/native/ntlm.dart';
import 'package:test/test.dart';

// MS-NLMP 4.2.4's published challenge and independently published NTLMv2 result.
// https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-nlmp/bc612491-fb0b-4829-91bc-7c6b95ff67fe
final _publishedChallenge = _hex(
  '4e544c4d53535000020000000c000c003800000033828ae2'
  '0123456789abcdef00000000000000002400240044000000'
  '060070170000000f530065007200760065007200'
  '02000c0044006f006d00610069006e00'
  '01000c0053006500720076006500720000000000',
);

Uint8List _hex(String value) => Uint8List.fromList([
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
]);

String _toHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Uint8List _field(Uint8List message, int offset) {
  final data = ByteData.sublistView(message);
  final start = data.getUint32(offset + 4, Endian.little);
  return Uint8List.sublistView(
    message,
    start,
    start + data.getUint16(offset, Endian.little),
  );
}

Uint8List _authenticate({
  Uint8List? challenge,
  String username = 'User',
  String domain = 'Domain',
}) => createNtlmAuthenticateMessage(
  negotiate: createNtlmNegotiateMessage(),
  challenge: challenge ?? _publishedChallenge,
  username: username,
  domain: domain,
  password: 'Password',
  workstation: 'COMPUTER',
  channelBinding: Uint8List.fromList(List<int>.filled(16, 0xab)),
  targetName: 'HTTP/exchange.example.test',
  clientChallenge: _hex('aaaaaaaaaaaaaaaa'),
  now: DateTime.utc(2026, 11, 19),
);

Uint8List _certificateDer() {
  for (final prefix in [
    'test/fixtures/tls',
    'packages/quds_mail_transport/test/fixtures/tls',
  ]) {
    final file = File('$prefix/loopback-cert.pem');
    if (file.existsSync()) {
      return base64.decode(
        file.readAsStringSync().replaceAll(RegExp(r'-----[^-]+-----|\s'), ''),
      );
    }
  }
  throw StateError('Public test certificate is missing.');
}

void main() {
  test('NTLMv2 proof and session key match MS-NLMP 4.2.4 vectors', () {
    final result = computeNtlmV2Response(
      username: 'User',
      domain: 'Domain',
      password: 'Password',
      serverChallenge: _hex('0123456789abcdef'),
      clientChallenge: _hex('aaaaaaaaaaaaaaaa'),
      timestamp: Uint8List(8),
      targetInfo: Uint8List.sublistView(_publishedChallenge, 68),
    );
    expect(
      _toHex(result.ntResponse.sublist(0, 16)),
      '68cd0ab851e51c96aabc927bebef6a1c',
    );
    expect(_toHex(result.sessionBaseKey), '8de40ccadbc14a82f15cb0ad0de95ca3');
  });

  test(
    'Type 3 binds the TLS channel and SPN and authenticates all three messages',
    () {
      final message = _authenticate();
      final data = ByteData.sublistView(message);
      final flags = data.getUint32(60, Endian.little);
      expect(flags & 0x40000030, 0); // No unnegotiated key exchange/sign/seal.
      expect(
        _field(message, 12),
        List<int>.filled(24, 0),
      ); // No LM/v1 response.
      expect(_field(message, 52), isEmpty);
      final nt = _field(message, 20);
      final info = ByteData.sublistView(nt);
      var at = 16 + 28;
      final pairs = <int, Uint8List>{};
      while (info.getUint16(at, Endian.little) != 0) {
        final id = info.getUint16(at, Endian.little);
        final length = info.getUint16(at + 2, Endian.little);
        pairs[id] = Uint8List.sublistView(nt, at + 4, at + 4 + length);
        at += 4 + length;
      }
      expect(
        ByteData.sublistView(pairs[6]!).getUint32(0, Endian.little) & 2,
        2,
      );
      expect(pairs[10], List<int>.filled(16, 0xab));
      final spn = pairs[9]!;
      expect(
        String.fromCharCodes([
          for (var i = 0; i < spn.length; i += 2) spn[i] | (spn[i + 1] << 8),
        ]),
        'HTTP/exchange.example.test',
      );
      final responseKey = _hex('0c868a403bfd7a93a3001ef22ef02e3f');
      final key = Hmac(md5, responseKey).convert(nt.sublist(0, 16)).bytes;
      final zeroMic = Uint8List.fromList(message)..fillRange(72, 88, 0);
      final expectedMic = Hmac(md5, key).convert([
        ...createNtlmNegotiateMessage(),
        ..._publishedChallenge,
        ...zeroMic,
      ]).bytes;
      expect(message.sublist(72, 88), expectedMic);
    },
  );

  test('server timestamp takes precedence over the workstation clock', () {
    final challenge = Uint8List.fromList([
      ..._publishedChallenge.sublist(0, _publishedChallenge.length - 4),
      7,
      0,
      8,
      0,
      ..._hex('0011223344556601'),
      0,
      0,
      0,
      0,
    ]);
    final data = ByteData.sublistView(challenge);
    data.setUint16(40, 48, Endian.little);
    data.setUint16(42, 48, Endian.little);
    expect(
      _field(_authenticate(challenge: challenge), 20).sublist(24, 32),
      _hex('0011223344556601'),
    );
  });

  test('DOMAIN\\user and separate domain generate the same identity proof', () {
    expect(
      _authenticate(username: r'Domain\User', domain: ''),
      _authenticate(),
    );
    expect(
      () => _authenticate(username: r'Other\User'),
      throwsA(
        isA<EwsException>().having(
          (e) => e.code,
          'code',
          MailProblemCode.invalidInput,
        ),
      ),
    );
  });

  test(
    'TLS channel binding matches independently calculated certificate digest',
    () {
      // Python hashlib MD5(16 zero bytes + LE32(len(data)) + data), where data
      // is ASCII tls-server-end-point: followed by SHA256 of the DER fixture.
      expect(
        _toHex(tlsServerEndPointChannelBinding(_certificateDer())),
        'aef9a42a3ffa0ce195f2f645e86dda84',
      );
    },
  );

  test('weak challenge flags never trigger an NTLMv1 fallback', () {
    final challenge = Uint8List.fromList(_publishedChallenge);
    ByteData.sublistView(challenge).setUint32(20, 0x201, Endian.little);
    expect(
      () => _authenticate(challenge: challenge),
      throwsA(
        isA<EwsException>().having(
          (e) => e.code,
          'code',
          MailProblemCode.unsupported,
        ),
      ),
    );
  });

  test('extended SingleHost target information preserves reserved bytes', () {
    final singleHost = Uint8List(80)..fillRange(0, 80, 0xcc);
    ByteData.sublistView(singleHost).setUint32(0, 80, Endian.little);
    final challenge = Uint8List.fromList([
      ..._publishedChallenge.sublist(0, _publishedChallenge.length - 4),
      8,
      0,
      80,
      0,
      ...singleHost,
      0,
      0,
      0,
      0,
    ]);
    final data = ByteData.sublistView(challenge);
    data.setUint16(40, 120, Endian.little);
    data.setUint16(42, 120, Endian.little);
    final response = _field(_authenticate(challenge: challenge), 20);
    final info = ByteData.sublistView(response);
    var at = 44;
    while (info.getUint16(at, Endian.little) != 8) {
      at += 4 + info.getUint16(at + 2, Endian.little);
    }
    expect(info.getUint16(at + 2, Endian.little), 80);
    expect(response.sublist(at + 4, at + 84), singleHost);
  });

  for (final scenario in [
    'truncated',
    'offset overflow',
    'unterminated',
    'duplicate AV',
  ]) {
    test('malformed $scenario challenge fails without retaining input', () {
      var challenge = Uint8List.fromList(_publishedChallenge);
      switch (scenario) {
        case 'truncated':
          challenge = Uint8List.sublistView(challenge, 0, 20);
        case 'offset overflow':
          ByteData.sublistView(
            challenge,
          ).setUint32(44, 0xffffffff, Endian.little);
        case 'unterminated':
          challenge[challenge.length - 4] = 1;
        case 'duplicate AV':
          challenge[84] = 2;
      }
      expect(
        () => _authenticate(challenge: challenge),
        throwsA(isA<EwsException>()),
      );
    });
  }

  test('certificate ASN.1 bounds reject malformed encodings', () {
    for (final der in [
      Uint8List(0),
      _hex('3084ffffffff'),
      _hex('300430820001'),
      _hex('30800000'),
    ]) {
      expect(
        () => tlsServerEndPointChannelBinding(der),
        throwsA(isA<EwsException>()),
      );
    }
  });
}
