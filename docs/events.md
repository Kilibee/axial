# Event stream API

Axial provides a local Unix domain socket that carries device events as fixed
size binary records. It is useful for diagnostics, integrations, and tools that
need direct access to SpaceMouse input without loading one of Axial's
compatibility frameworks.

## Connection

The default socket path is:

```text
/tmp/axial-$UID/events
```

`$UID` is the numeric Unix user ID, not the account name. In a shell, print it
with:

```sh
id -u
```

For example, if `id -u` prints `501`, the default path is
`/tmp/axial-501/events`. In shells that define the `$UID` variable, such as zsh
and bash, `echo "$UID"` prints the same value.

Set `AXIAL_SOCKET` to use another path. The service creates the parent directory
with mode `0700` and the socket with mode `0600`; connections from another Unix
user are rejected. The socket is an `AF_UNIX` `SOCK_STREAM`. It has no message
boundaries, so clients must read and write complete records themselves.

The service may be unavailable while Axial is starting or after it has stopped.
Clients should reconnect when a connection fails. A client that uses the
`Stream` helper in `include/axial/stream.hpp` is automatically retried every
100 ms.

## Record format

Every record is exactly 64 bytes. Values use the host's little-endian layout on
the supported macOS architectures (Apple silicon and Intel). The layout is:

| Offset | Size | Field | Description |
| ---: | ---: | --- | --- |
| 0 | 4 | `magicValue` | `0x534e4156` (`SNAV`) |
| 4 | 2 | `version` | `1` |
| 6 | 2 | `kind` | Event kind, described below |
| 8 | 8 | `received` | Monotonic timestamp in nanoseconds |
| 16 | 8 | `sequence` | Per-device input sequence number |
| 24 | 4 | `device` | Axial device identifier |
| 28 | 4 | `buttons` | Current 32-bit button mask |
| 32 | 12 | `axes` | Six signed 16-bit axis values |
| 44 | 2 | `vendor` | USB vendor ID |
| 46 | 2 | `product` | USB product ID |
| 48 | 4 | `flags` | Event and connection flags |
| 52 | 4 | `pid` | Sender process ID in a hello record |
| 56 | 8 | `decoded` | Service decode timestamp in nanoseconds |

`received` and `decoded` use `mach_continuous_time` converted to nanoseconds.
They are suitable for ordering and latency measurements within the running
system; they are not wall-clock timestamps.

## Opening a stream

The first record sent by a client must be a `hello` record. The service sends
the current `added` record for each connected device after accepting a normal
subscriber. A hello record normally has `pid` set to the client's process ID.

Set these flags in the hello record to select a stream:

| Flag | Value | Meaning |
| --- | ---: | --- |
| `monitor` | `1` | Receive raw events before the active application's profile filtering |
| `replay` | `2` | Send events into the service instead of subscribing; accepted only by the mock service used for tests |

With no flags, a subscriber receives events after the active profile has applied
gain, dead zones, axis inversion, dominant-axis mode, translation/rotation
switches, orbit mode, and suppressed buttons. Motion and button events are
delivered to the foreground application. Device lifecycle events are delivered
regardless of foreground focus. A monitor receives the raw event data and does
not receive profile-filtered data. Monitor events are also independent of
foreground focus: a monitoring app can remain in the background and continue to
observe SpaceMouse motion and button activity while another app is active.

The service identifies the peer process and requires it to have the same Unix
user as the service. A malformed record, an invalid first record, or a full
client queue closes the connection.

## Event kinds

| `kind` | Value | Meaning |
| --- | ---: | --- |
| `hello` | 1 | Client registration record; sent by the client only |
| `motion` | 2 | One or more of the six axes changed; `axes` contains the current values |
| `buttons` | 3 | The button mask changed; `buttons` contains the current mask |
| `added` | 4 | A device became available; identity fields are populated |
| `removed` | 5 | A device was disconnected; `axes` and `buttons` are cleared |
| `reset` | 6 | Input state was reset, such as after focus or service changes |
| `command` | 7 | An application command was triggered; `flags` identifies the command |

`device` is zero for service-wide reset events. `vendor` and `product` contain
the USB identity for device events. A button bit is set while that button is
held. Axis values are signed HID-scale values; their interpretation as
translation or rotation depends on the consumer and the active profile.

## Minimal C++ example

The public headers provide transport helpers for native clients:

```cpp
#include "axial/transport.hpp"

int fd = sn::openEvents(sn::Flags::monitor);
if (fd < 0) return 1;

sn::Event event;
while (sn::readAll(fd, &event, sizeof event) && sn::valid(event)) {
    // Handle event.kind, event.axes, event.buttons, and event.device.
}
close(fd);
```

`openEvents` connects to the socket, sends the hello record, and returns a
blocking descriptor by default. `sn::readAll` is a convenience for reading one
complete record. Nonblocking clients can pass `true` as the second argument to
`openEvents` and handle partial reads with their own event loop.

For dispatch-based clients, `sn::Stream` accepts a queue and callback, reconnects
after service startup or disconnection, and invokes the callback on that queue.
On a stream disconnection it reports a `reset` event with the
`disconnected` flag before retrying.

## Related control socket

The service's request API is a separate newline-delimited JSON protocol at
`/tmp/axial-$UID/events.control` (or the `AXIAL_SOCKET` path with
`.control` appended). The bundled `axialctl` command uses it for `status`,
`config`, `commands`, and configuration updates. It is not part of the binary
event record stream described here.
