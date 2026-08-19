defmodule Arangox.Api.Documents do
  @moduledoc """
  ArangoDB's Documents operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.Api.Client` for the options they all accept and
  for what a `404` answers.
  """

  alias Arangox.Api.Client

  @doc """
  Create a document

  Creates a new document from the document given in the body, unless there
  is already a document with the `_key` given. If no `_key` is given, a
  new unique `_key` is generated automatically. The `_id` is automatically
  set in both cases, derived from the collection name and `_key`.

  > **INFO:**
  An `_id` or `_rev` attribute specified in the body is ignored.


  If the document was created successfully, then the `Location` header
  contains the path to the newly created document. The `ETag` header field
  contains the revision of the document. Both are only set in the single
  document case.

  Unless `silent` is set to `true`, the body of the response contains a
  JSON object with the following attributes:
  - `_id`, containing the document identifier with the format `<collection-name>/<document-key>`.
  - `_key`, containing the document key that uniquely identifies a document within the collection.
  - `_rev`, containing the document revision.

  If the collection parameter `waitForSync` is `false`, then the call
  returns as soon as the document has been accepted. It does not wait
  until the documents have been synced to disk.

  Optionally, the query parameter `waitForSync` can be used to force
  synchronization of the document creation operation to disk even in
  case that the `waitForSync` flag had been disabled for the entire
  collection. Thus, the `waitForSync` query parameter can be used to
  force synchronization of just this specific operations. To use this,
  set the `waitForSync` parameter to `true`. If the `waitForSync`
  parameter is not specified or set to `false`, then the collection's
  default `waitForSync` behavior is applied. The `waitForSync` query
  parameter cannot be used to disable synchronization for collections
  that have a default `waitForSync` value of `true`.

  If the query parameter `returnNew` is `true`, then, for each
  generated document, the complete new document is returned under
  the `new` attribute in the result.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "_id" => string,
        "_key" => string,
        "_rev" => string
      }
  """
  @spec create(Arangox.conn(), binary, term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def create(conn, collection, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "document", collection],
      body: body,
      query: [
        wait_for_sync: "waitForSync",
        return_new: "returnNew",
        return_old: "returnOld",
        silent: "silent",
        overwrite: "overwrite",
        overwrite_mode: "overwriteMode",
        keep_null: "keepNull",
        merge_objects: "mergeObjects",
        refill_index_caches: "refillIndexCaches",
        version_attribute: "versionAttribute"
      ],
      opts: opts
    )
  end

  @doc """
  Create a document. Raises on error.

  See `create/3`.
  """
  @spec create!(Arangox.conn(), binary, term, keyword) :: term
  def create!(conn, collection, body, opts \\ []) do
    case create(conn, collection, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Create multiple documents

  Creates new documents from the documents given in the body, unless there
  is already a document with the `_key` given. If no `_key` is given, a new
  unique `_key` is generated automatically. The `_id` is automatically
  set in both cases, derived from the collection name and `_key`.

  The result body contains a JSON array of the
  same length as the input array, and each entry contains the result
  of the operation for the corresponding input. In case of an error
  the entry is a document with attributes `error` set to `true` and
  errorCode set to the error code that has happened.

  > **INFO:**
  Any `_id` or `_rev` attribute specified in the body is ignored.


  Unless `silent` is set to `true`, the body of the response contains an
  array of JSON objects with the following attributes:
  - `_id`, containing the document identifier with the format `<collection-name>/<document-key>`.
  - `_key`, containing the document key that uniquely identifies a document within the collection.
  - `_rev`, containing the document revision.

  If the collection parameter `waitForSync` is `false`, then the call
  returns as soon as the documents have been accepted. It does not wait
  until the documents have been synced to disk.

  Optionally, the query parameter `waitForSync` can be used to force
  synchronization of the document creation operation to disk even in
  case that the `waitForSync` flag had been disabled for the entire
  collection. Thus, the `waitForSync` query parameter can be used to
  force synchronization of just this specific operations. To use this,
  set the `waitForSync` parameter to `true`. If the `waitForSync`
  parameter is not specified or set to `false`, then the collection's
  default `waitForSync` behavior is applied. The `waitForSync` query
  parameter cannot be used to disable synchronization for collections
  that have a default `waitForSync` value of `true`.

  If the query parameter `returnNew` is `true`, then, for each
  generated document, the complete new document is returned under
  the `new` attribute in the result.

  Should an error have occurred with some of the documents,
  the `X-Arango-Error-Codes` HTTP header is set. It contains a map of the
  error codes and how often each kind of error occurred. For example,
  `1200:17,1205:10` means that in 17 cases the error 1200 ("revision conflict")
  has happened, and in 10 cases the error 1205 ("illegal document handle").
  """
  @spec create_many(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def create_many(conn, collection, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "document", collection],
      body: body,
      query: [
        wait_for_sync: "waitForSync",
        return_new: "returnNew",
        return_old: "returnOld",
        silent: "silent",
        overwrite: "overwrite",
        overwrite_mode: "overwriteMode",
        keep_null: "keepNull",
        merge_objects: "mergeObjects",
        refill_index_caches: "refillIndexCaches",
        version_attribute: "versionAttribute"
      ],
      opts: opts
    )
  end

  @doc """
  Create multiple documents. Raises on error.

  See `create_many/3`.
  """
  @spec create_many!(Arangox.conn(), binary, term, keyword) :: term
  def create_many!(conn, collection, body, opts \\ []) do
    case create_many(conn, collection, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Remove a document

  Unless `silent` is set to `true`, the body of the response contains a
  JSON object with the following attributes:
  - `_id`, containing the document identifier with the format `<collection-name>/<document-key>`.
  - `_key`, containing the document key that uniquely identifies a document within the collection.
  - `_rev`, containing the document revision.

  If the `waitForSync` parameter is not specified or set to `false`,
  then the collection's default `waitForSync` behavior is applied.
  The `waitForSync` query parameter cannot be used to disable
  synchronization for collections that have a default `waitForSync`
  value of `true`.

  If the query parameter `returnOld` is `true`, then
  the complete previous revision of the document
  is returned under the `old` attribute in the result.
  """
  @spec delete(Arangox.conn(), binary, binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete(conn, collection, key, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "document", collection, key],
      query: [
        wait_for_sync: "waitForSync",
        return_old: "returnOld",
        silent: "silent",
        refill_index_caches: "refillIndexCaches"
      ],
      opts: opts
    )
  end

  @doc """
  Remove a document. Raises on error.

  See `delete/3`.
  """
  @spec delete!(Arangox.conn(), binary, binary, keyword) :: term
  def delete!(conn, collection, key, opts \\ []) do
    case delete(conn, collection, key, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Remove multiple documents

  The body of the request is an array consisting of selectors for
  documents. A selector can either be a string with a key or a string
  with a document identifier or an object with a `_key` attribute. This
  API call removes all specified documents from `collection`.
  If the `ignoreRevs` query parameter is `false` and the
  selector is an object and has a `_rev` attribute, it is a
  precondition that the actual revision of the removed document in the
  collection is the specified one.

  The body of the response is an array of the same length as the input
  array. For each input selector, the output contains a JSON object
  with the information about the outcome of the operation. If no error
  occurred, then such an object has the following attributes:
  - `_id`, containing the document identifier with the format `<collection-name>/<document-key>`.
  - `_key`, containing the document key that uniquely identifies a document within the collection.
  - `_rev`, containing the document revision.
  In case of an error, the object has the `error` attribute set to `true`
  and `errorCode` set to the error code.

  If the `waitForSync` parameter is not specified or set to `false`,
  then the collection's default `waitForSync` behavior is applied.
  The `waitForSync` query parameter cannot be used to disable
  synchronization for collections that have a default `waitForSync`
  value of `true`.

  If the query parameter `returnOld` is `true`, then
  the complete previous revision of the document
  is returned under the `old` attribute in the result.

  Note that if any precondition is violated or an error occurred with
  some of the documents, the return code is still 200 or 202, but the
  `X-Arango-Error-Codes` HTTP header is set. It contains a map of the
  error codes and how often each kind of error occurred. For example,
  `1200:17,1205:10` means that in 17 cases the error 1200 ("revision conflict")
  has happened, and in 10 cases the error 1205 ("illegal document handle").
  """
  @spec delete_many(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def delete_many(conn, collection, body, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "document", collection],
      body: body,
      query: [
        wait_for_sync: "waitForSync",
        return_old: "returnOld",
        silent: "silent",
        ignore_revs: "ignoreRevs",
        refill_index_caches: "refillIndexCaches"
      ],
      opts: opts
    )
  end

  @doc """
  Remove multiple documents. Raises on error.

  See `delete_many/3`.
  """
  @spec delete_many!(Arangox.conn(), binary, term, keyword) :: term
  def delete_many!(conn, collection, body, opts \\ []) do
    case delete_many(conn, collection, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get a document

  Returns the document identified by the collection name and document key.
  The returned document contains three special attributes:
  - `_id`, containing the document identifier with the format `<collection-name>/<document-key>`.
  - `_key`, containing the document key that uniquely identifies a document within the collection.
  - `_rev`, containing the document revision.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "_id" => string,
        "_key" => string,
        "_rev" => string
      }
  """
  @spec get(Arangox.conn(), binary, binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def get(conn, collection, key, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "document", collection, key],
      opts: opts
    )
  end

  @doc """
  Get a document. Raises on error.

  See `get/3`.
  """
  @spec get!(Arangox.conn(), binary, binary, keyword) :: term
  def get!(conn, collection, key, opts \\ []) do
    case get(conn, collection, key, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get multiple documents

  > **WARNING:**
  The endpoint for getting multiple documents is the same as for replacing
  multiple documents but with an additional query parameter:
  `PUT /_api/document/{collection}?onlyget=true`. This is because a lot of
  software does not support payload bodies in `GET` requests.


  Returns the documents identified by their `_key` attribute.
  The body of the request _must_ contain a JSON array of either
  strings (the `_key` values to look up) or search documents.

  A search document _must_ contain at least a value for the `_key` field.
  A value for `_rev` _may_ be specified to verify whether the document
  has the same revision value, unless _ignoreRevs_ is set to false.

  Cluster only: The search document _may_ contain
  values for the collection's pre-defined shard keys. Values for the shard keys
  are treated as hints to improve performance. Should the shard keys
  values be incorrect ArangoDB may answer with a *not found* error.

  The returned array of documents contain three special attributes: 
  - `_id`, containing the document identifier with the format `<collection-name>/<document-key>`.
  - `_key`, containing the document key that uniquely identifies a document within the collection.
  - `_rev`, containing the document revision.
  """
  @spec get_many(Arangox.conn(), binary, term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def get_many(conn, collection, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "document", collection],
      body: body,
      forced: [{"onlyget", "true"}],
      query: [ignore_revs: "ignoreRevs"],
      opts: opts
    )
  end

  @doc """
  Get multiple documents. Raises on error.

  See `get_many/3`.
  """
  @spec get_many!(Arangox.conn(), binary, term, keyword) :: term
  def get_many!(conn, collection, body, opts \\ []) do
    case get_many(conn, collection, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get a document header

  Like `GET`, but only returns the header fields and not the body. You
  can use this call to get the current revision of a document or check if
  the document was deleted.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      string
  """
  @spec header(Arangox.conn(), binary, binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def header(conn, collection, key, opts \\ []) do
    Client.request(conn,
      method: :head,
      segments: ["_api", "document", collection, key],
      response: :revision,
      opts: opts
    )
  end

  @doc """
  Get a document header. Raises on error.

  See `header/3`.
  """
  @spec header!(Arangox.conn(), binary, binary, keyword) :: term
  def header!(conn, collection, key, opts \\ []) do
    case header(conn, collection, key, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Replace a document

  Replaces the specified document with the one in the body, provided there is
  such a document and no precondition is violated.

  The values of the `_key`, `_id`, and `_rev` system attributes as well as
  attributes used as sharding keys cannot be changed.

  If the `If-Match` header is specified and the revision of the
  document in the database is unequal to the given revision, the
  precondition is violated.

  If `If-Match` is not given and `ignoreRevs` is `false` and there
  is a `_rev` attribute in the body and its value does not match
  the revision of the document in the database, the precondition is
  violated.

  If a precondition is violated, an *HTTP 412* is returned.

  If the document exists and can be updated, then an *HTTP 201* or
  an *HTTP 202* is returned (depending on `waitForSync`, see below),
  the `ETag` header field contains the new revision of the document
  and the `Location` header contains a complete URL under which the
  document can be queried.

  Cluster only: The replace documents _may_ contain
  values for the collection's pre-defined shard keys. Values for the shard keys
  are treated as hints to improve performance. Should the shard keys
  values be incorrect ArangoDB may answer with a *not found* error.

  Optionally, the query parameter `waitForSync` can be used to force
  synchronization of the document replacement operation to disk even in case
  that the `waitForSync` flag had been disabled for the entire collection.
  Thus, the `waitForSync` query parameter can be used to force synchronization
  of just specific operations. To use this, set the `waitForSync` parameter
  to `true`. If the `waitForSync` parameter is not specified or set to
  `false`, then the collection's default `waitForSync` behavior is
  applied. The `waitForSync` query parameter cannot be used to disable
  synchronization for collections that have a default `waitForSync` value
  of `true`.

  Unless `silent` is set to `true`, the body of the response contains a
  JSON object with the following attributes:
  - `_id`, containing the document identifier with the format `<collection-name>/<document-key>`.
  - `_key`, containing the document key that uniquely identifies a document within the collection.
  - `_rev`, containing the new document revision.

  If the query parameter `returnOld` is `true`, then
  the complete previous revision of the document
  is returned under the `old` attribute in the result.

  If the query parameter `returnNew` is `true`, then
  the complete new document is returned under
  the `new` attribute in the result.

  If the document does not exist, then a *HTTP 404* is returned and the
  body of the response contains an error document.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "_id" => string,
        "_key" => string,
        "_oldRev" => string,
        "_rev" => string
      }
  """
  @spec replace(Arangox.conn(), binary, binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def replace(conn, collection, key, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "document", collection, key],
      body: body,
      query: [
        wait_for_sync: "waitForSync",
        ignore_revs: "ignoreRevs",
        return_old: "returnOld",
        return_new: "returnNew",
        silent: "silent",
        refill_index_caches: "refillIndexCaches",
        version_attribute: "versionAttribute"
      ],
      opts: opts
    )
  end

  @doc """
  Replace a document. Raises on error.

  See `replace/4`.
  """
  @spec replace!(Arangox.conn(), binary, binary, term, keyword) :: term
  def replace!(conn, collection, key, body, opts \\ []) do
    case replace(conn, collection, key, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Replace multiple documents

  Replaces multiple documents in the specified collection with the
  ones in the body, the replaced documents are specified by the `_key`
  attributes in the body documents.

  The values of the `_key`, `_id`, and `_rev` system attributes as well as
  attributes used as sharding keys cannot be changed.

  If `ignoreRevs` is `false` and there is a `_rev` attribute in a
  document in the body and its value does not match the revision of
  the corresponding document in the database, the precondition is
  violated.

  Cluster only: The replace documents _may_ contain
  values for the collection's pre-defined shard keys. Values for the shard keys
  are treated as hints to improve performance. Should the shard keys
  values be incorrect ArangoDB may answer with a `not found` error.

  Optionally, the query parameter `waitForSync` can be used to force
  synchronization of the document replacement operation to disk even in case
  that the `waitForSync` flag had been disabled for the entire collection.
  Thus, the `waitForSync` query parameter can be used to force synchronization
  of just specific operations. To use this, set the `waitForSync` parameter
  to `true`. If the `waitForSync` parameter is not specified or set to
  `false`, then the collection's default `waitForSync` behavior is
  applied. The `waitForSync` query parameter cannot be used to disable
  synchronization for collections that have a default `waitForSync` value
  of `true`.

  The body of the response contains a JSON array of the same length
  as the input array with the information about the identifier and the
  revision of the replaced documents. In each element has the following
  attributes:
  - `_id`, containing the document identifier with the format `<collection-name>/<document-key>`.
  - `_key`, containing the document key that uniquely identifies a document within the collection.
  - `_rev`, containing the new document revision.

  In case of an error or violated precondition, an error
  object with the attribute `error` set to `true` and the attribute
  `errorCode` set to the error code is built.

  If the query parameter `returnOld` is `true`, then, for each
  generated document, the complete previous revision of the document
  is returned under the `old` attribute in the result.

  If the query parameter `returnNew` is `true`, then, for each
  generated document, the complete new document is returned under
  the `new` attribute in the result.

  Note that if any precondition is violated or an error occurred with
  some of the documents, the return code is still 201 or 202, but the
  `X-Arango-Error-Codes` HTTP header is set. It contains a map of the
  error codes and how often each kind of error occurred. For example,
  `1200:17,1205:10` means that in 17 cases the error 1200 ("revision conflict")
  has happened, and in 10 cases the error 1205 ("illegal document handle").
  """
  @spec replace_many(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def replace_many(conn, collection, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "document", collection],
      body: body,
      query: [
        wait_for_sync: "waitForSync",
        ignore_revs: "ignoreRevs",
        return_old: "returnOld",
        return_new: "returnNew",
        silent: "silent",
        refill_index_caches: "refillIndexCaches",
        version_attribute: "versionAttribute"
      ],
      opts: opts
    )
  end

  @doc """
  Replace multiple documents. Raises on error.

  See `replace_many/3`.
  """
  @spec replace_many!(Arangox.conn(), binary, term, keyword) :: term
  def replace_many!(conn, collection, body, opts \\ []) do
    case replace_many(conn, collection, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Update a document

  Partially updates the document identified by the *document ID*.
  The body of the request must contain a JSON document with the
  attributes to patch (the patch document). All attributes from the
  patch document are added to the existing document if they do not
  yet exist, and overwritten in the existing document if they do exist
  there.

  The values of the `_key`, `_id`, and `_rev` system attributes as well as
  attributes used as sharding keys cannot be changed.

  Setting an attribute value to `null` in the patch document causes a
  value of `null` to be saved for the attribute by default.

  If the `If-Match` header is specified and the revision of the
  document in the database is unequal to the given revision, the
  precondition is violated.

  If `If-Match` is not given and `ignoreRevs` is `false` and there
  is a `_rev` attribute in the body and its value does not match
  the revision of the document in the database, the precondition is
  violated.

  If a precondition is violated, an *HTTP 412* is returned.

  If the document exists and can be updated, then an *HTTP 201* or
  an *HTTP 202* is returned (depending on `waitForSync`, see below),
  the `ETag` header field contains the new revision of the document
  (in double quotes) and the `Location` header contains a complete URL
  under which the document can be queried.

  Cluster only: The patch document _may_ contain
  values for the collection's pre-defined shard keys. Values for the shard keys
  are treated as hints to improve performance. Should the shard keys
  values be incorrect ArangoDB may answer with a `not found` error

  Optionally, the query parameter `waitForSync` can be used to force
  synchronization of the updated document operation to disk even in case
  that the `waitForSync` flag had been disabled for the entire collection.
  Thus, the `waitForSync` query parameter can be used to force synchronization
  of just specific operations. To use this, set the `waitForSync` parameter
  to `true`. If the `waitForSync` parameter is not specified or set to
  `false`, then the collection's default `waitForSync` behavior is
  applied. The `waitForSync` query parameter cannot be used to disable
  synchronization for collections that have a default `waitForSync` value
  of `true`.

  Unless `silent` is set to `true`, the body of the response contains a
  JSON object with the following attributes:
  - `_id`, containing the document identifier with the format `<collection-name>/<document-key>`.
  - `_key`, containing the document key that uniquely identifies a document within the collection.
  - `_rev`, containing the new document revision.

  If the query parameter `returnOld` is `true`, then
  the complete previous revision of the document
  is returned under the `old` attribute in the result.

  If the query parameter `returnNew` is `true`, then
  the complete new document is returned under
  the `new` attribute in the result.

  If the document does not exist, then a *HTTP 404* is returned and the
  body of the response contains an error document.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "_id" => string,
        "_key" => string,
        "_oldRev" => string,
        "_rev" => string
      }
  """
  @spec update(Arangox.conn(), binary, binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def update(conn, collection, key, body, opts \\ []) do
    Client.request(conn,
      method: :patch,
      segments: ["_api", "document", collection, key],
      body: body,
      query: [
        keep_null: "keepNull",
        merge_objects: "mergeObjects",
        wait_for_sync: "waitForSync",
        ignore_revs: "ignoreRevs",
        return_old: "returnOld",
        return_new: "returnNew",
        silent: "silent",
        refill_index_caches: "refillIndexCaches",
        version_attribute: "versionAttribute"
      ],
      opts: opts
    )
  end

  @doc """
  Update a document. Raises on error.

  See `update/4`.
  """
  @spec update!(Arangox.conn(), binary, binary, term, keyword) :: term
  def update!(conn, collection, key, body, opts \\ []) do
    case update(conn, collection, key, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Update multiple documents

  Partially updates documents, the documents to update are specified
  by the `_key` attributes in the body objects. The body of the
  request must contain a JSON array of document updates with the
  attributes to patch (the patch documents). All attributes from the
  patch documents are added to the existing documents if they do
  not yet exist, and overwritten in the existing documents if they do
  exist there.

  The values of the `_key`, `_id`, and `_rev` system attributes as well as
  attributes used as sharding keys cannot be changed.

  Setting an attribute value to `null` in the patch documents causes a
  value of `null` to be saved for the attribute by default.

  If `ignoreRevs` is `false` and there is a `_rev` attribute in a
  document in the body and its value does not match the revision of
  the corresponding document in the database, the precondition is
  violated.

  Cluster only: The patch document _may_ contain
  values for the collection's pre-defined shard keys. Values for the shard keys
  are treated as hints to improve performance. Should the shard keys
  values be incorrect ArangoDB may answer with a *not found* error

  Optionally, the query parameter `waitForSync` can be used to force
  synchronization of the document replacement operation to disk even in case
  that the `waitForSync` flag had been disabled for the entire collection.
  Thus, the `waitForSync` query parameter can be used to force synchronization
  of just specific operations. To use this, set the `waitForSync` parameter
  to `true`. If the `waitForSync` parameter is not specified or set to
  `false`, then the collection's default `waitForSync` behavior is
  applied. The `waitForSync` query parameter cannot be used to disable
  synchronization for collections that have a default `waitForSync` value
  of `true`.

  The body of the response contains a JSON array of the same length
  as the input array with the information about the identifier and the
  revision of the updated documents. Each element has the following
  attributes:
  - `_id`, containing the document identifier with the format `<collection-name>/<document-key>`.
  - `_key`, containing the document key that uniquely identifies a document within the collection.
  - `_rev`, containing the new document revision.

  In case of an error or violated precondition, an error
  object with the attribute `error` set to `true` and the attribute
  `errorCode` set to the error code is built.

  If the query parameter `returnOld` is `true`, then, for each
  generated document, the complete previous revision of the document
  is returned under the `old` attribute in the result.

  If the query parameter `returnNew` is `true`, then, for each
  generated document, the complete new document is returned under
  the `new` attribute in the result.

  Note that if any precondition is violated or an error occurred with
  some of the documents, the return code is still 201 or 202, but the
  `X-Arango-Error-Codes` HTTP header is set. It contains a map of the
  error codes and how often each kind of error occurred. For example,
  `1200:17,1205:10` means that in 17 cases the error 1200 ("revision conflict")
  has happened, and in 10 cases the error 1205 ("illegal document handle").
  """
  @spec update_many(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def update_many(conn, collection, body, opts \\ []) do
    Client.request(conn,
      method: :patch,
      segments: ["_api", "document", collection],
      body: body,
      query: [
        keep_null: "keepNull",
        merge_objects: "mergeObjects",
        wait_for_sync: "waitForSync",
        ignore_revs: "ignoreRevs",
        return_old: "returnOld",
        return_new: "returnNew",
        silent: "silent",
        refill_index_caches: "refillIndexCaches",
        version_attribute: "versionAttribute"
      ],
      opts: opts
    )
  end

  @doc """
  Update multiple documents. Raises on error.

  See `update_many/3`.
  """
  @spec update_many!(Arangox.conn(), binary, term, keyword) :: term
  def update_many!(conn, collection, body, opts \\ []) do
    case update_many(conn, collection, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
