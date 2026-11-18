# Quds Mail licensing and App Store release plan

**Status:** implementation planning; no application archive, store submission, or licensing audit has been completed by this documentation change. **Evidence checked:** 2026-11-18. Recheck the cited platform requirements before a release.

This document covers the shared `quds_mail_core`, `quds_mail_mime`, `quds_mail_store`, `quds_mail_transport`, `quds_mail_ui`, and `quds_mail_office` packages, their integration into CrispCloud, and the standalone Office application at `apps/quds_office`. It defines release evidence without preventing independent shared-package implementation.

## Distribution boundaries

The Quds fork's [inspected root license is MIT](https://github.com/CrispStrobe/quds_office_suite/blob/556c55c0ef312eda2cca11600021d293a81ab44b/LICENSE). Its existing license remains unchanged. Independently authored Quds Mail files should use that MIT baseline; incorporated components retain their own licenses.

The inspected CrispCloud host [has an AGPL-3.0 root license](https://github.com/CrispStrobe/CrispCloud/blob/05e10a6e5afd951844b45fd4f2aac11de15d0e6b/LICENSE.txt). This is a material distinction: adding a compatible mail module does not establish that the complete CrispCloud product meets the requested no-GPL-family policy or is suitable for App Store distribution. Repository ownership alone does not establish rights to relicense every contribution or dependency.

| Target | Planned source boundary | Distribution finding | App Store validation |
| --- | --- | --- | --- |
| Shared mail packages | MIT original files; retained third-party licenses, including allowed MPL-2.0 | Candidate baseline; exact dependency audit pending | **NOT RUN**; assess in each consuming archive |
| Standalone Office, `apps/quds_office` | Separate MIT shell using Quds editors and shared mail packages | Candidate for the requested license policy; provenance and dependency evidence pending | **NOT RUN** on iOS/iPadOS and macOS |
| CrispCloud with shared Mail | Existing AGPL host plus shared packages | Host distribution gate unresolved; cannot claim no-GPL compliance | **NOT RUN**; cannot claim complete-host compatibility |

The standalone shell must not copy CrispCloud's AGPL implementation, UI files, assets, or `.eml` viewer code unless a separately applicable allowed license and the necessary rights are established. Existing viewer behavior and required interfaces can guide an independently implemented integration. Preserve any independently licensed Quds components under their actual terms. Code sharing is not a license exemption; moving code between packages does not change its provenance.

## LIC-01 — Record the policy and provenance baseline

**Owner:** release maintainer. **Evidence:** a versioned component/provenance ledger.

Allow MIT, BSD variants, Apache-2.0, ISC, and individually documented equivalent free permissive licenses, plus **MPL-2.0**, which the user explicitly permits. Exclude GPL, AGPL, LGPL, noncommercial restrictions, unlicensed code, and unidentified license terms from the standalone product's approved dependency set. Do not treat “free download” or “source available” as approval.

Record each copied or adapted file's upstream path, immutable revision, license, and changes. For dual-licensed components, record the allowed license actually selected. For CrispCloud, retain the host finding as a separate unresolved distribution item; resolving it requires evidence covering the host, contributors, and dependencies, rather than a new root-license label. This does not block independent MIT package work or documented integration interfaces.

## LIC-02 — Audit the complete shipped dependency graph

**Owner:** package maintainers and release maintainer. **Evidence:** per-target dependency inventory and notices.

The inventory must include package/version, source revision, license expression, bundled assets, local modifications, consuming targets, and source availability where required. Inspect Dart dependencies, Flutter engine notices, CocoaPods, Swift packages, native frameworks, bundled JavaScript, fonts, icons, and optional feature dependencies actually included in each artifact.

Pin the resolved product build through committed lockfiles and immutable fork references. Review upgrades before updating the approved inventory. An MIT wrapper does not override a dependency's MPL or prohibited license. Unknown or prohibited entries fail the affected release's license check; they do not prevent unrelated implementation. Record build tools separately from redistributed runtime components instead of conflating their obligations.

## LIC-03 — Verify the MPL mail and portable MIME boundary

**Owner:** transport/MIME maintainers. **Evidence:** pinned source, dependency graph, platform build results.

The proposed baseline is [`enough_mail` 3.0.0, MPL-2.0](https://pub.dev/packages/enough_mail/versions/3.0.0/license). Selection is not a completed compatibility audit. Before adopting it, verify the exact release, its dependencies, and required API behavior.

Any portable MIME extraction or fork belongs behind `quds_mail_mime`'s platform-neutral interface. Preserve MPL notices and coverage on copied or adapted files; do not relabel them MIT. Prove that the shared MIME surface does not require `dart:io` or Flutter UI libraries before claiming web portability. Keep network-dependent transport code in `quds_mail_transport`. Independently written adapter/interface files may remain MIT when they contain no copied MPL code. Record the fork's maintenance and source-release responsibility explicitly.

## LIC-04 — Publish matching covered source and notices

**Owner:** release maintainer. **Evidence:** immutable source release and recipient-visible source link for every binary version.

[MPL-2.0 §§3.1–3.4](https://www.mozilla.org/en-US/MPL/2.0/) require covered-source availability for executable distributions, preservation of source rights, and retention of notices. [Mozilla's FAQ Q8–Q11](https://www.mozilla.org/en-US/MPL/2.0/FAQ/) explains that these obligations also cover unmodified MPL components; independently authored separate files need not become MPL.

For each release, preserve the exact MPL-covered source and local changes corresponding to the shipped code. Provide a stable, publicly reachable source archive or immutable repository tag, component/version mapping, license text, and relevant build/patch instructions. Do not link only to a moving upstream branch. Add **About → Open-source licenses and source** to both hosts and verify its links from the release build. Public development alone does not replace matching-source availability and recipient notice.

## LIC-05 — Preserve source rights in executable terms

**Owner:** release maintainer. **Evidence:** terms selected for each distribution target.

MPL permits different executable terms provided they do not limit recipients' MPL source rights. Apple's [standard EULA, section a](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/), includes an open-source-license carve-out; Apple also supports a [custom EULA](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement). Check whichever terms the host actually distributes, including terms outside the App Store. Preserve the source-license rights explicitly rather than assuming a proprietary host EULA covers them correctly.

This supports an MPL-containing App Store design in principle. It is neither Apple approval of a particular archive nor a finding that CrispCloud's AGPL host has been cleared.

## LIC-06 — Validate each Apple sandbox and credential boundary

**Owner:** host/platform maintainers. **Evidence:** final entitlements and attachment/editor round-trip results.

[Mac App Store distribution requires App Sandbox](https://developer.apple.com/documentation/security/app-sandbox). Enable outgoing networking with `com.apple.security.network.client`. Use user-selected document access for attachments, `.eml` import/export, and Office documents; keep caches, outbox data, and editor working copies in the app container. Add entitlements only for implemented capabilities. A loopback OAuth listener, if selected, needs its own sandbox validation.

Persist user-granted document access through [security-scoped URLs/bookmarks](https://developer.apple.com/documentation/foundation/nsurl/) when needed. Treat incoming attachments as immutable; edit a working copy and explicitly save/export or attach the resulting version. Test picker cancellation, permission loss, moved files, and a revoked bookmark using the signed release configuration.

CrispCloud and standalone Office share packages, not implicit account storage. Apple [isolates Keychain items by default](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps). Initially provide separate host account stores and namespaces. Cross-app sharing is a later explicit feature requiring appropriate access groups, signing identity, and user-facing behavior; never discover credentials by reading another app's files.

## LIC-07 — Check review rules against the implemented product

**Owner:** host/platform maintainers. **Evidence:** build configuration and review notes.

Apply the following [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) to the actual release:

- **2.5.1:** public platform APIs and supported operating systems.
- **2.5.2:** bundled functionality and authorized container/document access; no downloaded executable mail modules.
- **2.5.4:** background modes used for their intended purposes.
- **2.4.5:** Mac App Store sandboxing, self-contained packaging, approved installation/update behavior, and no privilege escalation.
- **4.5.4:** useful operation without push permission and appropriate notification payloads.
- **4.8:** mailbox-provider login can qualify for the third-party-content-client exception; assess login to the host's own primary account separately.

Use compile-time package composition for the reusable Mail module. Maintain a store configuration distinct from any non-store updater. These checks apply to the whole host application, not just the new package.

## LIC-08 — Verify authentication and optional default-mail behavior

**Owner:** account/platform maintainers. **Evidence:** provider registration and release-device flow tests.

Separate mailbox authorization from CrispCloud/Office service-account login. Use provider-supported native authorization flows, PKCE where applicable, system-browser authorization, platform-appropriate redirects, and Keychain-backed token storage. A bundled client secret is not confidential. Google [prohibits developer-controlled embedded OAuth user agents](https://developers.google.com/identity/protocols/oauth2/policies); Microsoft documents [authorization code and PKCE](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow).

Test revoked tokens, expired refresh credentials, cancelled authorization, and local account removal. Disconnecting a mailbox must remove its local credentials/cache according to the user's chosen retention behavior; it must not silently delete the remote provider account.

Request Apple's optional [`com.apple.developer.mail-client`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.mail-client) entitlement only when implementing default-mail support. Validate `mailto:` handling and sending/receiving with arbitrary valid correspondents. This entitlement is not required simply to implement an ordinary email client.

## LIC-09 — Produce privacy evidence from the final archive

**Owner:** host/platform maintainers. **Evidence:** privacy manifests, archive report, privacy policy, and store disclosures.

Declare required-reason API use in `PrivacyInfo.xcprivacy` according to [Apple TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest). Check [Apple's SDK list](https://developer.apple.com/support/third-party-SDK-requirements/): it includes Flutter and common authentication, file-picker, database, notification, and WebView dependencies. Listed binary SDKs also have signature requirements. Inspect the archived product rather than assuming package source manifests were bundled correctly.

Document device-to-provider traffic, any relay, diagnostics, and attachment handling. Generate [App Privacy disclosures](https://developer.apple.com/app-store/app-privacy-details/) from those actual flows. Keep mail contents, subjects, addresses, attachments, and tokens out of routine logs/telemetry. Both hosts need accurate privacy documentation and controls for disconnecting accounts and removing local data. Adding a relay changes these facts and requires updated evidence, including provider requirements.

## LIC-10 — Validate background delivery and notification fallback

**Owner:** sync/platform maintainers. **Evidence:** physical-device suspend/resume and denied-permission results.

Do not depend on an indefinitely running IMAP socket while iOS is suspended. Implement launch/resume reconciliation and permitted background work. Apple [does not guarantee background-notification delivery](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app). Treat push as a hint to synchronize, not mailbox truth.

Test force-quit/reopen, task expiration, network loss during submission, delayed/coalesced notifications, and denied notification permission. Keep push payloads minimal; fetch mailbox changes through the authenticated provider path. Record which platforms support which delivery behavior instead of promising identical background behavior everywhere.

## LIC-11 — Record the encryption determination

**Owner:** release maintainer. **Evidence:** encryption inventory and App Store Connect declaration.

Inventory TLS, Dart/native cryptographic libraries, local encryption, and any later S/MIME/OpenPGP capability. Follow Apple's [encryption-export declaration guidance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations). Set `ITSAppUsesNonExemptEncryption` from the actual artifact and applicable exemption determination, including third-party code. Do not automatically set it to `NO` because the product is an email client. Update the determination when encryption features or dependencies change.

## LIC-12 — Assemble release evidence independently for each host

**Owner:** release maintainer. **Evidence:** versioned release record.

Before claiming store readiness, attach the resolved dependency/provenance ledger, matching covered-source release, notices/EULA selection, signed-archive entitlement/privacy inspection, sandbox document round trip, OAuth/removal results, sync/outbox recovery results, privacy disclosures, encryption declaration, and reviewer test instructions.

Record every item as **PASS**, **FAIL**, or **NOT RUN**, with the exact version and platform. All artifact/store checks are currently **NOT RUN**. Keep CrispCloud's unresolved host-license distribution gate visible even if its technical tests pass. Standalone Office may proceed on its independently verified license boundary. No store submission, credential registration, relicensing, or runtime implementation is performed by this plan commit.
