---
title: "Encoding every path segment alike breaks index ids, which are themselves paths"
date: 2026-08-20
category: logic-errors
module: arangox-api
problem_type: logic_error
component: database
severity: high
symptoms:
  - "`Arangox.Api.Indexes.get/3` and `Arangox.Api.Indexes.delete/3` answered HTTP 400 for every valid index identifier, because the request left as `GET /_api/index/capture_1787176566%2F284576`"
  - "Every index read and every index delete in the resource surface was unusable; operations taking single-part values were unaffected"
  - "Both gates over the API surface stayed green — the address `/_api/index/{index-id}` matches the server's own API description exactly"
  - "The defect appeared only when a response-recording script called the operation with a real index identifier against a live server"
root_cause: logic_error
resolution_type: code_fix
related_components:
  - testing_framework
tags: [path-encoding, percent-encoding, api-surface, conformance-gate, index-identifier, adapter-pattern, elixir, arangox]
---

# Encoding every path segment alike breaks index ids, which are themselves paths

## Problem

`Arangox.Api.Client` builds a request path by percent-encoding one segment at a time, so a `/` inside an interpolated value becomes `%2F` and cannot add path depth. An ArangoDB index identifier is itself a two-part path — `collection-name/number` — so every index read and every index delete in the `Arangox.Api.*` surface addressed `/_api/index/<collection>%2F<number>`, which the server rejects with HTTP (Hypertext Transfer Protocol) status 400.

## Symptoms

Two operations were unusable for every valid argument:

- `Arangox.Api.Indexes.get/3` (`lib/arangox/api/indexes.ex:249-257`) and `Arangox.Api.Indexes.delete/3` (`:194-200`) are the only operations in the surface whose path parameter is a composite identifier. Given an identifier of the shape the server hands out — the committed recording contains `capture_1787176566/284576` (`priv/arangodb/response-shapes-3.12.10.json`) — the request left as `GET /_api/index/capture_1787176566%2F284576`.
- A caller got `{:error, %Arangox.Error{status: 400, error_num: …}}` from the plain form and a raised `Arangox.Error` from the bang twin (`lib/arangox/api/client.ex:86-91`). The `:message` field carries ArangoDB's own wording (`lib/arangox/error.ex:30-35`), so the failure read as "you passed a bad index identifier" rather than as a driver defect. There was no argument that made the call succeed.
- Nothing else in the request path misbehaved. The pool, the deadline budget, the transaction header and the error contract all worked; the request was well-formed and addressed the wrong resource.

The rest of the surface was unaffected. Every other operation interpolates single-part values — a collection name, a document key, a view or analyzer name — where the uniform rule is correct. `Arangox.Api.Indexes.all/3` sends the collection as a forced query parameter rather than a path segment (`indexes.ex:62-70`), and `Arangox.Api.Graphs.vertex_edges/4` does the same with its `collection/key` vertex identifier (`lib/arangox/api/graphs.ex:788-796`), so neither touched the encoder that was wrong.

The failure surfaced during unrelated work: `priv/arangodb/capture_responses.exs` called `Indexes.get` with the index identifier its own fixture had just created, and recorded a 400 where a body was expected.

## What Didn't Work

No fix was tried and rejected here. The defect was not misdiagnosed; it was invisible to everything watching the surface. Both gates over the API surface were green while the two operations were unusable, and neither could have been otherwise.

**The conformance gate compares the surface against the server's own API description, and never supplies a value.** It fetches the description the tested server serves and checks address coverage in both directions (`test/arangox/api/conformance_test.exs:109-137`), that every query key the surface sends is documented at its address (`:139-155`), that every required query parameter is either forced or offered (`:159-186`), that a declared non-JSON (JavaScript Object Notation) request media matches (`:189-208`), and the pinned cardinality of 243 documented operations at 228 addresses against 230 surface operations (`:46-56`, `:91-107`). The address `/_api/index/{index-id}` matched, because the surface does address it correctly. Path parameters are not modelled at all beyond the template: `document_operations/1` extracts `required` and `query` only from parameter objects whose `in` is `"query"` (`:217-220`), and the address itself is built from the path string with the fragment dropped and the database prefix stripped (`:240-260`). A gate built this way answers whether an endpoint is spelled correctly and given the right parameter names, which is not where this defect was.

That scope was chosen deliberately, not inherited. When the gate was designed, three depths were on the table — address bijection only, addresses plus query parameters and request media, or full schema conformance including response bodies — and the middle one was picked, with response schemas explicitly out. So the gate has always been a transcription-drift detector: does every address exist, are the query-key sets right, is the declared request media right. Nothing in that charter ever covered what the driver puts on the wire.

There is also nothing in the description for such a gate to check against. ArangoDB documents `index-id` as a path parameter; the two-part convention is the server's own, stated in prose where it is stated at all. A comparison of two descriptions of shape cannot discover a convention that neither description contains.

