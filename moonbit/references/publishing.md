# Publishing & Dependency Management (Advanced)

Publishing modules to mooncakes.io and the dependency tooling around it.
Day-to-day `moon add/remove/update/fetch` and `moon.mod` basics are in
`toolchain.md`.

## Account setup (one-time)

```sh
moon register   # create a mooncakes.io account (interactive)
moon login      # log in with an existing account
moon whoami     # show login status and username
```

Success message: `API token saved to ~/.moon/credentials.json`.

## Pre-publish checklist

1. **Name**: must begin with your mooncakes.io username (`username/module`).
2. **Version**: required, must follow semver `MAJOR.MINOR.PATCH` (see below).
3. **Metadata** in `moon.mod` — shown on mooncakes.io alongside the README:

   | Field | Meaning |
   |---|---|
   | `license` | SPDX identifier (e.g. `"Apache-2.0"`) |
   | `keywords` | list of keywords |
   | `repository` | source repo URL |
   | `description` | short description |
   | `homepage` | module homepage URL |
   | `readme` | path to README (e.g. `"README.mbt.md"`) |

4. **Verify package contents** before pushing:

   ```sh
   moon package --list   # list files that would be included in the package
   ```

5. Run the usual pre-commit pass: `moon fmt`, `moon info`, `moon test`.

Then:

```sh
moon publish            # push the current module to mooncakes.io
moon publish --dry-run  # show what would happen without doing it
```

In a `moon.work` workspace, publish runs per member: `moon -C mod_a publish`.

## Versioning: semver + minimal version selection

Bump MAJOR for incompatible API changes, MINOR for backward-compatible
additions, PATCH for backward-compatible fixes. moon resolves dependencies with
[minimal version selection](https://research.swtch.com/vgo-mvs) (MVS): it picks
the *minimum* version satisfying all declared requirements, so consumers get a
dependency graph as close as possible to what authors developed against —
provided everyone follows semver honestly.

## Publish filtering: `include` / `exclude`

Control which files go into the published package. Gitignore syntax;
**`include` is applied after `exclude`** (include wins for re-adding subsets):

```
options(
  exclude: ["build"],
  "include": ["build/assets"],   // keep build/assets, drop the rest of build/
)
```

Legacy `moon.mod.json`: top-level `"exclude"` / `"include"` arrays.
Always confirm the result with `moon package --list`.

## `scripts.postadd`

Runs automatically after a consumer `moon add`s your module, with cwd set to
the module root. Use sparingly — it executes arbitrary code on users' machines.

```
options(
  scripts: {
    "postadd": "python3 build.py",
  },
)
```

## Dependency tooling

- `moon tree` — display the dependency tree of the current module.
- `moon update` — refresh the registry index (do this when a freshly published
  version isn't found).
- `moon install <source>` — install a **binary package** globally (to
  `~/.moon/bin/` by default, override with `--bin <dir>`). Source can be a
  local path, a git URL (`--rev/--branch/--tag`), or a registry path
  `user/module/pkg[@version]`; append `/...` to install all matching main
  packages. Bare `moon install` (sync project deps) is deprecated — `moon
  check/build/test` sync dependencies automatically.
- `moon upgrade [--dev]` — upgrades the **toolchain** (moon/moonc), not module
  dependencies; `--dev` installs the latest development version, `-f` forces.
  To bump a dependency, `moon add user/module@version` again.
