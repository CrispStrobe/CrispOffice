# Mail workspace — final main reconciliation

The qualified [01290cee stage](reconciled-acceptance-01290cee.md) was preserved
before main advanced to `d040c15a07f652d01e75363031d0efdee6357bda`. That main
already includes the Mail implementation and adds Word/PowerPoint VBA and
proofing changes. This reconciliation preserves its product source, retaining
only the small omitted-focus radial parsing improvement from the earlier gate.

At this checkpoint, the affected Office/native-format/proofing compatibility
gate and complete Studio Mail selection are being qualified on the combined
source. The unchanged core/transport/UI and native-path cases have separately
scoped continuity proofs. Historical counts remain attributed to their source.
No hosted CI is queried or awaited. The final accepted report replaces this
checkpoint notice before publication.
