## 0.1.0

- Add a pure Dart single-VTODO codec bound to `quds_tasks_core` identities,
  task fields, explicit patches, and retained provider data.
- Preserve unchanged source, unknown properties and parameters, alarms,
  VTIMEZONE components, UID, and exact priority when editing other fields.
- Keep civil dates, floating times, UTC times, and TZID wall times distinct;
  refuse lossy fractional-second conversion and ambiguous task resources.
- Guard mutation of recurrence, duration, delegation, and related-task
  resources until their semantics have dedicated implementations.
- Add generic, Nextcloud, ownCloud, Open-Xchange, and mailbox.org connection
  presets with documented conservative capabilities and source links.
- Add focused preservation, boundary, malformed-input, and profile tests.
- Bound resources, unfolded lines, physical lines, and nesting with fixed
  ceilings; reject raw controls and property-name injection.
- Require retained timezone definitions for zoned date writes, enforce strict
  task start/due ordering, and retain progress-property extension parameters.
- Add a real codec round-trip portability smoke for JavaScript and Node.

This is a codec and configuration foundation. It does not implement DAV HTTP
transport, account login, durable synchronization, or application task UI.
