# Changelog

## v0.7.0 (2024-02-20)

* Enhancements
  * Added support for ArangoDB JWT authentication via bearer tokens

* Breaking changes
  * `auth` start option now only accepts `{:basic, username, password}` or `{:bearer, token`
  * No longer authenticates with "root:" by default
  * Requires Elixir v1.7+.
