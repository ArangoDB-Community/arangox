defmodule Arangox.Api.Documents do
  @moduledoc """
  Provides API endpoints related to documents
  """

  @default_client Arangox.Api.Client

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

  ## Options

    * `waitForSync`: Wait until document has been synced to disk.
      
    * `returnNew`: Whether to additionally include the complete new document under the
      `new` attribute in the result.
      
    * `returnOld`: Whether to additionally include the complete previous document under the
      `old` attribute in the result. Only available if the `overwriteMode`
      parameter is set to `"update"` or `"replace"`, or if `overwrite` is set to `true`.
      
    * `silent`: If set to `true`, an empty object is returned as response if the document operation
      succeeds. No meta-data is returned for the created document. If the
      operation raises an error, an error object is returned.
      
      You can use this option to save network traffic.
      
    * `overwrite`: If set to `true`, the insert becomes a replace-insert. If a document with the
      same `_key` already exists, the new document is not rejected with unique
      constraint violation error but replaces the old document. Note that operations
      with `overwrite` parameter require a `_key` attribute in the request payload,
      therefore they can only be performed on collections sharded by `_key`.
      
    * `overwriteMode`: This option supersedes `overwrite` and offers the following modes:
      - `"ignore"`: if a document with the specified `_key` value exists already,
        nothing is done and no write operation is carried out. The
        insert operation returns success in this case. This mode does not
        support returning the old document version using `RETURN OLD`. When using
        `RETURN NEW`, `null` is returned in case the document already existed.
      - `"replace"`: if a document with the specified `_key` value exists already,
        it is overwritten with the specified document value. This mode is
        also used when no overwrite mode is specified but the `overwrite`
        flag is set to `true`.
      - `"update"`: if a document with the specified `_key` value exists already,
        it is patched (partially updated) with the specified document value.
        The overwrite mode can be further controlled via the `keepNull` and
        `mergeObjects` parameters.
      - `"conflict"`: if a document with the specified `_key` value exists already,
        return a unique constraint violation error so that the insert operation
        fails. This is also the default behavior in case the overwrite mode is
        not set, and the `overwrite` flag is `false` or not set either.
      
    * `keepNull`: If the intention is to delete existing attributes with the update-insert
      command, set the `keepNull` query parameter to `false`. This modifies the
      behavior of the patch command to remove top-level attributes and sub-attributes
      from the existing document that are contained in the patch document with an
      attribute value of `null` (but not attributes of objects that are nested inside
      of arrays). This option controls the update-insert behavior only.
      
    * `mergeObjects`: Controls whether objects (not arrays) are merged if present in both, the
      existing and the update-insert document. If set to `false`, the value in the
      patch document overwrites the existing document's value. If set to `true`,
      objects are merged.
      This option controls the update-insert behavior only.
      
    * `refillIndexCaches`: Whether to add new entries to in-memory index caches if document insertions
      affect the edge index or cache-enabled persistent indexes.
      
    * `versionAttribute`: Only applicable if `overwrite` is set to `true` or `overwriteMode`
      is set to `update` or `replace`.
      
      You can use the `versionAttribute` option for external versioning support.
      If set, the attribute with the name specified by the option is looked up in the
      stored document and the attribute value is compared numerically to the value of
      the versioning attribute in the supplied document that is supposed to update/replace it.
      
      If the version number in the new document is higher (rounded down to a whole number)
      than in the document that already exists in the database, then the update/replace
      operation is performed normally. This is also the case if the new versioning
      attribute has a non-numeric value, if it is a negative number, or if the
      attribute doesn't exist in the supplied or stored document.
      
      If the version number in the new document is lower or equal to what exists in
      the database, the operation is not performed and the existing document thus not
      changed. No error is returned in this case.
      
      The attribute can only be a top-level attribute.
      
      You can check if `_oldRev` (if present) and `_rev` are different to determine if the
      document has been changed.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_document(
          database_name :: String.t(),
          collection :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_document(database_name, collection, body, opts \\ []) do
    client = opts[:client] || @default_client

    query =
      Keyword.take(opts, [
        :keepNull,
        :mergeObjects,
        :overwrite,
        :overwriteMode,
        :refillIndexCaches,
        :returnNew,
        :returnOld,
        :silent,
        :versionAttribute,
        :waitForSync
      ])

    client.request(%{
      args: [database_name: database_name, collection: collection, body: body],
      call: {Arangox.Api.Documents, :create_document},
      url: "/_db/#{database_name}/_api/document/#{collection}",
      body: body,
      method: :post,
      query: query,
      request: [{"application/json", :map}],
      response: [
        {201, :null},
        {202, :null},
        {400, :null},
        {403, :null},
        {404, :null},
        {409, :null},
        {410, :null},
        {503, :null}
      ],
      opts: opts
    })
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

  ## Options

    * `waitForSync`: Wait until document has been synced to disk.
      
    * `returnNew`: Whether to additionally include the complete new document under the
      `new` attribute in the result.
      
    * `returnOld`: Whether to additionally include the complete previous document under the
      `old` attribute in the result. Only available if the `overwriteMode`
      parameter is set to `"update"` or `"replace"`, or if `overwrite` is set to `true`.
      
    * `silent`: If set to `true`, an empty object is returned as response if all document operations
      succeed. No meta-data is returned for the created documents. If any of the
      operations raises an error, an array with the error object(s) is returned.
      
      You can use this option to save network traffic but you cannot map any errors
      to the inputs of your request.
      
    * `overwrite`: If set to `true`, the insert becomes a replace-insert. If a document with the
      same `_key` already exists, the new document is not rejected with a unique
      constraint violation error but replaces the old document. Note that operations
      with `overwrite` parameter require a `_key` attribute in the request payload,
      therefore they can only be performed on collections sharded by `_key`.
      
    * `overwriteMode`: This option supersedes `overwrite` and offers the following modes:
      - `"ignore"`: if a document with the specified `_key` value exists already,
        nothing is done and no write operation is carried out. The
        insert operation returns success in this case. This mode does not
        support returning the old document version using `RETURN OLD`. When using
        `RETURN NEW`, `null` is returned in case the document already existed.
      - `"replace"`: if a document with the specified `_key` value exists already,
        it is overwritten with the specified document value. This mode is
        also used when no overwrite mode is specified but the `overwrite`
        flag is set to `true`.
      - `"update"`: if a document with the specified `_key` value exists already,
        it is patched (partially updated) with the specified document value.
        The overwrite mode can be further controlled via the `keepNull` and
        `mergeObjects` parameters.
      - `"conflict"`: if a document with the specified `_key` value exists already,
        return a unique constraint violation error so that the insert operation
        fails. This is also the default behavior in case the overwrite mode is
        not set, and the `overwrite` flag is `false` or not set either.
      
    * `keepNull`: If the intention is to delete existing attributes with the update-insert
      command, set the `keepNull` query parameter to `false`. This modifies the
      behavior of the patch command to remove top-level attributes and sub-attributes
      from the existing document that are contained in the patch document with an
      attribute value of `null` (but not attributes of objects that are nested inside
      of arrays). This option controls the update-insert behavior only.
      
    * `mergeObjects`: Controls whether objects (not arrays) are merged if present in both, the
      existing and the update-insert document. If set to `false`, the value in the
      patch document overwrites the existing document's value. If set to `true`,
      objects are merged.
      This option controls the update-insert behavior only.
      
    * `refillIndexCaches`: Whether to add new entries to in-memory index caches if document insertions
      affect the edge index or cache-enabled persistent indexes.
      
    * `versionAttribute`: Only applicable if `overwrite` is set to `true` or `overwriteMode`
      is set to `update` or `replace`.
      
      You can use the `versionAttribute` option for external versioning support.
      If set, the attribute with the name specified by the option is looked up in the
      stored document and the attribute value is compared numerically to the value of
      the versioning attribute in the supplied document that is supposed to update/replace it.
      
      If the version number in the new document is higher (rounded down to a whole number)
      than in the document that already exists in the database, then the update/replace
      operation is performed normally. This is also the case if the new versioning
      attribute has a non-numeric value, if it is a negative number, or if the
      attribute doesn't exist in the supplied or stored document.
      
      If the version number in the new document is lower or equal to what exists in
      the database, the operation is not performed and the existing document thus not
      changed. No error is returned in this case.
      
      The attribute can only be a top-level attribute.
      
      You can check if `_oldRev` (if present) and `_rev` are different to determine if the
      document has been changed.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_documents(
          database_name :: String.t(),
          collection :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_documents(database_name, collection, body, opts \\ []) do
    client = opts[:client] || @default_client

    query =
      Keyword.take(opts, [
        :keepNull,
        :mergeObjects,
        :overwrite,
        :overwriteMode,
        :refillIndexCaches,
        :returnNew,
        :returnOld,
        :silent,
        :versionAttribute,
        :waitForSync
      ])

    client.request(%{
      args: [database_name: database_name, collection: collection, body: body],
      call: {Arangox.Api.Documents, :create_documents},
      url: "/_db/#{database_name}/_api/document/#{collection}",
      body: body,
      method: :post,
      query: query,
      request: [{"application/json", [:map]}],
      response: [
        {201, :null},
        {202, :null},
        {400, :null},
        {403, :null},
        {404, :null},
        {410, :null},
        {503, :null}
      ],
      opts: opts
    })
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

  ## Options

    * `waitForSync`: Wait until deletion operation has been synced to disk.
      
    * `returnOld`: Whether to additionally include the complete previous document under the
      `old` attribute in the result.
      
    * `silent`: If set to `true`, an empty object is returned as response if the document operation
      succeeds. No meta-data is returned for the deleted document. If the
      operation raises an error, an error object is returned.
      
      You can use this option to save network traffic.
      
    * `refillIndexCaches`: Whether to delete existing entries from in-memory index caches and refill them
      if document removals affect the edge index or cache-enabled persistent indexes.
      

  """
  @spec delete_document(
          database_name :: String.t(),
          collection :: String.t(),
          key :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_document(database_name, collection, key, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:refillIndexCaches, :returnOld, :silent, :waitForSync])

    client.request(%{
      args: [database_name: database_name, collection: collection, key: key],
      call: {Arangox.Api.Documents, :delete_document},
      url: "/_db/#{database_name}/_api/document/#{collection}/#{key}",
      method: :delete,
      query: query,
      response: [
        {200, :null},
        {202, :null},
        {403, :null},
        {404, :null},
        {409, :null},
        {410, :null},
        {412, :null},
        {503, :null}
      ],
      opts: opts
    })
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

  ## Options

    * `waitForSync`: Wait until deletion operation has been synced to disk.
      
    * `returnOld`: Whether to additionally include the complete previous document under the
      `old` attribute in the result.
      
    * `silent`: If set to `true`, an empty object is returned as response if all document operations
      succeed. No meta-data is returned for the deleted documents. If at least one of
      the operations raises an error, an array with the error object(s) is returned.
      
      You can use this option to save network traffic but you cannot map any errors
      to the inputs of your request.
      
    * `ignoreRevs`: If set to `true`, ignore any `_rev` attribute included in the request. No
      revision check is performed. If set to `false`, then revisions are checked.
      
    * `refillIndexCaches`: Whether to delete existing entries from in-memory index caches and refill them
      if document removals affect the edge index or cache-enabled persistent indexes.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec delete_documents(
          database_name :: String.t(),
          collection :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_documents(database_name, collection, body, opts \\ []) do
    client = opts[:client] || @default_client

    query =
      Keyword.take(opts, [:ignoreRevs, :refillIndexCaches, :returnOld, :silent, :waitForSync])

    client.request(%{
      args: [database_name: database_name, collection: collection, body: body],
      call: {Arangox.Api.Documents, :delete_documents},
      url: "/_db/#{database_name}/_api/document/#{collection}",
      body: body,
      method: :delete,
      query: query,
      request: [{"application/json", [:unknown]}],
      response: [
        {200, :null},
        {202, :null},
        {403, :null},
        {404, :null},
        {410, :null},
        {503, :null}
      ],
      opts: opts
    })
  end

  @doc """
  Get a document

  Returns the document identified by the collection name and document key.
  The returned document contains three special attributes:
  - `_id`, containing the document identifier with the format `<collection-name>/<document-key>`.
  - `_key`, containing the document key that uniquely identifies a document within the collection.
  - `_rev`, containing the document revision.

  """
  @spec get_document(
          database_name :: String.t(),
          collection :: String.t(),
          key :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_document(database_name, collection, key, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, collection: collection, key: key],
      call: {Arangox.Api.Documents, :get_document},
      url: "/_db/#{database_name}/_api/document/#{collection}/#{key}",
      method: :get,
      response: [{200, :null}, {304, :null}, {404, :null}, {410, :null}, {412, :null}],
      opts: opts
    })
  end

  @doc """
  Get a document header

  Like `GET`, but only returns the header fields and not the body. You
  can use this call to get the current revision of a document or check if
  the document was deleted.

  """
  @spec get_document_header(
          database_name :: String.t(),
          collection :: String.t(),
          key :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_document_header(database_name, collection, key, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, collection: collection, key: key],
      call: {Arangox.Api.Documents, :get_document_header},
      url: "/_db/#{database_name}/_api/document/#{collection}/#{key}",
      method: :head,
      response: [{200, :null}, {304, :null}, {404, :null}, {410, :null}, {412, :null}],
      opts: opts
    })
  end

  @doc """
  Get multiple documents

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

  > **WARNING:**
  The server distinguishes this operation from `replace_documents/4` by
  nothing but the `onlyget=true` query parameter — same path, same method —
  and without that flag it *replaces* the documents named in the body.
  This function always sends `onlyget=true`; an `onlyget` value in `opts`
  is ignored rather than forwarded.

  ## Options

    * `ignoreRevs`: If set to `false` and a `_rev` attribute is included in the request,
      then the document is only returned if it has the same revision.
      Otherwise, a precondition failed error is returned for the document.


  ## Request Body

  **Content Types**: `application/json`
  """
  @spec get_documents(
          database_name :: String.t(),
          collection :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_documents(database_name, collection, body, opts \\ []) do
    client = opts[:client] || @default_client

    # `onlyget` is put after the take, so no caller-supplied value can
    # reach the wire — without `onlyget=true` this address replaces documents.
    query =
      opts
      |> Keyword.take([:ignoreRevs])
      |> Keyword.put(:onlyget, true)

    client.request(%{
      args: [database_name: database_name, collection: collection, body: body],
      call: {Arangox.Api.Documents, :get_documents},
      url: "/_db/#{database_name}/_api/document/#{collection}",
      body: body,
      method: :put,
      query: query,
      request: [{"application/json", [:unknown]}],
      response: [{200, :null}, {400, :null}, {404, :null}, {410, :null}],
      opts: opts
    })
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

  ## Options

    * `waitForSync`: Wait until document has been synced to disk.
      
    * `ignoreRevs`: If set to `true`, the `_rev` attributes in
      the given document is ignored. If this is set to `false`, then
      the `_rev` attribute given in the body document is taken as a
      precondition. The document is only replaced if the current revision
      is the one specified.
      
    * `returnOld`: Whether to additionally include the complete previous document under the
      `old` attribute in the result.
      
    * `returnNew`: Whether to additionally include the complete new document under the
      `new` attribute in the result.
      
    * `silent`: If set to `true`, an empty object is returned as response if the document operation
      succeeds. No meta-data is returned for the replaced document. If the
      operation raises an error, an error object is returned.
      
      You can use this option to save network traffic.
      
    * `refillIndexCaches`: Whether to update existing entries in in-memory index caches if documents
      replacements affect the edge index or cache-enabled persistent indexes.
      
    * `versionAttribute`: You can use the `versionAttribute` option for external versioning support.
      If set, the attribute with the name specified by the option is looked up in the
      stored document and the attribute value is compared numerically to the value of
      the versioning attribute in the supplied document that is supposed to replace it.
      
      If the version number in the new document is higher (rounded down to a whole number)
      than in the document that already exists in the database, then the replace
      operation is performed normally. This is also the case if the new versioning
      attribute has a non-numeric value, if it is a negative number, or if the
      attribute doesn't exist in the supplied or stored document.
      
      If the version number in the new document is lower or equal to what exists in
      the database, the operation is not performed and the existing document thus not
      changed. No error is returned in this case.
      
      The attribute can only be a top-level attribute.
      
      You can check if `_oldRev` and `_rev` are different to determine if the
      document has been changed.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec replace_document(
          database_name :: String.t(),
          collection :: String.t(),
          key :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def replace_document(database_name, collection, key, body, opts \\ []) do
    client = opts[:client] || @default_client

    query =
      Keyword.take(opts, [
        :ignoreRevs,
        :refillIndexCaches,
        :returnNew,
        :returnOld,
        :silent,
        :versionAttribute,
        :waitForSync
      ])

    client.request(%{
      args: [database_name: database_name, collection: collection, key: key, body: body],
      call: {Arangox.Api.Documents, :replace_document},
      url: "/_db/#{database_name}/_api/document/#{collection}/#{key}",
      body: body,
      method: :put,
      query: query,
      request: [{"application/json", :map}],
      response: [
        {201, :null},
        {202, :null},
        {400, :null},
        {403, :null},
        {404, :null},
        {409, :null},
        {410, :null},
        {412, :null},
        {503, :null}
      ],
      opts: opts
    })
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

  ## Options

    * `waitForSync`: Wait until the new documents have been synced to disk.
      
    * `ignoreRevs`: If set to `true`, the `_rev` attributes in
      the given documents are ignored. If this is set to `false`, then
      any `_rev` attribute given in a body document is taken as a
      precondition. The document is only replaced if the current revision
      is the one specified.
      
    * `returnOld`: Whether to additionally include the complete previous document under the
      `old` attribute in the result.
      
    * `returnNew`: Whether to additionally include the complete new document under the
      `new` attribute in the result.
      
    * `silent`: If set to `true`, an empty object is returned as response if all document operations
      succeed. No meta-data is returned for the replaced documents. If at least one
      operation raises an error, an array with the error object(s) is returned.
      
      You can use this option to save network traffic but you cannot map any errors
      to the inputs of your request.
      
    * `refillIndexCaches`: Whether to update existing entries in in-memory index caches if documents
      replacements affect the edge index or cache-enabled persistent indexes.
      
    * `versionAttribute`: You can use the `versionAttribute` option for external versioning support.
      If set, the attribute with the name specified by the option is looked up in the
      stored document and the attribute value is compared numerically to the value of
      the versioning attribute in the supplied document that is supposed to replace it.
      
      If the version number in the new document is higher (rounded down to a whole number)
      than in the document that already exists in the database, then the replace
      operation is performed normally. This is also the case if the new versioning
      attribute has a non-numeric value, if it is a negative number, or if the
      attribute doesn't exist in the supplied or stored document.
      
      If the version number in the new document is lower or equal to what exists in
      the database, the operation is not performed and the existing document thus not
      changed. No error is returned in this case.
      
      The attribute can only be a top-level attribute.
      
      You can check if `_oldRev` and `_rev` are different to determine if the
      document has been changed.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec replace_documents(
          database_name :: String.t(),
          collection :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def replace_documents(database_name, collection, body, opts \\ []) do
    client = opts[:client] || @default_client

    query =
      Keyword.take(opts, [
        :ignoreRevs,
        :refillIndexCaches,
        :returnNew,
        :returnOld,
        :silent,
        :versionAttribute,
        :waitForSync
      ])

    client.request(%{
      args: [database_name: database_name, collection: collection, body: body],
      call: {Arangox.Api.Documents, :replace_documents},
      url: "/_db/#{database_name}/_api/document/#{collection}",
      body: body,
      method: :put,
      query: query,
      request: [{"application/json", [:map]}],
      response: [
        {201, :null},
        {202, :null},
        {400, :null},
        {403, :null},
        {404, :null},
        {410, :null},
        {503, :null}
      ],
      opts: opts
    })
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

  ## Options

    * `keepNull`: If the intention is to delete existing attributes with the patch
      command, set the `keepNull` query parameter to `false`. This modifies the
      behavior of the patch command to remove top-level attributes and sub-attributes
      from the existing document that are contained in the patch document with an
      attribute value of `null` (but not attributes of objects that are nested inside
      of arrays).
      
    * `mergeObjects`: Controls whether objects (not arrays) are merged if present in
      both the existing and the patch document. If set to `false`, the
      value in the patch document overwrites the existing document's
      value. If set to `true`, objects are merged.
      
    * `waitForSync`: Wait until document has been synced to disk.
      
    * `ignoreRevs`: If set to `true`, the `_rev` attributes in
      the given document is ignored. If this is set to `false`, then
      the `_rev` attribute given in the body document is taken as a
      precondition. The document is only updated if the current revision
      is the one specified.
      
    * `returnOld`: Whether to additionally include the complete previous document under the
      `old` attribute in the result.
      
    * `returnNew`: Whether to additionally include the complete new document under the
      `new` attribute in the result.
      
    * `silent`: If set to `true`, an empty object is returned as response if the document operation
      succeeds. No meta-data is returned for the updated document. If the
      operation raises an error, an error object is returned.
      
      You can use this option to save network traffic.
      
    * `refillIndexCaches`: Whether to update existing entries in in-memory index caches if document updates
      affect the edge index or cache-enabled persistent indexes.
      
    * `versionAttribute`: You can use the `versionAttribute` option for external versioning support.
      If set, the attribute with the name specified by the option is looked up in the
      stored document and the attribute value is compared numerically to the value of
      the versioning attribute in the supplied document that is supposed to update it.
      
      If the version number in the new document is higher (rounded down to a whole number)
      than in the document that already exists in the database, then the update
      operation is performed normally. This is also the case if the new versioning
      attribute has a non-numeric value, if it is a negative number, or if the
      attribute doesn't exist in the supplied or stored document.
      
      If the version number in the new document is lower or equal to what exists in
      the database, the operation is not performed and the existing document thus not
      changed. No error is returned in this case.
      
      The attribute can only be a top-level attribute.
      
      You can check if `_oldRev` and `_rev` are different to determine if the
      document has been changed.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec update_document(
          database_name :: String.t(),
          collection :: String.t(),
          key :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def update_document(database_name, collection, key, body, opts \\ []) do
    client = opts[:client] || @default_client

    query =
      Keyword.take(opts, [
        :ignoreRevs,
        :keepNull,
        :mergeObjects,
        :refillIndexCaches,
        :returnNew,
        :returnOld,
        :silent,
        :versionAttribute,
        :waitForSync
      ])

    client.request(%{
      args: [database_name: database_name, collection: collection, key: key, body: body],
      call: {Arangox.Api.Documents, :update_document},
      url: "/_db/#{database_name}/_api/document/#{collection}/#{key}",
      body: body,
      method: :patch,
      query: query,
      request: [{"application/json", :map}],
      response: [
        {201, :null},
        {202, :null},
        {400, :null},
        {403, :null},
        {404, :null},
        {409, :null},
        {410, :null},
        {412, :null},
        {503, :null}
      ],
      opts: opts
    })
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

  ## Options

    * `keepNull`: If the intention is to delete existing attributes with the patch
      command, set the `keepNull` query parameter to `false`. This modifies the
      behavior of the patch command to remove top-level attributes and sub-attributes
      from the existing document that are contained in the patch document with an
      attribute value of `null` (but not attributes of objects that are nested inside
      of arrays).
      
    * `mergeObjects`: Controls whether objects (not arrays) are merged if present in
      both the existing and the patch document. If set to `false`, the
      value in the patch document overwrites the existing document's
      value. If set to `true`, objects are merged.
      
    * `waitForSync`: Wait until the new documents have been synced to disk.
      
    * `ignoreRevs`: If set to `true`, the `_rev` attributes in
      the given documents are ignored. If this is set to `false`, then
      any `_rev` attribute given in a body document is taken as a
      precondition. The document is only updated if the current revision
      is the one specified.
      
    * `returnOld`: Whether to additionally include the complete previous document under the
      `old` attribute in the result.
      
    * `returnNew`: Whether to additionally include the complete new document under the
      `new` attribute in the result.
      
    * `silent`: If set to `true`, an empty object is returned as response if all document operations
      succeed. No meta-data is returned for the updated documents. If at least one
      operation raises an error, an array with the error object(s) is returned.
      
      You can use this option to save network traffic but you cannot map any errors
      to the inputs of your request.
      
    * `refillIndexCaches`: Whether to update existing entries in in-memory index caches if document updates
      affect the edge index or cache-enabled persistent indexes.
      
    * `versionAttribute`: You can use the `versionAttribute` option for external versioning support.
      If set, the attribute with the name specified by the option is looked up in the
      stored document and the attribute value is compared numerically to the value of
      the versioning attribute in the supplied document that is supposed to update it.
      
      If the version number in the new document is higher (rounded down to a whole number)
      than in the document that already exists in the database, then the update
      operation is performed normally. This is also the case if the new versioning
      attribute has a non-numeric value, if it is a negative number, or if the
      attribute doesn't exist in the supplied or stored document.
      
      If the version number in the new document is lower or equal to what exists in
      the database, the operation is not performed and the existing document thus not
      changed. No error is returned in this case.
      
      The attribute can only be a top-level attribute.
      
      You can check if `_oldRev` and `_rev` are different to determine if the
      document has been changed.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec update_documents(
          database_name :: String.t(),
          collection :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def update_documents(database_name, collection, body, opts \\ []) do
    client = opts[:client] || @default_client

    query =
      Keyword.take(opts, [
        :ignoreRevs,
        :keepNull,
        :mergeObjects,
        :refillIndexCaches,
        :returnNew,
        :returnOld,
        :silent,
        :versionAttribute,
        :waitForSync
      ])

    client.request(%{
      args: [database_name: database_name, collection: collection, body: body],
      call: {Arangox.Api.Documents, :update_documents},
      url: "/_db/#{database_name}/_api/document/#{collection}",
      body: body,
      method: :patch,
      query: query,
      request: [{"application/json", [:map]}],
      response: [
        {201, :null},
        {202, :null},
        {400, :null},
        {403, :null},
        {404, :null},
        {410, :null},
        {503, :null}
      ],
      opts: opts
    })
  end
end
