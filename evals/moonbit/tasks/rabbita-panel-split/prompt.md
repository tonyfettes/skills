This Rabbita (MoonBit) web app is a small ops console: a session log fills
the page, and a bottom "terminal" drawer accepts commands. Ctrl+` or the
header button toggles the drawer. Everything currently lives in one
package: `main/client.mbt`.

Refactor the terminal drawer into its own package inside this module, the
way a subsystem headed for reuse would be organized: the drawer package
owns its messages and its slice of state, and the root package wires it in.
While you are in there, ship one small feature: when the drawer opens, its
text input should be focused so the user can type immediately.

Everything else must behave exactly as before: Ctrl+` and the header button
still toggle the drawer, submitted commands still append to the session
log, and `moon check` must pass when you are done.

Work only inside the current directory — never read, search, or write
anything outside it.