**The unit-tier surface gate checks structure, which the wrong call satisfied exactly.** `test/arangox/api/surface_test.exs:62-71` asserts every path segment is a literal string or a bare argument, and that no literal segment carries `{`, `}`, `#` or `?`. Reaching the assertion is most of the proof, because `ApiSurface.segments/3` raises on any other shape (`test/support/api_surface.ex:110-128`). The rule exists so that no operation can assemble an address by string building, and the broken call — `segments: ["_api", "index", index_id]` — is precisely the shape it wants. A structural check over the source says what an operation is allowed to write down; it says nothing about what the adapter then does with the value, and nothing about what values callers pass.

**The one adapter test covering this area pins the opposite rule and is still correct.** `test/arangox/api/client_test.exs:109-118`, "a separator inside a segment is encoded, not treated as structure", asserts that `"a/b?c#d"` reaches the wire as `a%2Fb%3Fc%23d`. It passed then and passes now. Having a test named after the rule made the rule look settled; nobody had tested the exception because nobody had noticed the class of parameter that needs one.

**The live spot check exercised encoding, but with a value that has no separator.** `test/arangox/api/surface_integration_test.exs:61-68` round-trips the document key `a:b+c(d)e@f,g=h` through a real server — a genuine encoding test against a real endpoint, and blind to this defect, because the value is a single segment.

**This is the second time a shape-comparison gate passed while the wire form was wrong.** Earlier in the same body of work, thirteen operations sent a literal `{param}` or a literal `#fragment` to the server, because ArangoDB's description uses fragment suffixes (`/_api/index#persistent`) to mean "same address, different body". The then-current coverage gate compared method and path-template identities against the description and passed, because the templates did match. A reviewer reading emitted URL strings found it, not the gate. The response then was to assert over every emitted URL that none contains an un-interpolated `{param}` or a literal `#` — a check on the constructed request rather than on the template. That assertion covers corruption, not encoding, so it did not fire here; but it is the right shape of check, and the precedent worth generalizing.

## Solution

An operation declares a path parameter that is itself a path, and the adapter encodes that one segment by a different rule. Before, `path/1` had a single encoder for every segment:

```elixir
defp path(segments) do
  Enum.reduce_while(segments, {:ok, ""}, fn segment, {:ok, acc} ->
    value = to_string(segment)
    # … control-character refusal …
    {:cont, {:ok, acc <> "/" <> URI.encode(value, &URI.char_unreserved?/1)}}
  end)
end
```

After, the segment carries which encoder applies (`lib/arangox/api/client.ex:118-143`):

```elixir
defp path(segments) do
  Enum.reduce_while(segments, {:ok, ""}, fn segment, {:ok, acc} ->
    {value, encode} =
      case segment do
        {:path, v} -> {to_string(v), &encode_path/1}
        v -> {to_string(v), &encode_segment/1}
      end

    if control_byte?(value) do
      {:halt,
       {:error,
        %Error{
          message:
            "a path segment cannot contain control characters; the value is not " <>
              "echoed here because it may be a credential or a transaction identifier"
        }}}
    else
      {:cont, {:ok, acc <> "/" <> encode.(value)}}
    end
  end)
end

defp encode_segment(value), do: URI.encode(value, &URI.char_unreserved?/1)

# Separators are kept, each part between them encoded.
defp encode_path(value), do: value |> String.split("/") |> Enum.map_join("/", &encode_segment/1)
```

The two operations that need it declare the segment as `{:path, value}` (`lib/arangox/api/indexes.ex:194-200`; `get/3` declares it identically at `:249-257`):

```elixir
def delete(conn, index_id, opts \\ []) do
  Client.request(conn,
    method: :delete,
    segments: ["_api", "index", {:path, index_id}],
    opts: opts
  )
end
```

The adapter's moduledoc states the bound alongside the others it enforces (`lib/arangox/api/client.ex:45-48`): a parameter that is itself a path keeps its separators, everything between them is still encoded, and such a value can add path depth but cannot introduce a query or a fragment.

The surface extractor accepts the new segment form and still renders it as one address slot, so `/_api/index/{index_id}` is what both gates compare (`test/support/api_surface.ex:115-118`, with `address/1` at `:152-159`).

The fix sits on `feat/v0-8-modernization`, which has never been pushed and has no pull request open against it; it is not merged to `master`. Commit identifiers on that branch can be rewritten by a rebase or squash before it lands, so this doc cites file and line rather than a revision.

## Why This Works

The two encoders differ in exactly one character. `encode_segment/1` escapes everything `URI.char_unreserved?/1` does not admit — anything outside `A-Z`, `a-z`, `0-9`, `-`, `.`, `_` and `~` — which includes `/`, `?`, `#`, space, and every other character with meaning in a URL (uniform resource locator). `encode_path/1` splits the value on `/` and applies that same encoder to each part, so the only character that survives unescaped is the separator itself. An index identifier can therefore occupy two path slots, and a `?` or `#` anywhere inside it is still escaped, so the value cannot start a query string, open a fragment, or otherwise leave the path.

