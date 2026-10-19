# Live fetch smoke (opt-in, needs network)

Network-dependent end-to-end tests against public endpoints. Not part of the
default offline cram run (`moon cram test tests/cram`); run explicitly with:

```text
moon cram test tests/live
```

Every case pins `--backend local`, so these fixtures neither depend on a
`$DEEPSEEK` key nor spend DeepSeek Fetch requests. That keeps them stable: the
DeepSeek backend's rendering of the same page is not byte-stable across runs.
Exercise the DeepSeek backend by hand instead — see README.md.

## Fetch a static HTML page

example.com is the only convenient always-up target; its body text is the
site's, so update this fixture when the page changes.

```mooncram
$ skills-web-fetch.exe --backend local https://example.com/
Title: Example Domain

This domain is for use in documentation examples without needing permission. This is not a service; avoid relying on it for testing and monitoring purposes.
```

## HTTP 404 surfaces an error and exits 1

```mooncram
$ skills-web-fetch.exe --backend local https://example.com/definitely-missing-xyz
error: HTTP 404 Not Found for https://example.com/definitely-missing-xyz
[1]
```
