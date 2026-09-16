# Vendored ArangoDB `errorNum` table

This directory pins the error table that `Arangox.Errno` is generated from.
Everything needed to reproduce the generated module is here — no network access
is required to regenerate, and nothing is fetched at build or run time.

## The pinned table

| | |
| --- | --- |
| File | `errors-3.12.10.dat` |
| Source | <https://raw.githubusercontent.com/arangodb/arangodb/3.12.10/lib/Basics/errors.dat> |
| Upstream path | `lib/Basics/errors.dat` |
| Pinned tag | `3.12.10` |
| Retrieved | 2026-08-07 |
| Size | 58,191 bytes |
| SHA-256 | `64397475bfe2c988ca42389bed44a57679d8bbdcef0cd6dad6ad899999c9d13f` |
| Entries | 347 |
| `errorNum` range | 0..21005 |

**This file is byte-identical to what ArangoDB publishes and must stay that
way.** It is never hand-edited. `gen_errno.exs` asserts the digest above on
every run and refuses to proceed if it does not match.

The tag is deliberately the same one `docker-compose.yml` defaults to.
`Arangox.Errno.tag/0` carries it at runtime and is the driver's single
version pin: the API conformance gate asserts it against the live server's
`/_api/version` before comparing anything, so the error semantics compiled
into the driver and the server the API surface is verified against cannot
drift apart silently.

Each data line is `CONSTANT,errorNum,"short message","long description"`:

```
ERROR_NO_ERROR,0,"no error","No error has occurred."
ERROR_ARANGO_CONFLICT,1200,"conflict","Will be raised when updating or deleting a document and a conflict has been detected."
ERROR_ARANGO_DOCUMENT_NOT_FOUND,1202,"document not found","Will be raised when a document with a given identifier is unknown."
```

Only the constant and the number are used. Go's driver generates named integer
constants from the same table; Elixir's idiom is pattern matching, so this
generates atoms instead.

## Reason-atom naming

`ERROR_ARANGO_CONFLICT` → `:arango_conflict`. Strip the `ERROR_` prefix,
downcase, keep the underscores.

This is a **public pattern-matching surface** and is stable. The constant names
are unique, so the mapping is injective; the generator asserts that. The short
messages are not unique and contain spaces and `printf` format specifiers
(`"icu error: %s"`), so they are not used for naming.

## Unknown codes

A number absent from the table maps to **`:unknown`**. A server newer than the
pinned tag can introduce codes, and a caller matching on
`%Arangox.Error{reason: reason}` must not crash or receive `nil` when it does.
The `:status` and the raw `:error_num` are preserved on the error either way, so
the number the server actually sent is never lost.

`:unknown` is asserted by the generator not to collide with any generated atom,
and by `Arangox.ErrnoTest` not to collide with any transport reason either.

## Regenerating

```sh
mix run priv/arangodb/gen_errno.exs
```

It writes `lib/arangox/errno.ex`, which **is committed**. The
generator is deterministic: running it twice produces a byte-identical module.

## Updating to a new server tag

Do this as part of the whole-driver tag move — "Updating to a new server tag"
in `AGENTS.md` — in the same change as the `docker-compose.yml` default, not
separately.

1. Download the new `errors.dat` at the new tag into this directory as
   `errors-<tag>.dat`. Do not edit it.
2. Update the pin table above (tag, date, size, SHA-256, entry count, range) and
   `expected_sha256`, `vendored` and `tag` in `gen_errno.exs`.
3. Re-run the generator. Review the diff of `lib/arangox/errno.ex` — that diff
   is the server's error-code change.
4. A **removed or renumbered** code is a breaking change for applications
   pattern-matching on the atom. Note it in `CHANGELOG.md`. Added codes are not
   breaking: before the refresh they resolved to `:unknown`.
