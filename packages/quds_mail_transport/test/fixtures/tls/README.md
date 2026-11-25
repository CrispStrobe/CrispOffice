# Local TLS fixture

These files are public test data for loopback-only IMAP and EWS peers.
Tests load `loopback-root.pem` as their explicit trust anchor.
`loopback-cert.pem` and `loopback-key.pem` identify the test server at
`127.0.0.1`. Negative tests exercise default trust and mismatched names.
Keep these files out of deployed servers and application trust stores.

The test root uses RSA-2048 and SHA-256 with critical CA and key-signing
extensions. The root private key was discarded after signing the leaf.
The RSA-2048 leaf has an IP SAN for `127.0.0.1`, `serverAuth` EKU, and
an 800-day validity period to fit macOS TLS policy. When renewing it,
update the independent leaf-certificate digest in `ews_ntlm_test.dart`.
[Apple TLS certificate requirements](https://support.apple.com/en-us/103769)
