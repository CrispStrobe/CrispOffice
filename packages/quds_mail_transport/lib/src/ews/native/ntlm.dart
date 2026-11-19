import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/digests/md4.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import '../errors.dart';

// Independently implemented from MS-NLMP 2.2 / 3.1.5.1.2 / 3.3.2 and RFC 5929.
// HTTP runs inside verified TLS; NTLM signing/sealing/key exchange are not used.
const int _unicode = 0x00000001;
const int _ntlm = 0x00000200;
const int _extendedSessionSecurity = 0x00080000;
const int _targetInfo = 0x00800000;
const int _version = 0x02000000;
const int _flags =
    _unicode |
    0x00000004 |
    _ntlm |
    0x00008000 |
    _extendedSessionSecurity |
    _targetInfo |
    0x20000000 |
    0x80000000;
const List<int> _signature = [78, 84, 76, 77, 83, 83, 80, 0];

/// Internal protocol helper. Neither the public API nor diagnostics expose it.
Uint8List createNtlmNegotiateMessage() {
  final message = Uint8List(40);
  message.setRange(0, 8, _signature);
  final data = ByteData.sublistView(message);
  data.setUint32(8, 1, Endian.little);
  data.setUint32(12, _flags, Endian.little);
  data.setUint32(20, 40, Endian.little);
  data.setUint32(28, 40, Endian.little);
  // VERSION is not negotiated; its reserved bytes remain zero.
  return message;
}

final class _AvPair {
  const _AvPair(this.id, this.bytes);
  final int id;
  final Uint8List bytes;
}

final class _Challenge {
  _Challenge(Uint8List message) {
    if (message.length < 48 || message.length > 65536) _malformed();
    for (var i = 0; i < _signature.length; i++) {
      if (message[i] != _signature[i]) _malformed();
    }
    final data = ByteData.sublistView(message);
    if (data.getUint32(8, Endian.little) != 2) _malformed();
    flags = data.getUint32(20, Endian.little);
    const requiredFlags =
        _unicode | _ntlm | _extendedSessionSecurity | _targetInfo;
    if ((flags & requiredFlags) != requiredFlags) {
      throw const EwsException(MailProblemCode.unsupported);
    }
    final headerSize = (flags & _version) != 0 ? 56 : 48;
    if (message.length < headerSize) _malformed();
    serverChallenge = Uint8List.fromList(message.sublist(24, 32));
    _securityBuffer(message, 12, headerSize); // Validate unused target name.
    final info = _securityBuffer(message, 40, headerSize);
    if (info.length < 4 || info.length > 16384) _malformed();
    final infoData = ByteData.sublistView(info);
    final seen = <int>{};
    var offset = 0;
    var ended = false;
    while (offset + 4 <= info.length) {
      final id = infoData.getUint16(offset, Endian.little);
      final size = infoData.getUint16(offset + 2, Endian.little);
      offset += 4;
      if (id == 0) {
        if (size != 0 || offset != info.length) _malformed();
        ended = true;
        break;
      }
      if (!seen.add(id) || seen.length > 128 || size > info.length - offset) {
        _malformed();
      }
      if (((id >= 1 && id <= 5) || id == 9) && size.isOdd) _malformed();
      if ((id == 6 && size != 4) ||
          (id == 7 && size != 8) ||
          (id == 8 && size < 48) ||
          (id == 10 && size != 16)) {
        _malformed();
      }
      final value = Uint8List.fromList(info.sublist(offset, offset + size));
      pairs.add(_AvPair(id, value));
      offset += size;
    }
    if (!ended) _malformed();
  }

  late final int flags;
  late final Uint8List serverChallenge;
  final List<_AvPair> pairs = [];
}

Uint8List _securityBuffer(Uint8List message, int at, int headerSize) {
  final data = ByteData.sublistView(message);
  final length = data.getUint16(at, Endian.little);
  final maxLength = data.getUint16(at + 2, Endian.little);
  final offset = data.getUint32(at + 4, Endian.little);
  if (maxLength < length ||
      offset > message.length ||
      length > message.length - offset ||
      (length != 0 && offset < headerSize)) {
    _malformed();
  }
  return Uint8List.sublistView(message, offset, offset + length);
}

