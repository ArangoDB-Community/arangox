defmodule Arangox.Api.Import do
  @moduledoc """
  Provides API endpoint related to import
  """

  @default_client Arangox.Api.Client

  @type import_data_201_json_resp :: %{
          created: integer,
          details: [String.t()] | nil,
          empty: integer,
          errors: integer,
          ignored: integer,
          updated: integer
        }

  @doc """
  Import JSON data as documents

  Load JSON data and store it as documents into the specified collection.

  If you import documents into edge collections, all documents require a `_from`
  and a `_to` attribute.

  ## Options

    * `collection`: The name of the target collection. The collection needs to exist already.
      
    * `type`: Determines how the body of the request is interpreted.
      
      - `documents`: JSON Lines (JSONL) format. Each line is expected to be one
        JSON object.
      
        Example:
      
        ```json
        {"_key":"john","name":"John Smith","age":35}
        {"_key":"katie","name":"Katie Foster","age":28}
        ```
      
      - `array` (or `list`): JSON format. The request body is expected to be a
        JSON array of objects. This format requires ArangoDB to parse the complete
        array and keep it in memory for the duration of the import. This is more
        resource-intensive than the line-wise JSONL processing.
      
        Any whitespace outside of strings is ignored, which means the JSON data can be
        a single line or be formatted as multiple lines.
      
        Example:
      
        ```json
        [
          {"_key":"john","name":"John Smith","age":35},
          {"_key":"katie","name":"Katie Foster","age":28}
        ]
        ```
      
      - `auto`: automatically determines the type (either `documents` or `array`).
      
      - Omit the `type` parameter entirely (or set it to an empty string)
        to import JSON arrays of tabular data, similar to CSV.
      
        The first line is an array of strings that defines the attribute keys. The
        subsequent lines are arrays with the attribute values. The keys and values
        are matched by the order of the array elements.
      
        Example:
      
        ```json
        ["_key","name","age"]
        ["john","John Smith",35]
        ["katie","Katie Foster",28]
        ```
      
    * `ignoreMissing`: When importing JSON arrays of tabular data (`type` parameter is omitted),
      the first line of the request body defines the attribute keys and the
      subsequent lines the attribute values for each document. Subsequent lines
      with a different number of elements than the first line are not imported
      by default.
      
      ```js
      ["attr1", "attr2"]
      [1, 2]     // matching number of elements
      [1]        // misses 2nd element
      [1, 2, 3]  // excess 3rd element
      ```
      
      You can enable this option to import them anyway. For the missing elements,
      the document attributes are omitted. Excess elements are ignored.
      
    * `fromPrefix`: The collection name prefix to prepend to all values in the `_from`
      attribute that only specify a document key.
      
    * `toPrefix`: The collection name prefix to prepend to all values in the `_to`
      attribute that only specify a document key.
      
    * `overwriteCollectionPrefix`: Force the `fromPrefix` and `toPrefix`, possibly replacing existing
      collection name prefixes.
      
    * `overwrite`: If enabled, then all data in the collection is removed prior to the
      import. Any existing index definitions are preserved.
      
    * `waitForSync`: Wait until documents have been synced to disk before returning.
      
    * `onDuplicate`: Controls what action is carried out in case of a unique key constraint
      violation.
      
      - `error`: this will not import the current document because of the unique
        key constraint violation. This is the default setting.
      - `update`: this will update an existing document in the database with the
        data specified in the request. Attributes of the existing document that
        are not present in the request will be preserved.
      - `replace`: this will replace an existing document in the database with the
        data specified in the request.
      - `ignore`: this will not update an existing document and simply ignore the
        error caused by a unique key constraint violation.
      
      Note that `update`, `replace` and `ignore` will only work when the
      import document in the request contains the `_key` attribute. `update` and
      `replace` may also fail because of secondary unique key constraint violations.
      
    * `complete`: If set to `true`, the whole import fails if any error occurs. Otherwise, the
      import continues even if some documents are invalid and cannot be imported,
      skipping the problematic documents.
      
    * `details`: If set to `true`, the result includes a `details` attribute with information
      about documents that could not be imported.
      

  ## Request Body

  **Content Types**: `text/plain; charset=utf-8`
  """
  @spec import_data(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def import_data(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    query =
      Keyword.take(opts, [
        :collection,
        :complete,
        :details,
        :fromPrefix,
        :ignoreMissing,
        :onDuplicate,
        :overwrite,
        :overwriteCollectionPrefix,
        :toPrefix,
        :type,
        :waitForSync
      ])

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Import, :import_data},
      url: "/_db/#{database_name}/_api/import",
      body: body,
      method: :post,
      query: query,
      request: [{"text/plain; charset=utf-8", :map}],
      response: [
        {201, {Arangox.Api.Import, :import_data_201_json_resp}},
        {400, :null},
        {404, :null},
        {409, :null},
        {500, :null}
      ],
      opts: opts
    })
  end

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(:import_data_201_json_resp) do
    [
      created: :integer,
      details: [:string],
      empty: :integer,
      errors: :integer,
      ignored: :integer,
      updated: :integer
    ]
  end
end
