# Public loopback TLS test fixtures

These certificates and the server private key are intentionally public test data.
They are used only by local loopback tests. Never use the key or trust this CA in
production. The private CA signing key was discarded after generating the files.

The certificate has localhost, 127.0.0.1, and ::1 subject alternatives, serverAuth
extended usage, and a fixed validity from 2020-01-01 through 2045-01-01. Successful
tests construct an isolated SecurityContext trusting this CA; refusal tests use
the normal default context and must reject the same server certificate. No test
sets an onBadCertificate callback or changes the global default trust context.

The fixtures are checked in as fixed bytes; tests do not run OpenSSL, generate
keys, contact external servers, or depend on host certificate installation.
