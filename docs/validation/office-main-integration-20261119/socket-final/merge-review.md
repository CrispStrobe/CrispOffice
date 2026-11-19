# Final Socket-compatible integration review

Incoming heads: Mail `700e5a35ce5f96e7abd1dc92d1a00d2110d40649` and Zotero
`022a974a96db23e22bc161f7d465e4b972e8c2a9`; integrated after main
`d41000336c84b6ebfe6b35f7f8335140b5d46038`. This source checkpoint precedes
the fresh consolidated qualification; no expected count is a passing result.

The incoming Socket facade now retains its original TCP owner after TLS,
closes that owner before secure output can block, settles abandoned direct
callers, guards generations and late results, and preserves ordered partial
writes and producer cancellation. It also preserves the existing Socket
factory API and trusted manual STARTTLS. Immediate physical cancellation
during a stalled TLS handshake is qualified only for the default owned
transport; a manual SDK Socket can detach its TCP owner during handoff. The
manual fallback settles abort and destroys eventual late results.

Independent review reproduced a rejected direct upgrade leaving the client
connected. The narrow fix restores generation-guarded abort and rethrows the
handshake exception. Existing real-TLS default-trust rejection cases now
assert disconnected/logged-out state before final cleanup. Controlled RED and
GREEN probe evidence is retained separately; the integrated gate provides the
actual TLS validation.

The incoming FETCH detector recognizes malformed response separators before
the strict shape parser rejects them. This prevents successful-prefix results
and false absent-UID tombstones. Six provider and twelve parser cases cover
the boundary. Existing TLS case assertions remain, including new direct abort
and TCP-close ordering cases.

The exact qualified core model-test blob
`dd9172e8aed55f976baf698ce9e5ed52d8cc0c02` is retained, including nonidentity,
equality, equal-hash and Set.add assertions. Incoming Mail archives remain
unchanged. Its continuation/store README identify the separate 71edec2d
checkpoint. The store README changed as a bound documentation input, so the
new qualification will capture it afresh rather than claim prior inventory
identity. The 611-execution checkpoint remains archived under ../tls.

The frozen plan keeps 35 suites, 26 strict analysis/format targets and seven
unchanged certificate/key/README inputs. The full core/store gate runs on the
same frozen source. No GitHub Actions are queried, dispatched or awaited.
