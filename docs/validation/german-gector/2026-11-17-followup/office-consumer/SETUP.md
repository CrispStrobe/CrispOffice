# Reconstructed Office consumer setup

This is setup guidance for a new run after the workspace reset. It does not stand in for the lost raw pre-reset consumer evidence.

## Runtime and isolation

Every Dart subprocess must inherit DASH__SUPPRESS_ANALYTICS=true and CI=true. Use the parent-verified wrapper with an explicit Dartdev/VM distinction: add --suppress-analytics only for Dartdev subcommands such as pub, test and analyze. Direct VM invocations, including dart --packages=... script.dart and dart --version, must forward their original VM arguments without that Dartdev-only flag. The first reconstructed consumer attempt received the flag incorrectly and exited 255; its raw failure is retained, and the corrected wrapper was used for the next run. Both Python runners inherit PATH and the environment. Do not call dart --disable-analytics: the earlier invocation emitted an incidental opt-out request and automatic approval review terminated that private PTY.

Keep restoration, package resolution, tests, consumer conversion and evidence capture in the same persistent private PTY. The reset left ordinary new exec sandboxes without a persistent workspace bind; a successful write in one such sandbox did not establish persistence in the next.

The engine and legacy parser are pure Dart packages. A lean overlay can use copied, unchanged package manifests, links to the reviewed source libraries and engine tests, and this separate root manifest:

~~~yaml
name: office_consumer_runtime
publish_to: none
environment:
  sdk: ^3.12.0
workspace:
  - packages/legacy_doc_parser
  - packages/quds_office_engine
~~~

The root is outside the source checkout. Copy only each package's pubspec.yaml, link each lib directory and the engine test directory to the checkout, and resolve packages from the overlay root using the verified wrapper. If preserving the repository lockfile's versions is practical, copy it to the overlay before resolution and retain the resulting lockfile. Do not change tracked workspace manifests just to omit Flutter applications.

The cohort runner checks the actual overlay engine/parser libraries and selected tests against the reviewed checkout, then records before/after hashes and its resolved package configuration. Run the consumer with that same package_config.json. Its input seals include both the reviewed source and the actual resolved package-library files, so the binding remains reviewable.

## Source artifacts

| File | Git blob |
| --- | --- |
| make_fixtures.dart | 1848d60199c2e9504453b48f73c68ba7fdfd3239 |
| run_consumers.py | e17f14bafddbad2360f510f16406399fba245be7 |
| run_office_cohort.py, expanded candidate | 2808309b7eb25c6b6fd5f17719b4e8dcdee884bb |

The original reconstructed cohort was 50 files / expected 699 cases. The expanded candidate adds the four first/even-header/footer comment-reuse regressions in odt_header_variant_comment_fidelity_test.dart, for 51 files / expected 703 cases. These are expected inventories, not claimed test results.

The generator retains the same five bounded semantic examples: linked/styled native fields and their source caches; malformed-field fallback; three pages of first/even/default headers and footers; body/table/header/frame/TOC bookmark ranges; and an empty native PAGE before a hard column break. The generator is newly reconstructed and must have its own source identity and outputs.

## Commands

Use absolute paths from the active PTY for the placeholders below. The output directories must be fresh.

~~~sh
python run_office_cohort.py \
  --engine OVERLAY/packages/quds_office_engine \
  --source-repo CHECKOUT \
  --output NEW_COHORT_OUTPUT \
  --expected-count 703

python run_consumers.py \
  --repo CHECKOUT \
  --package-config OVERLAY/.dart_tool/package_config.json \
  --jing JING_JAR \
  --schemas CHECKOUT/docs/validation/office-reconcile-20261117/consumer/schemas \
  --output NEW_CONSUMER_OUTPUT
~~~

Place make_fixtures.dart beside run_consumers.py or supply --generator explicitly. Obtain the same Jing artifact from:

https://repo.maven.apache.org/maven2/org/relaxng/jing/20241231/jing-20241231.jar

The consumer runner records the actual JAR hash. It enforces the retained content-schema SHA-256 40bad03efdbb02825230d357da0aa6ac679934c5bf56c6281752c0c24d58e4e6 and manifest-schema SHA-256 8aee71f03484be112af972d622cc9031280c007b0a454ae8815e8e333c9bdd17.

Jing is invoked with -i to disable unrelated ID/IDREF compatibility checks while keeping RelaxNG grammar validation. All 20 XML parts must pass Jing. The known lxml/libxml2 disagreement for a nested page-count is retained as a diagnostic; it is not silently counted as a Jing failure or used to weaken the schema check.

## Assertions and limits

Source ODT fields must retain authored caches, bold/color and hyperlinks. LibreOffice may refresh their values; the reopened DOCX must retain native field codes and links, and the actual PDF field values must remain bold and color #123456. PDF link targets are checked too. The harness does not claim full DOCX field-result formatting preservation: the earlier consumer put style on the field-begin run while its result runs carried defaults.

The header case checks exact first/even/default words on the corresponding three pages. Bookmark selection is reconstructed within each reopened body/header/text-box story, excluding text boxes from their containing body range. The column case checks both source ordering and actual PDF coordinates: a minimum 150-point separation and matching top positions.

Archive the complete commands, source seals, identities, original ODTs, extracted XML, converted PDFs/DOCX files, PDF coordinate data and summaries. Profile/cache directories may be excluded. Verify archive readback, save the archive remotely, and report any actual failures without relabeling them. Keep native performance timing separate from consumer/test jobs. No GitHub Actions waits or polling are involved.
