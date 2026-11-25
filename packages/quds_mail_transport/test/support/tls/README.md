# Public loopback TLS test fixtures

These public certificates and server key are retained for historical
validation records. The active loopback tests use the shared
[fixtures/tls certificate](../../fixtures/tls/README.md).

The historical server certificate has localhost, 127.0.0.1, and ::1 subject
alternatives, serverAuth extended usage, and a fixed validity from 2020-01-01
through 2045-01-01. The CA signing key was discarded after generating the
fixtures. Keep the server key and CA out of production use.
