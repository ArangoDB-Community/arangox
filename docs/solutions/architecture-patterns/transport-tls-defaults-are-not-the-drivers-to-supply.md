---
title: "Check what the transport already does before writing TLS defaults for it"
date: 2026-08-10
category: architecture-patterns
module: arangox-client
problem_type: architecture_pattern
component: database
severity: high
applies_when:
  - Adding or reviewing TLS defaults in a driver that wraps Mint, :ssl, or :gen_tcp
  - Writing a shared options builder so two clients behave the same way
  - Reading a plan step that says a dependency does not supply something
  - Deciding whether a transport option belongs to the driver or to the caller
tags: [tls, ssl, mint, otp, security-defaults, transport, elixir, arangox]
---

# Check what the transport already does before writing TLS defaults for it

## Context

Arangox has two clients. `Arangox.MintClient` speaks HTTP through `:mint`;
`Arangox.VelocyClient` speaks VelocyStream by calling `:ssl.connect/4` and
`:gen_tcp.connect/4` itself.

The 1.0 plan said to build one TLS option builder that both clients would use.
Its argument was that "apply the same defaults as Mint" is not an operation
anyone can perform, because Mint assembles its hostname rules and version
filtering inside a private module — so the VelocyStream path, which never goes
near Mint, could not inherit them and had to be given them explicitly.

That argument is persuasive and it is wrong. A builder was written supplying
peer verification, an HTTPS hostname-match function, a TLS 1.2 floor, system
trust material and Server Name Indication. It was deleted a day later, along
with the `:castore` dependency added to support it. Two facts killed it, and
both were a few minutes of checking away.

**Mint already builds that exact list.** `Mint.Core.Transport.SSL` (in the
`:mint` dependency, `~> 1.9`) has a defaults function returning
`server_name_indication`, `versions` filtered to TLS 1.2 and 1.3,
`verify: :verify_peer`, `depth`, `secure_renegotiate` and `reuse_sessions`,
plus a step that fills in `cacerts` from `:public_key.cacerts_get/0` or CAStore.
The builder was a reimplementation of code sitting in `deps/`.

**`:ssl` refuses rather than accepting.** Since OTP 26 the client default is
`verify: :verify_peer`, and with no trust material it will not connect at all.
Measured on OTP 28:

```
:ssl.connect(~c"localhost", 8002, [packet: :raw, mode: :binary, active: false], 5000)
#=> {:error, {:options, :incompatible, [verify: :verify_peer, cacerts: :undefined]}}
```

So the VelocyStream path did not silently accept bad certificates either. It
failed loudly with an unhelpful message, which is a documentation problem, not
a security one.

The actual defect was much narrower than the plan supposed, and worse.
`Arangox.MintClient.connect/2` contained:

```elixir
transport_opts = Keyword.put_new(transport_opts, :verify, :verify_none)
```

The driver was not failing to supply a safe default. It was taking Mint's safe
default and turning it off, for everyone, while documenting `:ssl_opts` as
options passed through to the transport. Deleting that line was the whole fix.

## Guidance

Before writing a security default into a driver, read what the transport does
with the same option when you pass nothing. Read its source, or measure it, or
both. Do not infer it from the age of the ecosystem or from what the option
looked like five years ago — `:ssl` changed its client default in OTP 26 and
Mint has never shipped an unsafe one.

Then let the transport keep the decision. Pass the caller's options through
unchanged, except for the specific options your own framing depends on. In
arangox those are `mode` for the Mint client and `packet`, `mode` and `active`
for the VelocyStream client; they are merged last so they always win, and two
tests pin that they cannot be overridden.

Where the transport's own default is safe but its error is unreadable, fix the
error rather than the default. `:ssl`'s `{:options, :incompatible, ...}` names
neither the cause nor the remedy, and it is the first thing anyone enabling TLS
on the VelocyStream client meets, so `Arangox.VelocyClient` translates that one
tuple into a message naming `ssl_opts`. That is error reporting, which the
driver already owns everywhere else, and it adds no default.

