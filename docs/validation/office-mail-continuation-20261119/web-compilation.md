# Mail browser compilation

The frozen qualification compiles `example/tool/mail_web_entry.dart`, which
imports the public `studio_mail.dart` export and places its dialog in a real
Flutter application tree. It uses Flutter's browser platform libraries and
the same two-stage frontend / JavaScript compiler path used by Flutter tooling.

`web-sdk.json` pins the official Flutter engine-specific web component by URL,
archive length, archive SHA-256, and all 548 member lengths and SHA-256 values.
Its engine revision matches the separately verified native/Node runtime. The
web component lives outside that runtime; no verified runtime file is replaced.

Prepare once before freezing the source:

```sh
python docs/validation/office-mail-continuation-20261119/prepare_web_sdk.py \
  --runtime /path/to/office-runtime \
  --output /path/to/office-web-sdk
```

To verify an existing prepared component, add `--verify-only`. Run the aggregate
driver with `--web-sdk /path/to/office-web-sdk` in addition to its source, base,
runtime, and output arguments. The accepted gate downloads nothing.

The gate checks the compiler's dependency output for the web dialog, saved
message view, and web file loader. It rejects native account, native file,
bounded native message-loader, and vendored high-level socket client paths.
It then generates JavaScript, checks its syntax with the bound Node executable,
and records the kernel, JavaScript, and dependency artifact identities. All web
component bytes are fingerprinted before and after aggregate execution.

This establishes browser-target compilation and the actual selected conditional
import graph. It does not establish a live browser session, file-picker plugin
registration, browser storage, deployed hosting, or full Flutter web packaging.
Development compilation is exploratory evidence; only the frozen aggregate run
may be presented as accepted qualification of its recorded source commit.