The protection the uniform rule provided is unchanged everywhere else. Its purpose is that a value the caller controls cannot silently change which endpoint is addressed: a collection name containing `/` must not turn `/_api/collection/{name}` into a deeper address that reaches a different route. That still holds for every segment the operation does not mark, which is all but two of them.

Two properties of the fix matter for keeping it that way. The exception is declared per operation, in the operation's own source, not inferred by the adapter — there is no sniffing for values that look like index identifiers, so a collection name that happens to contain `/` is still escaped even though an index identifier one line away is not. And the control-character refusal runs before either encoder (`lib/arangox/api/client.ex:126-134`), so the composite form does not weaken the one check that rejects rather than escapes.

Encoding has to happen in the adapter rather than in the caller. A caller who pre-encoded an index identifier would have it encoded again on the way out, and the `%2F` problem would return as `%252F`.

## Prevention

The general rule: a gate that compares shapes proves an operation is addressed and parameterized correctly, and proves nothing about the mapping from a value to the bytes on the wire. When a parameter is a string to the description but the system's own convention gives it internal structure — `collection/key`, `collection/number`, a Foxx mount point that begins with `/` — no description-comparison gate can see the structure, because the description does not carry it. Only a call with a real value can.

The mechanism that now does that is `priv/arangodb/capture_responses.exs`, written for a different reason: ArangoDB's served description has no reusable schemas at all and leaves 417 of its 752 responses without a content schema (recorded in `AGENTS.md`), so the shapes in each operation's `## Returns` section come from the server instead. The script builds a fixture — collection, document, index, graph and vertex, view, analyzer, user, stream transaction (`:59-104`) — sweeps every `GET` and `HEAD` whose arguments the fixture can fill (`:160-180`), runs a named list of writes (`:183-220`), makes a second pass against a cluster coordinator for the reads a single server answers 501 or 403 to (`:222-269`), tears the fixture down (`:271-278`), and writes `priv/arangodb/response-shapes-<tag>.json`. Writes are never swept, and the reason is stated where someone would be tempted to change it (`:16-18`): a sweep that guesses at write operations eventually calls something irreversible.

Coverage at the 3.12.10 pin: the committed recording holds 101 entries, of which 100 answered and one is `Administration.shutdown_progress/2`, which returns 405 unless the server is shutting down; 15 reads are skipped for want of a fixture nobody has built (a Foxx mount, a job identifier, a replication batch, a crash-dump identifier, a task identifier, an edge, a DB-Server identifier). 98 of the 230 operations carry a rendered `## Returns` section.

Exercising real values catches defect classes that description comparison structurally cannot:

1. **Value-to-URL mapping.** Encoding rules, separator handling, and the order in which arguments are interpolated. The address matches the document and the bytes are still wrong. This defect is the example.
2. **A parameter that means something other than its name suggests.** The sweep needed an explicit override because `Graphs.vertex_edges/4` wants a full `collection/key` vertex identifier while `Graphs.get_vertex/5` takes the collection and key separately, and both call the argument `vertex` (`capture_responses.exs:99-104`, `:151-158`). Calling both with real values is what forced the distinction into the open.
3. **Response shapes.** The recording is the only source for what an operation answers, since the description supplies no schema for most successes.
4. **Argument-name and signature warts.** The same run exposed argument names mangled by snake_case conversion across consecutive capitals; `db__server_id` was corrected to `dbserver_id` (`lib/arangox/api/cluster.ex:92`, `:514`), and `d_bserver` still stands at `cluster.ex:610` — cosmetic, since the wire name `DBserver` is correct, but only visible once something tries to call the function.

Concretely, for anyone working on this surface:

- An operation whose path parameter is a composite identifier declares the segment as `{:path, value}`. Anything else stays a bare argument, and the default is the safe one.
- Re-run `mix run priv/arangodb/capture_responses.exs` with the compose stack up whenever the version pin moves or an operation's arguments change, and read the errored and skipped lists rather than only the recorded shapes — an operation that answers an error where a body was expected is the signal this defect produced.
- One gap remains open: nothing in the unit tier pins the composite-path encoding. `test/arangox/api/client_test.exs:109-118` pins the uniform rule, and no test asserts that a `{:path, value}` segment reaches the wire with its separator intact, so today that guarantee rests on the recording script being re-run rather than on `mix test`.

## Related Issues

- [A code generator guards against transcription errors, not judgment errors](../architecture-patterns/codegen-guards-transcription-not-judgment-errors.md) — the same subsystem, and the decision that made the conformance gate the surface's completeness guarantee. This defect marks the edge of what that guarantee covers: the gate carries address, parameter and media coverage, and cannot carry value semantics. That doc also sorts defects into transcription and judgment, and files encoding bugs under transcription as the kind a generator handles well; freezing the corpus did not remove that class, it moved it into the hand-written adapter, where neither a generator nor a gate is watching.
- [DBConnection's :timeout is a deadline, not a duration you can reuse downstream](../architecture-patterns/dbconnection-timeout-is-a-deadline-not-a-duration.md) — a different subsystem, the same shape of miss: a design that was internally coherent, survived repeated review, and was wrong about a fact outside its own frame.