If relying on the transport is only safe above some version, enforce the
version. Arangox's `mix.exs` refuses to build below OTP 26, because on 24 and
25 `:ssl` still defaulted to `verify_none` and a pass-through driver on those
releases would accept anything without saying so. Refusing to compile is how
that stops being a quiet fact.

Do not add a bundled certificate authority list to reach a database. Arangox
declined `:castore` for this reason. A database is served by a private
authority, a self-signed certificate, or a public certificate. The first wants
`ssl_opts: [cacertfile: ...]`, the second wants `verify: :verify_none` chosen
knowingly, and the third is already covered by the system store. A public root
list answers none of the three, and falling back to one means silently trusting
several hundred authorities nobody picked in order to reach a server they own.

## Why This Matters

A builder that duplicates its transport does not sit still. Mint and OTP keep
improving their defaults — depth limits, cipher selection, version floors — and
a driver holding its own copy silently opts every user out of those
improvements. The copy also has to be maintained by people who will not be
watching OTP release notes for changes to `:ssl`.

The plan's reasoning was also inverted in a way worth noticing. It argued from
"the transports supply nothing" to "we must supply everything", when the truth
was "the transports supply everything and we broke one of them." Chasing the
first story produced 259 lines that had to be deleted. Checking the premise
would have produced a three-line deletion straight away.

There is a testing consequence too. Once the driver holds no TLS opinion, most
TLS tests written against it are really tests of Mint and `:ssl`, and they
belong to those projects. The tests worth keeping are the ones about the
driver's own behaviour: that no override is reintroduced, and that the caller's
options arrive intact. Arangox's TLS tests went from thirty to twenty-five on
that basis, and the pruning immediately exposed a real gap — nothing had been
testing that `:client_opts` merges into `:transport_opts` rather than replacing
it, which is the path where supplying one unrelated option silently discards
the caller's trust material.

## When to Apply

Whenever a plan, a review, or your own instinct says a dependency does not
provide something you need. That claim is cheap to check and expensive to get
wrong in both directions: build what already exists and you carry a duplicate
forever, assume something exists when it does not and you ship the gap.

It applies with most force to security defaults, because a wrong one is
invisible in tests. Every arangox test passed with `verify: :verify_none` in
place. Nothing failed. The behaviour was only visible by reading the line.

## Examples

**Before** — the driver overriding its transport, in
`Arangox.MintClient.connect/2`:

```elixir
transport_opts = Keyword.get(opts, :ssl_opts, [])
transport_opts = Keyword.merge([timeout: connect_timeout], transport_opts)

transport_opts =
  if ssl?,
    do: Keyword.put_new(transport_opts, :verify, :verify_none),
    else: transport_opts

client_opts = Keyword.get(opts, :client_opts, [])
options = Keyword.merge([transport_opts: transport_opts], client_opts)
```

Two problems. The `verify_none` line disables Mint's verification. And the
final merge lets `:client_opts` replace `:transport_opts` wholesale, so a
caller who sets one unrelated option there loses everything given under
`:ssl_opts`, trust material included.

**After** — pass through, force only what the driver's own framing needs:

```elixir
client_opts = Keyword.get(opts, :client_opts, [])
transport_opts = [timeout: connect_timeout] ++ given

options =
  client_opts
  |> Keyword.update(:transport_opts, transport_opts, &Keyword.merge(transport_opts, &1))
  |> Keyword.merge(mode: :passive)
```

`mode: :passive` is merged last because the client's receive loop depends on
it. Everything else is the caller's to decide and Mint's to default.

See `lib/arangox/client/mint.ex` and `lib/arangox/client/velocy.ex` for the
current shape, and
[DBConnection's :timeout is a deadline, not a duration you can reuse downstream](dbconnection-timeout-is-a-deadline-not-a-duration.md)
for another case in this driver where a locally coherent design survived review
while being wrong about how a dependency behaves.
