# Live fetch smoke (opt-in, needs network)

Network-dependent end-to-end tests against public endpoints. Not part of the
default offline cram run (`moon cram test tests/cram`); run explicitly with:

```text
moon cram test tests/live
```

## Fetch a static HTML page

```mooncram
$ skills-web-fetch.exe https://example.com/
Title: Example Domain

# Example Domain

This domain is for use in documentation examples without needing permission. Avoid use in operations.

Learn more
```

## HTTP 404 surfaces an error and exits 1

```mooncram
$ skills-web-fetch.exe https://example.com/definitely-missing-xyz
error: HTTP 404 Not Found for https://example.com/definitely-missing-xyz
[1]
```
