# Code Coverage

Full coverage workflow: instrument tests, generate reports in multiple formats,
upload to CI services. Coverage is **branch-based** — each coverage point is the
start of a branch, counted per execution.

For quick gap-hunting during development, `moon coverage analyze` (below) is
usually all you need; the manual `moon test --enable-coverage` + `moon coverage
report` pipeline is for CI and report files.

## Quick analysis (one command)

`moon coverage analyze` runs tests with instrumentation AND reports in one step.
Flags after `--` go to the report tool:

```sh
moon coverage analyze -- -f summary                     # per-file covered/total
moon coverage analyze -- -f caret -F path/to/file.mbt   # caret marks under uncovered lines
moon coverage analyze -p mymod/mypkg -- -f summary      # limit to one package
```

Workflow: run it, then drive uncovered branches through the **public API** (add
tests, don't contort the code). See `refactoring.md` for the full loop.

## Manual pipeline (test, then report)

```sh
moon test --enable-coverage      # recompiles with instrumentation if needed
moon coverage report -f summary  # consume the collected data
```

`moon test --enable-coverage` drops `moonbit_coverage_*.txt` files under the
build directory (e.g. `_build/wasm-gc/debug/test/`); `moon coverage report`
picks them up from there.

### Report formats (`-f`)

| Format | Output | Use when |
|---|---|---|
| `summary` | stdout, `file: covered/total` per file | quick per-file % check |
| `caret` | stdout, carets under uncovered code | pinpointing exact uncovered branches |
| `bisect` (default) | `bisect.coverage` file | OCaml Bisect tooling |
| `coveralls` | `coveralls.json` | Coveralls / CodeCov upload (line-based JSON) |
| `cobertura` | Cobertura XML | Jenkins/GitLab-style CI dashboards |
| `html` | `_coverage/` directory | human browsing |

Other useful report flags (see `moon coverage report --help` for all):
`-o <file>` output path, `-p <pkg>` / `-F <file>` limit scope,
`--ignore-missing-files`, `--absolute-file-paths`.

### HTML report

`moon coverage report -f html` writes `_coverage/`; open `index.html` for the
file list with percentages. In per-file pages, each coverage point is a
highlighted character: green = covered, red = not covered; yellow lines are
partially covered. Unhighlighted lines are not branch starts — they share the
coverage of the closest covered line above.

## CI integration (Coveralls / CodeCov)

`--send-to coveralls|codecov` uploads directly. GitHub Actions example:

```sh
moon test --enable-coverage
moon coverage report \
    -f coveralls \
    -o codecov_report.json \
    --service-name github \
    --service-job-id "$GITHUB_RUN_NUMBER" \
    --service-pull-request "${{ github.event.number }}" \
    --send-to coveralls
# env: COVERALLS_REPO_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Related flags: `--coveralls-token`, `--service-number`,
`--coveralls-parallel` (parallel builds), `--coveralls-include-git-info`.

## Cleaning up

```sh
moon coverage clean   # remove coverage artifacts (stale data skews reports)
```

Run it when switching branches or after large refactors, so old
`moonbit_coverage_*` files don't pollute the next report.

## Skipping coverage

- Attribute `#coverage.skip` on a function excludes all its coverage points.
- Deprecated functions are automatically excluded — no need to chase 100% on
  code kept only for compatibility.