Never _malformed() => throw const EwsException(MailProblemCode.providerFailure);

Uint8List _utf16(String value) {
  final bytes = Uint8List(value.length * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < value.length; i++) {
    data.setUint16(i * 2, value.codeUnitAt(i), Endian.little);
  }
  return bytes;
}

Uint8List _hmac(List<int> key, List<int> input) =>
    Uint8List.fromList(Hmac(md5, key).convert(input).bytes);

/// MS-NLMP's NTLMv2 computation, exposed internally for published test vectors.
/// The caller owns these short-lived key bytes and must clear them after use.
final class NtlmV2Response {
  const NtlmV2Response(this.ntResponse, this.sessionBaseKey);
  final Uint8List ntResponse;
  final Uint8List sessionBaseKey;
}

NtlmV2Response computeNtlmV2Response({
  required String username,
  required String domain,
  required String password,
  required Uint8List serverChallenge,
  required Uint8List clientChallenge,
  required Uint8List timestamp,
  required Uint8List targetInfo,
}) {
  if (username.isEmpty ||
      username.length > 1024 ||
      domain.length > 255 ||
      password.length > 65536 ||
      serverChallenge.length != 8 ||
      clientChallenge.length != 8 ||
      timestamp.length != 8 ||
      targetInfo.length > 16384) {
    throw const EwsException(MailProblemCode.invalidInput);
  }
  final passwordBytes = _utf16(password);
  final passwordHash = MD4Digest().process(passwordBytes);
  final responseKey = _hmac(
    passwordHash,
    _utf16('${username.toUpperCase()}$domain'),
  );
  passwordBytes.fillRange(0, passwordBytes.length, 0);
  passwordHash.fillRange(0, passwordHash.length, 0);
  try {
    final blob = Uint8List(28 + targetInfo.length + 4);
    blob[0] = 1;
    blob[1] = 1;
    blob.setRange(8, 16, timestamp);
    blob.setRange(16, 24, clientChallenge);
    blob.setRange(28, 28 + targetInfo.length, targetInfo);
    final proof = _hmac(responseKey, [...serverChallenge, ...blob]);
    final sessionKey = _hmac(responseKey, proof);
    return NtlmV2Response(Uint8List.fromList([...proof, ...blob]), sessionKey);
  } finally {
    responseKey.fillRange(0, responseKey.length, 0);
  }
}

