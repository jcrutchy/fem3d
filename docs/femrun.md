# femrun -- run whitelisted CLI tools from a web page

`femrun` is a small FreePascal program (`src/tools/femrun`) that lets a
browser page run the suite's command-line tools **without the browser ever
being able to launch anything it likes**. It is the target of a vdrx
`cli_bridges` route using `"protocol": "bus"` (spawn-per-request): vdrx
receives the HTTP request, starts `femrun`, writes one JSON request line to
its stdin, and returns the one JSON line it writes back.

Nothing in `femrun` is specific to vdrx. Anything that can hand it that one
JSON line (a PHP script behind Apache, a test harness, `echo ... | femrun`)
gets the same behaviour.

## Setup (vdrx)

1. Build (`build.bat`) so `bin\femrun.exe` and the tools exist.
2. Copy `src/tools/femrun/femrun.ini.example` to `bin\femrun.ini`, then edit
   the whitelist and `AllowedHosts` / `AllowedOrigins`.
3. Add a route to `vdrx.conf` (paths resolve against vdrx's own working
   directory; avoid spaces in the command path):

```js
const r = await fetch('/fem/run/femgeocheck', { method: 'POST', body: fgeoText });
const result = await r.json();   // {tool, exit, stdout, stderr, truncated, ms}
if (!r.ok) console.error(result.error);   // 4xx/5xx carry {"error": "..."}
else if (result.exit !== 0) showDiagnostics(result.stdout);
```

## Security model

What `femrun` enforces itself, on every request:

- **Whitelist only.** Tools exist only as `[TOOL name]` sections in
  `femrun.ini`. The request supplies a name (letters, digits, `_`, `-`)
  which is looked up; it is never turned into a path.
- **No shell, no free-form arguments.** Arguments are an array. Each `a=`
  value must exactly (case-sensitively) match an entry in the tool's `Args`;
  the config's `Fixed` arguments (typically `-`, meaning "read stdin") are
  always appended. A value cannot smuggle a second flag.
- **Host check.** The `Host` header must be in `AllowedHosts`, which defeats
  DNS-rebinding attacks. Empty list = everything rejected.
- **Origin check.** If the browser sends an `Origin`, it must be in
  `AllowedOrigins`. A `POST` must either carry an allowed `Origin` (all
  browsers send one) or, if `Token` is configured, the header
  `X-Femrun-Token` with that exact value.
- **Limits.** Per tool: input size, output size (excess is dropped and
  reported as `"truncated": true`), and wall-clock time (the process is
  killed). The tool's stdin is fed from a separate thread while stdout and
  stderr are drained concurrently, so neither a chatty tool nor a tool that
  writes before it reads (or exits without reading) can deadlock the pipes.
  (A first version fed stdin from the same thread and froze on Windows,
  whose pipe buffers are small; `run_femrun_test` now reproduces that case
  on any OS.)

What `femrun` **cannot** enforce, and what you need to know:

- **vdrx listens on all network interfaces** (`0.0.0.0`), not just loopback,
  and does not tell the script where a request came from. The Host/Origin
  checks stop *browser-based* attacks, but a different machine on your
  network can reach the port and send a hand-made request with a correct
  `Host` and `Origin`. Until vdrx gains a per-site bind address, protect the
  port with the Windows firewall (allow inbound to the vdrx port from
  nowhere but this machine), and set `Token` if the machine is on a network
  you do not control. A token is only a real defence if it is not served to
  the page from a world-readable file; paste it into the app once instead.
- The tools are trusted code that parse untrusted text; a parser bug in a
  tool is reachable through this route. Keep the whitelist short and the
  limits tight.

## Tests

`run_femrun_test` (run by `test.bat`, 31 checks) drives `femrun` exactly as
vdrx does, including a large stdin round trip, the timeout and output caps,
every rejection path, and the real `femgeocheck` on the shared fixtures. It
doubles as its own helper tool (`--echo`, `--sleep`, `--noisy`, `--exit3`,
`--stderr`) so the limits are tested portably.

The whole chain (curl -> vdrx -> femrun -> femgeocheck) was also exercised
by hand on Linux with the config above.

## Not done yet

- **Workspace mode** (several files per run, e.g. `femresolve` with its
  database folder): planned as `PUT /fem/ws/<session>/<name>` into a sandbox
  folder, then `POST /fem/run/<tool>` with that as the working directory.
- **Long-running jobs** (meshing, big solves) with start/poll endpoints; they
  need vdrx's `bus-daemon` flavour. Until then they run inside one request
  and are bounded by `TimeoutMs`.
