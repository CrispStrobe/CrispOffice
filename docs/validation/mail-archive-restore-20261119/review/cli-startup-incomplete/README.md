# Incomplete Dart CLI startup

The initial plain `dart test --reporter=json --concurrency=1 test/archive_restore_adversarial_test.dart` invocation remained in implicit dependency/build-hook resolution without emitting test events. It was interrupted with exit 130. These logs contribute no accepted test cases. The retained executable harness uses the verified installed test entrypoint, explicit package configuration, and VM/kernel compilation, with the default SQLite native asset.