/// Constructs an NTLMv2 Type 3 message with MIC, TLS binding and explicit SPN.
/// All timestamp/nonce overrides are internal test seams, not package exports.
Uint8List createNtlmAuthenticateMessage({
  required Uint8List negotiate,
  required Uint8List challenge,
  required String username,
  required String password,
  required Uint8List channelBinding,
  required String targetName,
  String domain = '',
  String workstation = '',
  Uint8List? clientChallenge,
  DateTime? now,
}) {
  if (negotiate.length != 40 ||
      channelBinding.length != 16 ||
      workstation.length > 255 ||
      targetName.isEmpty ||
      targetName.length > 1024) {
    throw const EwsException(MailProblemCode.invalidInput);
  }
  final expectedNegotiate = createNtlmNegotiateMessage();
  for (var i = 0; i < negotiate.length; i++) {
    if (negotiate[i] != expectedNegotiate[i]) {
      throw const EwsException(MailProblemCode.invalidInput);
    }
  }
  final parsed = _Challenge(challenge);
  var user = username;
  var userDomain = domain;
  final slash = user.indexOf(r'\');
  if (slash >= 0) {
    if (slash == 0 ||
        slash == user.length - 1 ||
        user.indexOf(r'\', slash + 1) >= 0 ||
        (domain.isNotEmpty &&
            domain.toUpperCase() != user.substring(0, slash).toUpperCase())) {
      throw const EwsException(MailProblemCode.invalidInput);
    }
    userDomain = user.substring(0, slash);
    user = user.substring(slash + 1);
  }
  final nonce =
      clientChallenge ??
      Uint8List.fromList(
        List<int>.generate(8, (_) => Random.secure().nextInt(256)),
      );
  final timestamp = Uint8List(8);
  ByteData.sublistView(timestamp).setUint64(
    0,
    ((now ?? DateTime.now()).toUtc().microsecondsSinceEpoch +
            11644473600000000) *
        10,
    Endian.little,
  );
  var avFlags = 2; // MIC_PRESENT; never permit the server to strip integrity.
  final info = BytesBuilder(copy: false);
  for (final pair in parsed.pairs) {
    if (pair.id == 7) timestamp.setAll(0, pair.bytes);
    if (pair.id == 6) {
      avFlags |= ByteData.sublistView(pair.bytes).getUint32(0, Endian.little);
    } else if (pair.id != 9 && pair.id != 10) {
      _writePair(info, pair.id, pair.bytes);
    }
  }
  final avFlagsBytes = Uint8List(4);
  ByteData.sublistView(avFlagsBytes).setUint32(0, avFlags, Endian.little);
  _writePair(info, 6, avFlagsBytes);
  _writePair(info, 9, _utf16(targetName));
  _writePair(info, 10, channelBinding);
  info.add(const [0, 0, 0, 0]);
  final result = computeNtlmV2Response(
    username: user,
    domain: userDomain,
    password: password,
    serverChallenge: parsed.serverChallenge,
    clientChallenge: nonce,
    timestamp: timestamp,
    targetInfo: info.takeBytes(),
  );
  try {
    final domainBytes = _utf16(userDomain);
    final userBytes = _utf16(user);
    final workstationBytes = _utf16(workstation);
    // Eight zero VERSION bytes precede MIC, including without VERSION flag.
    const headerSize = 88;
    final length =
        headerSize +
        domainBytes.length +
        userBytes.length +
        workstationBytes.length +
        24 +
        result.ntResponse.length;
    final message = Uint8List(length);
    message.setRange(0, 8, _signature);
    final data = ByteData.sublistView(message);
    data.setUint32(8, 3, Endian.little);
    data.setUint32(60, parsed.flags & _flags, Endian.little);
    var offset = headerSize;
    void put(int field, Uint8List value) {
      data.setUint16(field, value.length, Endian.little);
      data.setUint16(field + 2, value.length, Endian.little);
      data.setUint32(field + 4, offset, Endian.little);
      message.setRange(offset, offset + value.length, value);
      offset += value.length;
    }

    put(28, domainBytes);
    put(36, userBytes);
    put(44, workstationBytes);
    // Never emit LM or NTLMv1 credentials, including for timestamp-less peers.
    put(12, Uint8List(24));
    put(20, result.ntResponse);
    put(52, Uint8List(0));
    final mic = _hmac(result.sessionBaseKey, [
      ...negotiate,
      ...challenge,
      ...message,
    ]);
    message.setRange(72, 88, mic);
    return message;
  } finally {
    result.sessionBaseKey.fillRange(0, result.sessionBaseKey.length, 0);
  }
}

void _writePair(BytesBuilder destination, int id, Uint8List value) {
  final header = Uint8List(4);
  final data = ByteData.sublistView(header);
  data.setUint16(0, id, Endian.little);
  data.setUint16(2, value.length, Endian.little);
  destination.add(header);
  destination.add(value);
}

/// The MD5 hash of GSS channel bindings containing RFC 5929's certificate hash.
/// Unknown signature algorithms fail explicitly instead of silently binding to
/// the wrong digest. Certificate bytes have already passed platform TLS checks.
Uint8List tlsServerEndPointChannelBinding(Uint8List certificateDer) {
  if (certificateDer.isEmpty || certificateDer.length > 1024 * 1024) {
    _malformed();
  }
  final certificate = _Der.read(certificateDer, 0, certificateDer.length);
  if (certificate.tag != 0x30 || certificate.end != certificateDer.length) {
    _malformed();
  }
  final tbs = _Der.read(certificateDer, certificate.start, certificate.end);
  if (tbs.tag != 0x30) _malformed();
  final algorithm = _Der.read(certificateDer, tbs.end, certificate.end);
  if (algorithm.tag != 0x30) _malformed();
  final oid = _Der.read(certificateDer, algorithm.start, algorithm.end);
  if (oid.tag != 6) _malformed();
  final identifier = _oid(certificateDer, oid);
  final Hash digest;
  switch (identifier) {
    case '1.2.840.113549.1.1.4': // MD5-with-RSA -> SHA-256, RFC 5929.
    case '1.2.840.113549.1.1.5': // SHA-1-with-RSA -> SHA-256.
    case '1.2.840.113549.1.1.11':
    case '1.2.840.10045.4.1':
    case '1.2.840.10045.4.3.2':
    case '1.2.840.10040.4.3':
    case '2.16.840.1.101.3.4.3.2':
      digest = sha256;
    case '1.2.840.113549.1.1.14':
    case '1.2.840.10045.4.3.1':
    case '2.16.840.1.101.3.4.3.1':
      digest = sha224;
    case '1.2.840.113549.1.1.12':
    case '1.2.840.10045.4.3.3':
    case '2.16.840.1.101.3.4.3.3':
      digest = sha384;
    case '1.2.840.113549.1.1.13':
    case '1.2.840.10045.4.3.4':
    case '2.16.840.1.101.3.4.3.4':
      digest = sha512;
    case '1.2.840.113549.1.1.10':
      digest = _pssDigest(certificateDer, oid.end, algorithm.end);
    default:
      throw const EwsException(MailProblemCode.unsupported);
  }
  final application = <int>[
    ...ascii.encode('tls-server-end-point:'),
    ...digest.convert(certificateDer).bytes,
  ];
  final bindings = Uint8List(20 + application.length);
  ByteData.sublistView(
    bindings,
  ).setUint32(16, application.length, Endian.little);
  bindings.setRange(20, bindings.length, application);
  return Uint8List.fromList(md5.convert(bindings).bytes);
}

Hash _pssDigest(Uint8List der, int start, int end) {
  if (start == end) return sha256; // RSASSA-PSS's default hash is SHA-1.
  final parameters = _Der.read(der, start, end);
  if (parameters.tag != 0x30 || parameters.end != end) _malformed();
  var at = parameters.start;
  while (at < parameters.end) {
    final parameter = _Der.read(der, at, parameters.end);
    if (parameter.tag == 0xa0) {
      final algorithm = _Der.read(der, parameter.start, parameter.end);
      if (algorithm.tag != 0x30 || algorithm.end != parameter.end) _malformed();
      final oid = _Der.read(der, algorithm.start, algorithm.end);
      if (oid.tag != 6) _malformed();
      return switch (_oid(der, oid)) {
        '1.3.14.3.2.26' => sha256,
        '2.16.840.1.101.3.4.2.1' => sha256,
        '2.16.840.1.101.3.4.2.2' => sha384,
        '2.16.840.1.101.3.4.2.3' => sha512,
        '2.16.840.1.101.3.4.2.4' => sha224,
        _ => throw const EwsException(MailProblemCode.unsupported),
      };
    }
    at = parameter.end;
  }
  return sha256;
}

final class _Der {
  const _Der(this.tag, this.start, this.end);
  final int tag;
  final int start;
  final int end;

  static _Der read(Uint8List bytes, int at, int limit) {
    if (at < 0 || at + 2 > limit || limit > bytes.length) _malformed();
    final tag = bytes[at++];
    if ((tag & 31) == 31) _malformed();
    var length = bytes[at++];
    if ((length & 128) != 0) {
      final count = length & 127;
      if (count < 1 || count > 4 || count > limit - at || bytes[at] == 0) {
        _malformed();
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | bytes[at++];
      }
      if (length < 128) _malformed();
    }
    if (length > limit - at) _malformed();
    return _Der(tag, at, at + length);
  }
}

String _oid(Uint8List bytes, _Der oid) {
  if (oid.start == oid.end || oid.end - oid.start > 32) _malformed();
  final first = bytes[oid.start];
  final components = <int>[
    first < 80 ? first ~/ 40 : 2,
    first < 80 ? first % 40 : first - 80,
  ];
  var value = 0;
  var componentBytes = 0;
  for (var at = oid.start + 1; at < oid.end; at++) {
    final byte = bytes[at];
    if (++componentBytes > 5 || (componentBytes == 1 && byte == 128)) {
      _malformed();
    }
    value = (value << 7) | (byte & 127);
    if ((byte & 128) == 0) {
      components.add(value);
      value = 0;
      componentBytes = 0;
    }
  }
  if (componentBytes != 0) _malformed();
  return components.join('.');
}
