# csiapps

## Installation

`csiapps` is distributed from
[GitHub](https://github.com/CSIOntario/csiapps-r) — there is no CRAN
release, so the ref you install decides what you get:

``` r

# install.packages("remotes")
remotes::install_github("CSIOntario/csiapps-r")          # main — the last released state
remotes::install_github("CSIOntario/csiapps-r@v0.1.4")   # a pinned release (use this in apps)
remotes::install_github("CSIOntario/csiapps-r@staging")  # unreleased, pre-validation
```

Deployed apps should pin a tag rather than track `main`; on Posit
Connect Cloud that pin lives in the app’s `manifest.json` as a commit
SHA. See
[CONTRIBUTING.md](https://csiontario.github.io/csiapps-r/CONTRIBUTING.html#branches-which-ref-serves-whom).

## Usage

Please refer to
[`vignette("csiapps")`](https://csiontario.github.io/csiapps-r/articles/csiapps.md)
and
[`vignette("api")`](https://csiontario.github.io/csiapps-r/articles/api.md)
for more information on how to use this library.

`csiapps` is also available for Python. The [cross-language
documentation](https://csiontario.github.io/csiapps/) shows R and Python
usage side by side and includes a [parity
checklist](https://csiontario.github.io/csiapps/parity/) mapping every
function between the two.

## Contributing

See
[CONTRIBUTING.md](https://csiontario.github.io/csiapps-r/CONTRIBUTING.md).
Shipping a change to the package itself goes through [Releasing
csiapps](https://csiontario.github.io/csiapps/releasing/) — validate
against the
[`dummy-r-shiny`](https://github.com/CSIOntario/dummy-r-shiny) harness
first.
