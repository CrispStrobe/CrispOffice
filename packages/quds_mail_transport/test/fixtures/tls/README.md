# Local TLS fixture

The certificate and private key in this directory are public test data for a
loopback-only IMAP peer. They must never be used by a deployed server or added to
an application's trusted roots.

The self-signed certificate covers only IP address `127.0.0.1`. Tests explicitly
trust it in an injected test client to verify successful TLS data flow. Separate
tests retain default trust and use a mismatched hostname to verify rejection.
Production configuration has no certificate-bypass option.

The fixture was generated locally with OpenSSL using RSA-2048, SHA-256, a
3,650-day validity period, subject `CN=Quds loopback TLS fixture`, and extensions
`subjectAltName=IP:127.0.0.1` and `basicConstraints=critical,CA:TRUE`.
