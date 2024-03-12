# Changelog

## v0.7.0 (2024-02-20)

* Breaking changes
  * Require Elixir v1.7+.
  * Use mint http as default client (VelocyStream will be deprecated in v3.12)
  * No longer authenticate with "root:" by default

* Enhancements
  * Add support for ArangoDB JWT authentication via bearer tokens
