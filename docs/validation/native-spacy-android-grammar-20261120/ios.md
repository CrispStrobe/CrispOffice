# iOS: no grammar claim (20 November 2026)

iOS is unchanged. Analysis runs, but grammar is refused, and no iOS digest is
in `spacyGrammarNativeSha256s` or `spacyGrammarCodeSha256s`.

- **The Simulator binary is not the device binary.** The XCFramework holds
  two different files. One is the device slice `ios-arm64`
  (`2a0ca967…` before app signing, thin arm64). The other is the simulator
  slice `ios-arm64_x86_64-simulator` (`054c21e3…`, a fat arm64+x86_64
  binary). After the app build signs it, the simulator copy measured
  `3827bd4c…` in the earlier simulator gate. A replay on the Simulator would
  produce evidence only for those simulator bytes. Apps never ship them.
- **Only bytes that actually ran get a claim.** No iPhone or iPad was
  attached, so the device slice was never loaded. Its signature-independent
  code digest would survive App Store re-signing, but nothing has been run
  for it. So it gets no claim.
- **Not run here.** The Simulator replay would need a full Xcode build of
  the Studio app on this Mac. The owner moved emulator and simulator work off
  the Mac because it was overloaded (load about 80), and GitHub-hosted
  runners cannot run the iOS Simulator replay through this workflow. The
  `mobile_spacy_grammar_replay_test.dart` test is platform-neutral. Run on a
  Simulator, it would first need that simulator digest temporarily listed
  in the planner, and its result would apply to the simulator bytes only.
- A fresh `tool/build.py --ios` from the pinned source reproduced both slice
  digests of the receipt (`2a0ca967…` and `054c21e3…`).

To qualify iOS, run the same replay on a physical device with the
App Store-signed app. Then record the measured code digest of the thin
device slice.
