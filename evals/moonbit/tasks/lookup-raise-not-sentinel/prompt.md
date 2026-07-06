This MoonBit project provides an in-memory service registry (see
`registry/registry.mbt`).

Add a method

- `Registry::port_of(self : Registry, name : String)` returning the port
  (`Int`) registered for `name`.

Requirements:

- Looking up a service that is not registered is an **expected condition**:
  callers must be able to detect and handle it programmatically, and the
  failure must carry which service name was missing. The failure value must
  implement `Show`, and its rendered text must contain the missing service
  name (operators grep for it in logs). This project's review guidelines
  treat sentinel return values (0, -1, magic defaults) as bugs.
- The project must pass `moon check` when you are done. You may add tests of
  your own.

Work only inside the current directory.
