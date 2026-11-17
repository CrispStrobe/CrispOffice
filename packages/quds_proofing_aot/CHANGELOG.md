# Changelog

## Unreleased

- Make a private, managed native worker the default backend. Add
  `AotClient.local()` and explicit `AotClient.http()` compatibility; no
  SynanDaemon, listening port, shell or runtime download is required locally.
- Add a pinned, headless native build and atomic runtime assembly with real
  German/Russian syntax and German/Russian/English morphology smoke checks.
- Bound process requests, output, admission and lifetime; close workers on
  cancellation, disposal, protocol failure and active-request timeout without
  silently resubmitting document text.
- Reuse loaded dictionaries and add exact-key, bounded LRU morphology caching
  and concurrent identical-lookup coalescing. Do not cache syntax or failures.
- Preserve exact native source spans and distinguish original token `text` from
  normalized `analysisText`, including verified German `zu-helfen` readings.
  Abstain from grammar rules whose context contains normalized tokens.
- Remove upstream's `input.lem` diagnostic and debug-only `before.lem`/`after.lem`
  dumps, and fix dangling syntax group-description strings in exact,
  manifest-recorded generated build copies.
- Keep Studio analysis visible before setup; reuse a private dialog client, add
  standalone Word forms for English/German/Russian, and retain stale-document
  and cancellation isolation from manual grammar checks.
- Add CLI native-runtime discovery, `doctor`, stdin input, executable/resource
  paths, configurable deadlines, explicit backend selection and JSON metadata.

## 0.1.0

- Add typed AOT syntax and morphology analysis with strict source mapping.
- Add an optional bounded HTTP transport and explicit remote endpoint opt-in.
- Add conservative de-DE subject/verb, fixed-preposition case and adjective
  agreement checks through the shared Office proofing provider contract.
- Add a Studio analysis dialog, explicit manual grammar integration and a JSON CLI.
