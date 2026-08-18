defmodule Arangox.Api.BatchRequests do
  @moduledoc """
  Provides API endpoint related to batch requests
  """

  @default_client Arangox.Api.Client

  @doc """
  Execute a batch request

  > **WARNING:**
  The `/_api/batch` endpoint was deprecated in v3.8.0 and has been removed
  in v3.12.3.

  Executes a batch request. A batch request can contain any number of
  other requests that can be sent to ArangoDB in isolation. The benefit of
  using batch requests is that batching requests requires less client/server
  roundtrips than when sending isolated requests.

  All parts of a batch request are executed serially on the server. The
  server will return the results of all parts in a single response when all
  parts are finished.

  Technically, a batch request is a multipart HTTP request, with
  content-type `multipart/form-data`. A batch request consists of an
  envelope and the individual batch part actions. Batch part actions
  are "regular" HTTP requests, including full header and an optional body.
  Multiple batch parts are separated by a boundary identifier. The
  boundary identifier is declared in the batch envelope. The MIME content-type
  for each individual batch part must be `application/x-arango-batchpart`.

  Please note that when constructing the individual batch parts, you must
  use CRLF (`\r\n`) as the line terminator as in regular HTTP messages.

  The response sent by the server will be an `HTTP 200` response, with an
  optional error summary header `x-arango-errors`. This header contains the
  number of batch part operations that failed with an HTTP error code of at
  least 400. This header is only present in the response if the number of
  errors is greater than zero.

  The response sent by the server is a multipart response, too. It contains
  the individual HTTP responses for all batch parts, including the full HTTP
  result header (with status code and other potential headers) and an
  optional result body. The individual batch parts in the result are
  separated using the same boundary value as specified in the request.

  The order of batch parts in the response will be the same as in the
  original client request. Client can additionally use the `Content-Id`
  MIME header in a batch part to define an individual id for each batch part.
  The server will return this id is the batch part responses, too.

  ## Request Body

  **Content Types**: `text/plain; charset=utf-8`
  """
  @spec execute_batch_request(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def execute_batch_request(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.BatchRequests, :execute_batch_request},
      url: "/_db/#{database_name}/_api/batch",
      body: body,
      method: :post,
      request: [{"text/plain; charset=utf-8", :map}],
      response: [{200, :null}, {400, :null}, {405, :null}],
      opts: opts
    })
  end
end
