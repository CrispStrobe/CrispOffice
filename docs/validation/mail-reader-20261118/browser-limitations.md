# Browser execution limits in this workspace

JavaScript compilation and Node execution are distinct from browser runtime
qualification. The core and MIME tests execute in the VM and Node. The public
portable MIME fixture compiles to JavaScript and produces the same projection
and source/attachment hashes in both runtimes.

An actual Chromium launch was attempted. The executor denied Chromium's
process-singleton Unix socket before a test could execute. The fork verification
directory retains that output. This is an environment failure, not a passing or
failing browser result for Mail.

A separate cloud browser was also tried against a locally served compiled
public-entry fixture. Its loopback could not reach the executor's server
(`ERR_CONNECTION_REFUSED`). The cloud browser then refused observation of its
internal error page because that URL protocol was outside its policy. No
alternate protocol, raw debugging connection or policy workaround was used.

The Chrome runtime gate remains **NOT QUALIFIED**. Run the supplied local
verification helper with `--chrome /path/to/chrome` on a host that permits a
browser process, including the post-bootstrap request-denial reader tests.
JavaScript compilation, static import review, and Node results do not close
that gate. Likewise, an HTML sanitizer unit test alone does not establish an
end-to-end no-fetch browser result.
