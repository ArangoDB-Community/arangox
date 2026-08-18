defmodule Arangox.ContractClients.NoAlive do
  @moduledoc """
  Implements `Arangox.Client` **without** `alive?/1`, which is optional since
  1.0. Compiling this module at all is half the test: omitting an optional
  callback must not warn or fail to compile.

  Answers `200` to everything except `/boom`, which returns an error whose
  reason is in `Arangox.Client.connection_lost_reasons/0`. Every response
  carries the socket it was served on in an `x-socket` header, so a test can see
  that a reconnect really produced a **new** socket rather than reusing the one
  that was declared lost.
  """

  @behaviour Arangox.Client

  alias Arangox.{Connection, Error, Request, Response}

  @impl true
  def connect(_endpoint, _opts), do: {:ok, make_ref()}

  @impl true
  def request(%Request{path: path}, opts, %Connection{} = state) when is_list(opts) do
    if String.ends_with?(path, "/boom") do
      {:error, %Error{reason: :closed, message: "connection lost"}, state}
    else
      {:ok, %Response{status: 200, headers: [{"x-socket", inspect(state.socket)}], body: nil},
       state}
    end
  end

  @impl true
  def close(%Connection{}), do: :ok
end

defmodule Arangox.ContractClients.Alive do
  @moduledoc """
  The same client with `alive?/1` implemented, exactly as a pre-0.8 client would
  have written it. Records the call in the process dictionary so a test can
  prove the callback was reached rather than defaulted.

  Lives in `test/support` rather than in the test file because
  `Arangox.ClientContractTest` **purges and deletes it** to prove the
  `Code.ensure_loaded?/1` guard in `Arangox.Client.implements_alive?/1` is
  needed. A module defined inside a `.exs` file has no beam file to be reloaded
  from, so the purge would be permanent and the test would prove nothing.
  """

  @behaviour Arangox.Client

  alias Arangox.{Connection, Request, Response}

  @impl true
  def connect(_endpoint, _opts), do: {:ok, make_ref()}

  @impl true
  def alive?(%Connection{}) do
    Process.put(:alive_called, true)
    false
  end

  @impl true
  def request(%Request{}, opts, %Connection{} = state) when is_list(opts),
    do: {:ok, %Response{status: 200, headers: [], body: nil}, state}

  @impl true
  def close(%Connection{}), do: :ok
end

defmodule Arangox.ContractClients.Legacy do
  @moduledoc """
  A third-party client written against the pre-0.8 two-argument `request/2`
  callback.

  `@behaviour` is deliberately **not** declared: the point is that such a module
  still compiles cleanly on its own, and only fails when arangox calls it — so
  the failure has to carry the explanation.
  """

  alias Arangox.{Connection, Request, Response}

  def connect(_endpoint, _opts), do: {:ok, make_ref()}

  def request(%Request{}, %Connection{} = state),
    do: {:ok, %Response{status: 200, headers: [], body: nil}, state}

  def close(%Connection{}), do: :ok
end
