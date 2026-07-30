# Contributing to `csiapps` (R)

Thanks for improving `csiapps`. A few pointers:

- **Using the package to build an app?** You're in the wrong place — see the
  [user documentation](https://csiontario.github.io/csiapps/) (tutorials for
  [Shiny](https://csiontario.github.io/csiapps/shiny-apps/) apps, the sandbox,
  and the REST API), or the
  [R function reference](https://csiontario.github.io/csiapps-r/reference/).

- **Shipping a change to the package?** Follow
  **[Releasing csiapps](https://csiontario.github.io/csiapps/releasing/)** — it is
  the canary→publish playbook: validate the change against the
  [`dummy-r-shiny`](https://github.com/CSIOntario/dummy-r-shiny) regression
  harness locally, push to a branch, re-validate on the deployed dummy app, then
  merge, tag, and update the docs. Open the **R** tab on that page.

## Quick start

```bash
git clone https://github.com/CSIOntario/csiapps-r csiapps
git clone https://github.com/CSIOntario/dummy-r-shiny   # sibling checkout
cd csiapps
```

```r
# install.packages(c("devtools", "pkgload"))
devtools::install_deps(dependencies = TRUE)
devtools::load_all()
devtools::test()
```

The regression harness loads `../csiapps` with `pkgload::load_all()`, so keep
the two repos as siblings on disk and your edits are live in the dummy app on
every run — no reinstall step.

## Before you open a PR

```r
devtools::document()   # man/ and NAMESPACE are committed — regenerate them
devtools::test()
devtools::check()      # slower, but catches doc/NAMESPACE/example problems
```

- `man/` and `NAMESPACE` are **generated** by roxygen2 and checked in. Edit the
  roxygen comments above the function, never the `.Rd` files.
- New exported functions need an entry in `_pkgdown.yml` under `reference:`, or
  pkgdown fails the build for undocumented topics.
- User-visible changes get written up in the GitHub Release for the version that
  ships them — the package has no changelog file, so the release body is the
  changelog. If the behaviour also differs from the Python package, add a row to
  the [parity checklist](https://csiontario.github.io/csiapps/parity/).

## Sandbox mode is the default

Every call routes to the local in-memory sandbox until `CSIAPPS_ENV=production`
is set (or `options(csiapps.sandbox = FALSE)`), so tests and local development
never touch the production warehouse. Keep it that way: a test that needs
credentials belongs in the dummy app's live suite, not in `tests/testthat/`.

## `csiapps` is two packages

There is a Python sibling, [`csiapps-py`](https://github.com/CSIOntario/csiapps-py),
with full feature parity. A change that adds or renames public surface in one
language should either land in the other too, or be recorded as an intentional
divergence in the
[parity checklist](https://csiontario.github.io/csiapps/parity/).
