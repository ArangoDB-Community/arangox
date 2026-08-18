defmodule Arangox.Api.ConformanceTest do
  @moduledoc """
  The conformance gate over the owned `Arangox.Api.*` surface.

  The oracle is the OpenAPI document the tested server itself serves —
  `GET /_db/_system/_admin/aardvark/api/swagger.json` — fetched through the
  driver from the compose 3.12 tier. Per operation, the gate proves:
  the method/path multiset is a bijection between document and surface, with
  no waiver list; the query-parameter names a call site can send equal
  the document's declared query parameters; and the declared request
  media equal the document's request content types. Response schemas
  are deliberately out of scope.

  Both sides must speak the same address before anything can be compared.
  Two conventions separate the published document from the source:

    * **Fragments.** The document distinguishes two operations sharing a
      path and method by appending a URL fragment to the path key
      (`/_api/document/{collection}#multiple`). The fragment is
      documentation, not an address — the server ignores it — so the gate
      strips it. After stripping, nine addresses carry more than one
      operation (24 operations in all; POST on the index path alone carries
      eight variants), so per-operation pairing is by group: both sides
      group by `{method, template}` and the gate compares the multiset of
      `{query key set, request media}` within each group, naming the
      address on failure.

    * **Path-parameter names.** The document writes path parameters in the
      published spelling — `{database-name}`, `{DB-Server-ID}` — while the
      source speaks valid Elixir identifiers. The rename rule: a name that
      is already a valid lowercase-leading identifier (camelCase such as
      `{shardId}` included) passes through untouched; any other name has
      its non-alphanumeric runs collapsed to `_`, is `Macro.underscore`d,
      has repeated `_` collapsed and edge `_` trimmed, and gains a `p_`
      prefix if it still does not start with a letter or underscore. Query
      parameter names are never renamed — the wire speaks them as
      published (`waitForSync`), and so does the source.

  The version pin comes first: `Errno.tag/0` must equal the live
  server's `/_api/version` answer before any comparison, so a mis-pinned
  compose stack fails on the actual problem instead of drowning it in
  operation noise.
  """

  use ExUnit.Case

  alias Arangox.{Errno, Response}
  alias Arangox.TestSupport.ApiSurface

  @moduletag :integration

  @document_path "/_db/_system/_admin/aardvark/api/swagger.json"

  @http_methods ~w(get put post delete options head patch trace)

  # R8a: the document's cardinality at the 3.12.10 pin. Pinning both sides'
  # counts before any comparison means an extraction or parse regression
  # cannot shrink a side to the empty set and pass vacuously.
  @expected_path_count 164
  @expected_operation_count 243

  # The three pins below mirror the "Known fidelity gaps" disclosures in
  # AGENTS.md ("The API surface") and README.md. The fidelity-gaps test
  # re-derives them from the live document so a new server pin cannot stale
  # the prose silently: a failure there means the document moved, and the
  # disclosures must be refreshed together with these pins — never the pins
  # alone.

  # Gap 1: array schemas the document leaves without `items`, as
  # {operationId, section} — :request for a requestBody schema, :response
  # for a response schema (all three response hits are the `result`
  # property of the operation's success answer).
  @itemless_array_schemas [
    {"createAqlQueryCursor", :response},
    {"deleteDocuments", :request},
    {"getDocuments", :request},
    {"getNextAqlQueryCursorBatch", :response},
    {"getPreviousAqlQueryCursorBatch", :response}
  ]

  # Gap 2: header parameter objects per name, summed across all operations.
  # None of these appears in an operation signature — headers are the
  # adapter's concern.
  @header_parameter_counts %{
    "If-Match" => 13,
    "If-None-Match" => 4,
    "x-arango-allow-dirty-read" => 6,
    "x-arango-trx-id" => 24
  }

  # Gap 3: the document's path keys by /_db prefix. The buckets must sum to
  # @expected_path_count; :unexpected_db_prefix never appears here, so a
  # path under /_db/ that is neither spelling fails the map equality.
  @path_prefix_counts %{
    database_argument: 129,
    hardcoded_system: 6,
    no_db_prefix: 29
  }

  # R7a: every {operationId, name} pair in the document whose parameter is
  # declared `"in": "query", "required": true`. This watches the *document*
  # side only — the surface does not enforce required-ness — so a parameter
  # changing required-ness at a future pin forces a human decision here
  # instead of sliding through. Regenerate by fetching `@document_path` from
  # the compose 3.12 server and enumerating those pairs, sorted.
  @required_query_parameters [
    {"createFoxxService", "mount"},
    {"createIndex", "collection"},
    {"createIndexFulltext", "collection"},
    {"createIndexGeo", "collection"},
    {"createIndexInverted", "collection"},
    {"createIndexMdi", "collection"},
    {"createIndexPersistent", "collection"},
    {"createIndexTtl", "collection"},
    {"createIndexVector", "collection"},
    {"deleteFoxxService", "mount"},
    {"disableFoxxDevelopmentMode", "mount"},
    {"downloadFoxxService", "mount"},
    {"enableFoxxDevelopmentMode", "mount"},
    {"getClusterStatistics", "DBserver"},
    {"getDocuments", "onlyget"},
    {"getFoxxConfiguration", "mount"},
    {"getFoxxDependencies", "mount"},
    {"getFoxxReadme", "mount"},
    {"getFoxxServiceDescription", "mount"},
    {"getFoxxSwaggerDescription", "mount"},
    {"getReplicationDump", "batchId"},
    {"getReplicationDump", "collection"},
    {"getReplicationInventory", "batchId"},
    {"getReplicationRevisionTree", "batchId"},
    {"getReplicationRevisionTree", "collection"},
    {"getVertexEdges", "vertex"},
    {"importData", "collection"},
    {"listFoxxScripts", "mount"},
    {"listIndexes", "collection"},
    {"listReplicationRevisionDocuments", "batchId"},
    {"listReplicationRevisionDocuments", "collection"},
    {"listReplicationRevisionRanges", "batchId"},
    {"listReplicationRevisionRanges", "collection"},
    {"rebuildReplicationRevisionTree", "collection"},
    {"replaceFoxxConfiguration", "mount"},
    {"replaceFoxxDependencies", "mount"},
    {"replaceFoxxService", "mount"},
    {"runFoxxScript", "mount"},
    {"runFoxxTests", "mount"},
    {"updateFoxxConfiguration", "mount"},
    {"updateFoxxDependencies", "mount"},
    {"upgradeFoxxService", "mount"}
  ]

  # Operation identity at the 3.12.10 pin: every {operationId, module, function}
  # triple, sorted by operationId. The gate keys on addresses and profiles, which
  # sibling operations at one address can share (the POST index variants do),
  # so a renamed function -- or one deleted and its sibling duplicated --
  # passes them while callers lose a function. At this pin every function name
  # is exactly `Macro.underscore(operationId)`; regenerate by fetching
  # `@document_path` from the compose 3.12 server and pairing each operation
  # to its call site by `{method, template}` and that rule, sorted by
  # operationId.
  @operation_functions [
    {"abortStreamTransaction", Arangox.Api.Transactions, :abort_stream_transaction},
    {"addVertexCollection", Arangox.Api.Graphs, :add_vertex_collection},
    {"beginStreamTransaction", Arangox.Api.Transactions, :begin_stream_transaction},
    {"cancelJob", Arangox.Api.Jobs, :cancel_job},
    {"clearSlowAqlQueryList", Arangox.Api.Queries, :clear_slow_aql_query_list},
    {"commitFoxxServiceState", Arangox.Api.Foxx, :commit_foxx_service_state},
    {"commitStreamTransaction", Arangox.Api.Transactions, :commit_stream_transaction},
    {"compactAllDatabases", Arangox.Api.Administration, :compact_all_databases},
    {"compactCollection", Arangox.Api.Collections, :compact_collection},
    {"computeClusterRebalancePlan", Arangox.Api.Cluster, :compute_cluster_rebalance_plan},
    {"createAccessToken", Arangox.Api.Authentication, :create_access_token},
    {"createAnalyzer", Arangox.Api.Analyzers, :create_analyzer},
    {"createAqlQueryCursor", Arangox.Api.Queries, :create_aql_query_cursor},
    {"createAqlUserFunction", Arangox.Api.Queries, :create_aql_user_function},
    {"createBackup", Arangox.Api.HotBackups, :create_backup},
    {"createCollection", Arangox.Api.Collections, :create_collection},
    {"createDatabase", Arangox.Api.Databases, :create_database},
    {"createDocument", Arangox.Api.Documents, :create_document},
    {"createDocuments", Arangox.Api.Documents, :create_documents},
    {"createEdge", Arangox.Api.Graphs, :create_edge},
    {"createEdgeDefinition", Arangox.Api.Graphs, :create_edge_definition},
    {"createFoxxService", Arangox.Api.Foxx, :create_foxx_service},
    {"createGraph", Arangox.Api.Graphs, :create_graph},
    {"createIndex", Arangox.Api.Indexes, :create_index},
    {"createIndexFulltext", Arangox.Api.Indexes, :create_index_fulltext},
    {"createIndexGeo", Arangox.Api.Indexes, :create_index_geo},
    {"createIndexInverted", Arangox.Api.Indexes, :create_index_inverted},
    {"createIndexMdi", Arangox.Api.Indexes, :create_index_mdi},
    {"createIndexPersistent", Arangox.Api.Indexes, :create_index_persistent},
    {"createIndexTtl", Arangox.Api.Indexes, :create_index_ttl},
    {"createIndexVector", Arangox.Api.Indexes, :create_index_vector},
    {"createReplicationBatch", Arangox.Api.Replication, :create_replication_batch},
    {"createSessionToken", Arangox.Api.Authentication, :create_session_token},
    {"createTask", Arangox.Api.Tasks, :create_task},
    {"createTaskWithId", Arangox.Api.Tasks, :create_task_with_id},
    {"createUser", Arangox.Api.Users, :create_user},
    {"createVertex", Arangox.Api.Graphs, :create_vertex},
    {"createView", Arangox.Api.Views, :create_view},
    {"createViewSearchAlias", Arangox.Api.Views, :create_view_search_alias},
    {"deleteAccessToken", Arangox.Api.Authentication, :delete_access_token},
    {"deleteAnalyzer", Arangox.Api.Analyzers, :delete_analyzer},
    {"deleteAqlQuery", Arangox.Api.Queries, :delete_aql_query},
    {"deleteAqlQueryCache", Arangox.Api.Queries, :delete_aql_query_cache},
    {"deleteAqlQueryCursor", Arangox.Api.Queries, :delete_aql_query_cursor},
    {"deleteAqlQueryPlanCache", Arangox.Api.Queries, :delete_aql_query_plan_cache},
    {"deleteAqlUserFunction", Arangox.Api.Queries, :delete_aql_user_function},
    {"deleteBackup", Arangox.Api.HotBackups, :delete_backup},
    {"deleteCollection", Arangox.Api.Collections, :delete_collection},
    {"deleteCrashDump", Arangox.Api.Administration, :delete_crash_dump},
    {"deleteDatabase", Arangox.Api.Databases, :delete_database},
    {"deleteDocument", Arangox.Api.Documents, :delete_document},
    {"deleteDocuments", Arangox.Api.Documents, :delete_documents},
    {"deleteEdge", Arangox.Api.Graphs, :delete_edge},
    {"deleteEdgeDefinition", Arangox.Api.Graphs, :delete_edge_definition},
    {"deleteFoxxService", Arangox.Api.Foxx, :delete_foxx_service},
    {"deleteGraph", Arangox.Api.Graphs, :delete_graph},
    {"deleteIndex", Arangox.Api.Indexes, :delete_index},
    {"deleteJob", Arangox.Api.Jobs, :delete_job},
    {"deleteReplicationBatch", Arangox.Api.Replication, :delete_replication_batch},
    {"deleteTask", Arangox.Api.Tasks, :delete_task},
    {"deleteUser", Arangox.Api.Users, :delete_user},
    {"deleteUserCollectionPermissions", Arangox.Api.Users, :delete_user_collection_permissions},
    {"deleteUserDatabasePermissions", Arangox.Api.Users, :delete_user_database_permissions},
    {"deleteVertex", Arangox.Api.Graphs, :delete_vertex},
    {"deleteVertexCollection", Arangox.Api.Graphs, :delete_vertex_collection},
    {"deleteView", Arangox.Api.Views, :delete_view},
    {"disableFoxxDevelopmentMode", Arangox.Api.Foxx, :disable_foxx_development_mode},
    {"downloadBackup", Arangox.Api.HotBackups, :download_backup},
    {"downloadFoxxService", Arangox.Api.Foxx, :download_foxx_service},
    {"echoRequest", Arangox.Api.Administration, :echo_request},
    {"enableFoxxDevelopmentMode", Arangox.Api.Foxx, :enable_foxx_development_mode},
    {"executeBatchRequest", Arangox.Api.BatchRequests, :execute_batch_request},
    {"executeClusterRebalancePlan", Arangox.Api.Cluster, :execute_cluster_rebalance_plan},
    {"executeCode", Arangox.Api.Administration, :execute_code},
    {"executeJavaScriptTransaction", Arangox.Api.Transactions, :execute_java_script_transaction},
    {"explainAqlQuery", Arangox.Api.Queries, :explain_aql_query},
    {"extendReplicationBatch", Arangox.Api.Replication, :extend_replication_batch},
    {"getAnalyzer", Arangox.Api.Analyzers, :get_analyzer},
    {"getAqlQueryOptimizerRules", Arangox.Api.Queries, :get_aql_query_optimizer_rules},
    {"getAqlQueryTrackingProperties", Arangox.Api.Queries, :get_aql_query_tracking_properties},
    {"getAvailableStartupOptions", Arangox.Api.Administration, :get_available_startup_options},
    {"getClusterHealth", Arangox.Api.Cluster, :get_cluster_health},
    {"getClusterImbalance", Arangox.Api.Cluster, :get_cluster_imbalance},
    {"getClusterStatistics", Arangox.Api.Cluster, :get_cluster_statistics},
    {"getCollection", Arangox.Api.Collections, :get_collection},
    {"getCollectionChecksum", Arangox.Api.Collections, :get_collection_checksum},
    {"getCollectionCount", Arangox.Api.Collections, :get_collection_count},
    {"getCollectionFigures", Arangox.Api.Collections, :get_collection_figures},
    {"getCollectionProperties", Arangox.Api.Collections, :get_collection_properties},
    {"getCollectionRevision", Arangox.Api.Collections, :get_collection_revision},
    {"getCollectionShards", Arangox.Api.Collections, :get_collection_shards},
    {"getCrashDump", Arangox.Api.Administration, :get_crash_dump},
    {"getCurrentDatabase", Arangox.Api.Databases, :get_current_database},
    {"getDatabaseVersion", Arangox.Api.Administration, :get_database_version},
    {"getDbserverMaintenance", Arangox.Api.Cluster, :get_dbserver_maintenance},
    {"getDeploymentId", Arangox.Api.Administration, :get_deployment_id},
    {"getDocument", Arangox.Api.Documents, :get_document},
    {"getDocumentHeader", Arangox.Api.Documents, :get_document_header},
    {"getDocuments", Arangox.Api.Documents, :get_documents},
    {"getEdge", Arangox.Api.Graphs, :get_edge},
    {"getEffectiveStartupOptions", Arangox.Api.Administration, :get_effective_startup_options},
    {"getEngine", Arangox.Api.Administration, :get_engine},
    {"getEngineStats", Arangox.Api.Administration, :get_engine_stats},
    {"getFoxxConfiguration", Arangox.Api.Foxx, :get_foxx_configuration},
    {"getFoxxDependencies", Arangox.Api.Foxx, :get_foxx_dependencies},
    {"getFoxxReadme", Arangox.Api.Foxx, :get_foxx_readme},
    {"getFoxxServiceDescription", Arangox.Api.Foxx, :get_foxx_service_description},
    {"getFoxxSwaggerDescription", Arangox.Api.Foxx, :get_foxx_swagger_description},
    {"getGraph", Arangox.Api.Graphs, :get_graph},
    {"getIndex", Arangox.Api.Indexes, :get_index},
    {"getJob", Arangox.Api.Jobs, :get_job},
    {"getJobResult", Arangox.Api.Jobs, :get_job_result},
    {"getKeyGenerators", Arangox.Api.Collections, :get_key_generators},
    {"getLicense", Arangox.Api.Administration, :get_license},
    {"getLog", Arangox.Api.Monitoring, :get_log},
    {"getLogEntries", Arangox.Api.Monitoring, :get_log_entries},
    {"getLogLevel", Arangox.Api.Monitoring, :get_log_level},
    {"getMetrics", Arangox.Api.Monitoring, :get_metrics},
    {"getMetricsV2", Arangox.Api.Monitoring, :get_metrics_v2},
    {"getNextAqlQueryCursorBatch", Arangox.Api.Queries, :get_next_aql_query_cursor_batch},
    {"getNextAqlQueryCursorBatchPut", Arangox.Api.Queries, :get_next_aql_query_cursor_batch_put},
    {"getPreviousAqlQueryCursorBatch", Arangox.Api.Queries, :get_previous_aql_query_cursor_batch},
    {"getPublicStartupOptions", Arangox.Api.Administration, :get_public_startup_options},
    {"getQueryCacheProperties", Arangox.Api.Queries, :get_query_cache_properties},
    {"getRecentApiCalls", Arangox.Api.Monitoring, :get_recent_api_calls},
    {"getRecentAqlQueries", Arangox.Api.Monitoring, :get_recent_aql_queries},
    {"getReplicationClusterInventory", Arangox.Api.Replication,
     :get_replication_cluster_inventory},
    {"getReplicationDump", Arangox.Api.Replication, :get_replication_dump},
    {"getReplicationInventory", Arangox.Api.Replication, :get_replication_inventory},
    {"getReplicationLoggerState", Arangox.Api.Replication, :get_replication_logger_state},
    {"getReplicationRevisionTree", Arangox.Api.Replication, :get_replication_revision_tree},
    {"getResponsibleShard", Arangox.Api.Collections, :get_responsible_shard},
    {"getServerAvailability", Arangox.Api.Administration, :get_server_availability},
    {"getServerId", Arangox.Api.Cluster, :get_server_id},
    {"getServerJwtSecrets", Arangox.Api.Authentication, :get_server_jwt_secrets},
    {"getServerMode", Arangox.Api.Administration, :get_server_mode},
    {"getServerRole", Arangox.Api.Cluster, :get_server_role},
    {"getServerTls", Arangox.Api.Security, :get_server_tls},
    {"getShutdownProgress", Arangox.Api.Administration, :get_shutdown_progress},
    {"getStatistics", Arangox.Api.Monitoring, :get_statistics},
    {"getStatisticsDescription", Arangox.Api.Monitoring, :get_statistics_description},
    {"getStatus", Arangox.Api.Administration, :get_status},
    {"getStreamTransaction", Arangox.Api.Transactions, :get_stream_transaction},
    {"getStructuredLog", Arangox.Api.Monitoring, :get_structured_log},
    {"getSupportInfo", Arangox.Api.Administration, :get_support_info},
    {"getTask", Arangox.Api.Tasks, :get_task},
    {"getTime", Arangox.Api.Administration, :get_time},
    {"getUsageMetrics", Arangox.Api.Monitoring, :get_usage_metrics},
    {"getUser", Arangox.Api.Users, :get_user},
    {"getUserCollectionPermissions", Arangox.Api.Users, :get_user_collection_permissions},
    {"getUserDatabasePermissions", Arangox.Api.Users, :get_user_database_permissions},
    {"getVersion", Arangox.Api.Administration, :get_version},
    {"getVertex", Arangox.Api.Graphs, :get_vertex},
    {"getVertexEdges", Arangox.Api.Graphs, :get_vertex_edges},
    {"getView", Arangox.Api.Views, :get_view},
    {"getViewProperties", Arangox.Api.Views, :get_view_properties},
    {"getViewPropertiesSearchAlias", Arangox.Api.Views, :get_view_properties_search_alias},
    {"getViewSearchAlias", Arangox.Api.Views, :get_view_search_alias},
    {"getWalLastTick", Arangox.Api.Replication, :get_wal_last_tick},
    {"getWalRange", Arangox.Api.Replication, :get_wal_range},
    {"getWalTail", Arangox.Api.Replication, :get_wal_tail},
    {"importData", Arangox.Api.Import, :import_data},
    {"listAccessTokens", Arangox.Api.Authentication, :list_access_tokens},
    {"listAnalyzers", Arangox.Api.Analyzers, :list_analyzers},
    {"listAqlQueries", Arangox.Api.Queries, :list_aql_queries},
    {"listAqlUserFunctions", Arangox.Api.Queries, :list_aql_user_functions},
    {"listBackups", Arangox.Api.HotBackups, :list_backups},
    {"listClusterEndpoints", Arangox.Api.Cluster, :list_cluster_endpoints},
    {"listCollections", Arangox.Api.Collections, :list_collections},
    {"listCrashDumps", Arangox.Api.Administration, :list_crash_dumps},
    {"listDatabases", Arangox.Api.Databases, :list_databases},
    {"listEdgeCollections", Arangox.Api.Graphs, :list_edge_collections},
    {"listEndpoints", Arangox.Api.Administration, :list_endpoints},
    {"listFoxxScripts", Arangox.Api.Foxx, :list_foxx_scripts},
    {"listFoxxServices", Arangox.Api.Foxx, :list_foxx_services},
    {"listGraphs", Arangox.Api.Graphs, :list_graphs},
    {"listIndexes", Arangox.Api.Indexes, :list_indexes},
    {"listQueryCachePlans", Arangox.Api.Queries, :list_query_cache_plans},
    {"listQueryCacheResults", Arangox.Api.Queries, :list_query_cache_results},
    {"listReplicationRevisionDocuments", Arangox.Api.Replication,
     :list_replication_revision_documents},
    {"listReplicationRevisionRanges", Arangox.Api.Replication, :list_replication_revision_ranges},
    {"listSlowAqlQueries", Arangox.Api.Queries, :list_slow_aql_queries},
    {"listStreamTransactions", Arangox.Api.Transactions, :list_stream_transactions},
    {"listTasks", Arangox.Api.Tasks, :list_tasks},
    {"listUserAccessibleDatabases", Arangox.Api.Databases, :list_user_accessible_databases},
    {"listUserDatabases", Arangox.Api.Users, :list_user_databases},
    {"listUsers", Arangox.Api.Users, :list_users},
    {"listVertexCollections", Arangox.Api.Graphs, :list_vertex_collections},
    {"listViews", Arangox.Api.Views, :list_views},
    {"loadCollection", Arangox.Api.Collections, :load_collection},
    {"loadCollectionIndexes", Arangox.Api.Collections, :load_collection_indexes},
    {"parseAqlQuery", Arangox.Api.Queries, :parse_aql_query},
    {"rebuildReplicationRevisionTree", Arangox.Api.Replication,
     :rebuild_replication_revision_tree},
    {"recalculateCollectionCount", Arangox.Api.Collections, :recalculate_collection_count},
    {"reloadRouting", Arangox.Api.Administration, :reload_routing},
    {"reloadServerJwtSecrets", Arangox.Api.Authentication, :reload_server_jwt_secrets},
    {"reloadServerTls", Arangox.Api.Security, :reload_server_tls},
    {"renameCollection", Arangox.Api.Collections, :rename_collection},
    {"renameView", Arangox.Api.Views, :rename_view},
    {"renameViewSearchAlias", Arangox.Api.Views, :rename_view_search_alias},
    {"replaceDocument", Arangox.Api.Documents, :replace_document},
    {"replaceDocuments", Arangox.Api.Documents, :replace_documents},
    {"replaceEdge", Arangox.Api.Graphs, :replace_edge},
    {"replaceEdgeDefinition", Arangox.Api.Graphs, :replace_edge_definition},
    {"replaceFoxxConfiguration", Arangox.Api.Foxx, :replace_foxx_configuration},
    {"replaceFoxxDependencies", Arangox.Api.Foxx, :replace_foxx_dependencies},
    {"replaceFoxxService", Arangox.Api.Foxx, :replace_foxx_service},
    {"replaceUserData", Arangox.Api.Users, :replace_user_data},
    {"replaceVertex", Arangox.Api.Graphs, :replace_vertex},
    {"replaceViewProperties", Arangox.Api.Views, :replace_view_properties},
    {"replaceViewPropertiesSearchAlias", Arangox.Api.Views,
     :replace_view_properties_search_alias},
    {"reserveUniqueIDs", Arangox.Api.Cluster, :reserve_unique_i_ds},
    {"resetLogLevel", Arangox.Api.Monitoring, :reset_log_level},
    {"restoreBackup", Arangox.Api.HotBackups, :restore_backup},
    {"rotateEncryptionAtRestKey", Arangox.Api.Security, :rotate_encryption_at_rest_key},
    {"runFoxxScript", Arangox.Api.Foxx, :run_foxx_script},
    {"runFoxxTests", Arangox.Api.Foxx, :run_foxx_tests},
    {"setClusterMaintenance", Arangox.Api.Cluster, :set_cluster_maintenance},
    {"setDbserverMaintenance", Arangox.Api.Cluster, :set_dbserver_maintenance},
    {"setLicense", Arangox.Api.Administration, :set_license},
    {"setLogLevel", Arangox.Api.Monitoring, :set_log_level},
    {"setQueryCacheProperties", Arangox.Api.Queries, :set_query_cache_properties},
    {"setServerMode", Arangox.Api.Administration, :set_server_mode},
    {"setStructuredLog", Arangox.Api.Monitoring, :set_structured_log},
    {"setUserCollectionPermissions", Arangox.Api.Users, :set_user_collection_permissions},
    {"setUserDatabasePermissions", Arangox.Api.Users, :set_user_database_permissions},
    {"startClusterRebalance", Arangox.Api.Cluster, :start_cluster_rebalance},
    {"startShutdown", Arangox.Api.Administration, :start_shutdown},
    {"truncateCollection", Arangox.Api.Collections, :truncate_collection},
    {"unloadCollection", Arangox.Api.Collections, :unload_collection},
    {"updateAqlQueryTrackingProperties", Arangox.Api.Queries,
     :update_aql_query_tracking_properties},
    {"updateCollectionProperties", Arangox.Api.Collections, :update_collection_properties},
    {"updateDocument", Arangox.Api.Documents, :update_document},
    {"updateDocuments", Arangox.Api.Documents, :update_documents},
    {"updateEdge", Arangox.Api.Graphs, :update_edge},
    {"updateFoxxConfiguration", Arangox.Api.Foxx, :update_foxx_configuration},
    {"updateFoxxDependencies", Arangox.Api.Foxx, :update_foxx_dependencies},
    {"updateUserData", Arangox.Api.Users, :update_user_data},
    {"updateVertex", Arangox.Api.Graphs, :update_vertex},
    {"updateViewProperties", Arangox.Api.Views, :update_view_properties},
    {"updateViewPropertiesSearchAlias", Arangox.Api.Views, :update_view_properties_search_alias},
    {"upgradeFoxxService", Arangox.Api.Foxx, :upgrade_foxx_service},
    {"uploadBackup", Arangox.Api.HotBackups, :upload_backup}
  ]

  # The document is ~1MB. The driver bounds the socket wait by
  # min(remaining budget, :request_timeout) and :request_timeout defaults to
  # 15s, so both must be raised together or the larger one is meaningless.
  @fetch_opts [timeout: 60_000, request_timeout: 60_000]

  setup_all do
    {:ok, conn} = Arangox.start_link(TestHelper.opts(endpoints: TestHelper.default()))

    # Errno.tag/0 is the repo's single version pin, and it must be
    # checked against `/_api/version` — never the document's info.version,
    # whose format differs ("3.12.10 (API v0)").
    assert {:ok, %Response{status: 200, body: %{"version" => server_version}}} =
             Arangox.get(conn, "/_api/version", [], @fetch_opts)

    assert server_version == Errno.tag(),
           """
           version pin mismatch: Errno.tag() is #{inspect(Errno.tag())} but the server \
           at #{TestHelper.default()} reports #{inspect(server_version)}. The gate only \
           means anything against the pinned server — check ARANGO_VERSION and the \
           docker-compose.yml default, or move the pin (priv/arangodb/gen_errno.exs) \
           and this gate's expectations together.
           """

    assert {:ok, %Response{status: 200, body: document}} =
             Arangox.get(conn, @document_path, [], @fetch_opts)

    assert is_map(document) and is_map(document["paths"]),
           "the server answered #{@document_path} without a decodable paths map"

    %{document: document}
  end

  ## The gate

  test "document operations and surface call sites are a multiset bijection",
       %{document: document} do
    document_ops = document_operations(document)
    sites = call_sites()
    assert_cardinality(document, document_ops, sites)

    document_identities = for op <- document_ops, do: {op.method, op.template}
    site_identities = for site <- sites, do: {site.method, site.template}

    missing = missing_operations(document_identities, site_identities)
    surplus = missing_operations(site_identities, document_identities)

    assert missing == [] and surplus == [],
           """
           in the server's document but absent from #{ApiSurface.surface_dir()}:
           #{format_identities(missing)}
           in #{ApiSurface.surface_dir()} but not in the server's document:
           #{format_identities(surplus)}
           """
  end

  test "within each address, query keys and request media match the document",
       %{document: document} do
    document_ops = document_operations(document)
    sites = call_sites()
    assert_cardinality(document, document_ops, sites)

    unrecognized =
      for %{query: {:unrecognized, description}} = site <- sites do
        "#{site.file} #{site.fun}: #{description}"
      end

    assert unrecognized == [],
           "query constructions the extractor does not recognize — extend it " <>
             "deliberately or fix the site:\n" <> Enum.join(unrecognized, "\n")

    document_groups =
      group_profiles(document_ops, fn op -> profile(op.query, op.media) end)

    site_groups =
      group_profiles(sites, fn site ->
        {:ok, keys} = site.query
        profile(Enum.map(keys, &Atom.to_string/1), site.media)
      end)

    mismatches =
      for address <- Enum.sort(Enum.uniq(Map.keys(document_groups) ++ Map.keys(site_groups))),
          document_side = Map.get(document_groups, address, []),
          code_side = Map.get(site_groups, address, []),
          document_side != code_side do
        {address, document_side, code_side}
      end

    assert mismatches == [], format_mismatches(mismatches)
  end

  test "R7a: the document's required query parameters are the checked-in set",
       %{document: document} do
    pairs =
      Enum.sort(
        for op <- document_operations(document), name <- op.required_query do
          {op.operation_id, name}
        end
      )

    assert pairs == @required_query_parameters,
           """
           the document's {operationId, required query parameter} pairs no longer \
           match @required_query_parameters. Required-ness changing at a new pin \
           needs a human decision — decide whether the surface must react, then \
           regenerate the attribute (see its comment).
           in the document but not in @required_query_parameters:
           #{format_entries(pairs -- @required_query_parameters)}
           in @required_query_parameters but not in the document:
           #{format_entries(@required_query_parameters -- pairs)}
           """
  end

  test "operation identity: operationIds and function names match the checked-in mapping",
       %{document: document} do
    document_ids = Enum.sort(for op <- document_operations(document), do: op.operation_id)
    mapping_ids = Enum.sort(for {id, _module, _fun} <- @operation_functions, do: id)

    surface_functions = Enum.sort(for site <- call_sites(), do: {site.module, site.fun})

    mapping_functions =
      Enum.sort(for {_id, module, fun} <- @operation_functions, do: {module, fun})

    assert document_ids == mapping_ids and surface_functions == mapping_functions,
           """
           the surface's operation identities no longer match @operation_functions. \
           A drifted document side means the pin moved; a drifted surface side \
           means a function was renamed, deleted, or duplicated — regenerate the \
           attribute (see its comment) only once the surface change is intended.
           operationIds in the document but not in @operation_functions:
           #{format_entries(document_ids -- mapping_ids)}
           operationIds in @operation_functions but not in the document:
           #{format_entries(mapping_ids -- document_ids)}
           functions in #{ApiSurface.surface_dir()} but not in @operation_functions:
           #{format_entries(surface_functions -- mapping_functions)}
           functions in @operation_functions but not in #{ApiSurface.surface_dir()}:
           #{format_entries(mapping_functions -- surface_functions)}
           """
  end

  test "fidelity gaps: the disclosed counts still hold in the live document",
       %{document: document} do
    itemless =
      Enum.sort(
        for {_path, item} <- document["paths"],
            {method, operation} <- item,
            method in @http_methods,
            is_map(operation),
            {section, subtree} <- [
              request: operation["requestBody"],
              response: operation["responses"]
            ],
            _schema <- itemless_arrays(subtree) do
          {operation["operationId"], section}
        end
      )

    assert itemless == @itemless_array_schemas,
           """
           gap 1 moved: the document now carries #{length(itemless)} array schemas \
           without items (disclosed: #{length(@itemless_array_schemas)}), at:
           #{format_entries(itemless)}
           """

    header_counts =
      Enum.frequencies(
        for {_path, item} <- document["paths"],
            {method, operation} <- item,
            method in @http_methods,
            is_map(operation),
            %{"in" => "header", "name" => name} <- operation["parameters"] || [] do
          name
        end
      )

    assert header_counts == @header_parameter_counts,
           "gap 2 moved: header parameter counts are now #{inspect(header_counts)} " <>
             "(total #{header_counts |> Map.values() |> Enum.sum()}), disclosed: " <>
             "#{inspect(@header_parameter_counts)} (total " <>
             "#{@header_parameter_counts |> Map.values() |> Enum.sum()})"

    assert Enum.sum(Map.values(@path_prefix_counts)) == @expected_path_count,
           "@path_prefix_counts no longer sums to @expected_path_count — " <>
             "the pins were edited apart"

    prefix_counts =
      document["paths"]
      |> Map.keys()
      |> Enum.frequencies_by(fn path ->
        cond do
          String.starts_with?(path, "/_db/{database-name}/") -> :database_argument
          String.starts_with?(path, "/_db/_system/") -> :hardcoded_system
          String.starts_with?(path, "/_db/") -> :unexpected_db_prefix
          true -> :no_db_prefix
        end
      end)

    assert prefix_counts == @path_prefix_counts,
           "gap 3 moved: path keys by prefix are now #{inspect(prefix_counts)}, " <>
             "disclosed: #{inspect(@path_prefix_counts)}"
  end

  # The adapter's path-parameter refusal (client.ex, `check_path_args`)
  # sees only the values listed under `args:` — the url arrives with every
  # value already interpolated, so a parameter missing from `args:` is
  # invisible to the check and its slash/path-alteration refusal silently
  # disappears. The address and profile comparisons never read `args:`, so
  # only this test catches that edit.
  test "every URL-interpolated path parameter has an args: binding" do
    unbound =
      for site <- call_sites(),
          name <- template_parameters(site.template),
          name not in site.args do
        "  #{site.file} #{site.fun}: #{name}"
      end

    assert unbound == [],
           """
           path parameters interpolated into a url but absent from args: — the \
           adapter validates path values only through args:, so these skip the \
           path-parameter refusal:
           #{Enum.join(unbound, "\n")}
           """
  end

  ## Gate logic, exercised on synthetic input so its failure modes are
  ## tested without breaking the real surface.

  describe "gate logic" do
    test "an absence fails — there is no waiver list" do
      document = [{:get, "/_api/version"}, {:post, "/_api/cursor"}]
      surface = [{:get, "/_api/version"}]

      assert missing_operations(document, surface) == [{:post, "/_api/cursor"}]
    end

    # A set would call these equal; the document really does carry the
    # operation twice, so losing one has to fail.
    test "a duplicate operation present once is a missing operation" do
      document = [{:post, "/_api/document/{collection}"}, {:post, "/_api/document/{collection}"}]
      surface = [{:post, "/_api/document/{collection}"}]

      assert missing_operations(document, surface) ==
               [{:post, "/_api/document/{collection}"}]
    end

    test "a surplus call site fails the other direction" do
      document = [{:get, "/_api/version"}]
      surface = [{:get, "/_api/version"}, {:get, "/_api/stale"}]

      assert missing_operations(surface, document) == [{:get, "/_api/stale"}]
    end
  end

  describe "query extraction" do
    test "a Keyword.take literal is read as its key set" do
      body =
        quote do
          query = Keyword.take(opts, [:a, :b])
          client.request(%{query: query})
        end

      assert extract_query(body) == {:ok, [:a, :b]}
    end

    test "the onlyget pipe is the one recognized injection" do
      body =
        quote do
          query = opts |> Keyword.take([:ignoreRevs]) |> Keyword.put(:onlyget, true)
          client.request(%{query: query})
        end

      assert extract_query(body) == {:ok, [:ignoreRevs, :onlyget]}
    end

    test "an absent query key and a literal [] are both the empty set" do
      absent = quote do: client.request(%{method: :get})
      empty = quote do: client.request(%{query: []})

      assert extract_query(absent) == {:ok, []}
      assert extract_query(empty) == {:ok, []}
    end

    test "any other construction is unrecognized, not silently empty" do
      appended =
        quote do
          query = Keyword.take(opts, [:a]) ++ [b: 1]
          client.request(%{query: query})
        end

      inline = quote do: client.request(%{query: Keyword.take(opts, [:a])})
      helper_call = quote do: client.request(%{query: build_query(opts)})

      assert {:unrecognized, _} = extract_query(appended)
      assert {:unrecognized, _} = extract_query(inline)
      assert {:unrecognized, _} = extract_query(helper_call)
    end
  end

  describe "request media extraction" do
    test "a single media entry is read as its string" do
      body = quote do: client.request(%{request: [{"application/json", :map}]})

      assert extract_media(body) == ["application/json"]
    end

    test "an absent request: key is the empty set" do
      body = quote do: client.request(%{method: :get})

      assert extract_media(body) == []
    end

    test "a parameterized media type survives byte-for-byte" do
      body = quote do: client.request(%{request: [{"text/plain; charset=utf-8", :map}]})

      assert extract_media(body) == ["text/plain; charset=utf-8"]
    end
  end

  ## Comparison plumbing

  # Multiset difference: each occurrence in `from` must be matched by its own
  # occurrence in `present_in`, so a duplicated operation cannot be satisfied
  # by a single call site.
  defp missing_operations(from, present_in) do
    remaining =
      Enum.reduce(present_in, Enum.frequencies(from), fn op, acc ->
        Map.update(acc, op, -1, &(&1 - 1))
      end)

    remaining
    |> Enum.filter(fn {_op, count} -> count > 0 end)
    |> Enum.flat_map(fn {op, count} -> List.duplicate(op, count) end)
    |> Enum.sort()
  end

  defp assert_cardinality(document, document_ops, sites) do
    assert map_size(document["paths"]) == @expected_path_count,
           "the fetched document carries #{map_size(document["paths"])} paths, " <>
             "expected #{@expected_path_count} at the #{Errno.tag()} pin"

    assert length(document_ops) == @expected_operation_count,
           "the fetched document carries #{length(document_ops)} operations, " <>
             "expected #{@expected_operation_count} at the #{Errno.tag()} pin"

    assert length(sites) == @expected_operation_count,
           "extracted #{length(sites)} call sites from #{ApiSurface.surface_dir()}, " <>
             "expected #{@expected_operation_count} — extraction regression or a surface edit"
  end

  # Within a group, order among sibling operations is meaningless, so each
  # group's profiles are compared as a sorted multiset. The PUT document path
  # is the only group whose members differ in these sets; `onlyget` is what
  # distinguishes getDocuments from replaceDocuments there.
  defp group_profiles(entries, to_profile) do
    entries
    |> Enum.group_by(&{&1.method, &1.template}, to_profile)
    |> Map.new(fn {address, profiles} -> {address, Enum.sort(profiles)} end)
  end

  defp profile(query_names, media), do: {Enum.sort(query_names), Enum.sort(media)}

  defp format_identities([]), do: "  (none)"

  defp format_identities(identities) do
    Enum.map_join(identities, "\n", fn {method, template} ->
      "  #{method |> to_string() |> String.upcase()} #{template}"
    end)
  end

  # Failure-message lines for whichever entry shape a diff produced:
  # `{module, function}`, `{operationId, parameter}`, or a bare name.
  defp format_entries([]), do: "  (none)"

  defp format_entries(entries) do
    Enum.map_join(entries, "\n", fn
      {module, fun} when is_atom(module) and is_atom(fun) -> "  #{inspect(module)}.#{fun}"
      {operation_id, name} -> "  #{operation_id} #{name}"
      entry -> "  #{entry}"
    end)
  end

  defp format_mismatches(mismatches) do
    Enum.map_join(mismatches, "\n\n", fn {{method, template}, document_side, code_side} ->
      """
      #{method |> to_string() |> String.upcase()} #{template}
        document: #{inspect(document_side)}
        code:     #{inspect(code_side)}\
      """
    end)
  end

  ## Document extraction

  defp document_operations(document) do
    for {path, item} <- document["paths"],
        {method, operation} <- item,
        method in @http_methods,
        is_map(operation) do
      %{
        method: String.to_atom(method),
        template: path |> strip_fragment() |> normalize_template(),
        operation_id: operation["operationId"],
        query: query_parameter_names(operation),
        required_query: required_query_parameter_names(operation),
        media: media_types(operation)
      }
    end
  end

  defp query_parameter_names(operation) do
    for %{"in" => "query", "name" => name} <- operation["parameters"] || [], do: name
  end

  defp required_query_parameter_names(operation) do
    for %{"in" => "query", "name" => name, "required" => true} <- operation["parameters"] || [],
        do: name
  end

  defp media_types(operation) do
    case operation do
      %{"requestBody" => %{"content" => content}} -> Map.keys(content)
      _ -> []
    end
  end

  # Every schema object under `node` declaring `"type": "array"` without an
  # `items` key, however deeply nested. The walk is generic over the decoded
  # JSON — it does not name OpenAPI's nesting keywords — so `properties`,
  # `items`, and response `content` are all covered without a keyword list
  # that could fall behind the document.
  defp itemless_arrays(%{} = node) do
    here =
      if node["type"] == "array" and not Map.has_key?(node, "items"), do: [node], else: []

    here ++ Enum.flat_map(node, fn {_key, value} -> itemless_arrays(value) end)
  end

  defp itemless_arrays(list) when is_list(list),
    do: Enum.flat_map(list, &itemless_arrays/1)

  defp itemless_arrays(_other), do: []

  defp strip_fragment(path), do: path |> String.split("#", parts: 2) |> hd()

  # The rename rule from the moduledoc, applied to path parameters only.
  defp normalize_template(path) do
    Regex.replace(~r/\{([^}]+)\}/, path, fn _whole, name ->
      "{" <> normalize_param(name) <> "}"
    end)
  end

  defp normalize_param(name) do
    if Regex.match?(~r/^[a-z_][a-zA-Z0-9_]*$/, name) do
      name
    else
      normalized =
        name
        |> String.replace(~r/[^a-zA-Z0-9]+/, "_")
        |> Macro.underscore()
        |> String.replace(~r/_+/, "_")
        |> String.trim("_")

      if Regex.match?(~r/^[a-z_]/, normalized), do: normalized, else: "p_" <> normalized
    end
  end

  ## Surface extraction

  # The file listing and the raw call-site read (module, function, body,
  # request pairs) come from `Arangox.TestSupport.ApiSurface`, shared with the
  # unit-tier surface gate. This section only builds the gate's per-site view
  # — address, args, query, media — on top of that read.

  defp call_sites do
    for file <- ApiSurface.surface_files(), site <- file_call_sites(file), do: site
  end

  defp file_call_sites(file) do
    for %{module: module, fun: fun, body: body, pairs: pairs} <- ApiSurface.call_sites(file) do
      %{
        file: file,
        module: module,
        fun: fun,
        method: Keyword.fetch!(pairs, :method),
        template: site_template(file, fun, Keyword.fetch!(pairs, :url)),
        args: arg_names(pairs),
        query: extract_query_from(pairs, body),
        media: request_media(pairs)
      }
    end
  end

  defp site_template(file, fun, url_ast) do
    case ApiSurface.template(url_ast) do
      {:ok, template} ->
        template

      :error ->
        flunk(
          "#{Path.basename(file)} #{fun}: url construction the template " <>
            "reconstruction does not recognize — extend ApiSurface.template/2 " <>
            "deliberately or fix the site"
        )
    end
  end

  defp extract_query(body) do
    body |> ApiSurface.request_pairs() |> hd() |> extract_query_from(body)
  end

  defp extract_media(body) do
    body |> ApiSurface.request_pairs() |> hd() |> request_media()
  end

  # The effective query key set a call site can send, or `{:unrecognized,
  # description}`, which the gate turns into a failure. Recognized shapes are
  # deliberately few: an absent `query:`, a literal `[]`, or a `query`
  # variable bound in the same function to a `Keyword.take(opts, [literals])`
  # — optionally piped through `Keyword.put(:onlyget, true)`, the one
  # documented injection (get_documents must force `onlyget=true`, or
  # its address replaces documents). Anything else — helper calls, `++`,
  # merges, other literals — must fail the gate rather than pass unchecked.
  defp extract_query_from(pairs, body) do
    case Keyword.fetch(pairs, :query) do
      :error -> {:ok, []}
      {:ok, []} -> {:ok, []}
      {:ok, {:query, _, context}} when is_atom(context) -> query_binding(body)
      {:ok, other} -> {:unrecognized, "query: #{Macro.to_string(other)}"}
    end
  end

  defp query_binding(body) do
    {_ast, bindings} =
      Macro.prewalk(body, [], fn
        {:=, _, [{:query, _, context}, rhs]} = node, acc when is_atom(context) ->
          {node, [rhs | acc]}

        node, acc ->
          {node, acc}
      end)

    case bindings do
      [rhs] -> query_rhs(rhs)
      [] -> {:unrecognized, "query: references a variable with no `query =` binding"}
      _many -> {:unrecognized, "more than one `query =` binding in one function"}
    end
  end

  defp query_rhs({{:., _, [{:__aliases__, _, [:Keyword]}, :take]}, _, [{:opts, _, _}, keys]}) do
    literal_keys(keys)
  end

  defp query_rhs(
         {:|>, _,
          [
            {:|>, _,
             [{:opts, _, _}, {{:., _, [{:__aliases__, _, [:Keyword]}, :take]}, _, [keys]}]},
            {{:., _, [{:__aliases__, _, [:Keyword]}, :put]}, _, [:onlyget, true]}
          ]}
       ) do
    with {:ok, keys} <- literal_keys(keys), do: {:ok, keys ++ [:onlyget]}
  end

  defp query_rhs(other), do: {:unrecognized, "query = #{Macro.to_string(other)}"}

  defp literal_keys(keys) do
    if is_list(keys) and Enum.all?(keys, &is_atom/1) do
      {:ok, keys}
    else
      {:unrecognized, "Keyword.take with a non-literal key list"}
    end
  end

  # Media strings are compared exactly as written. Verified against the live
  # 3.12.10 document: its requestBody content keys are byte-for-byte the
  # strings the surface declares, parameterized ones included
  # ("text/plain; charset=utf-8") — so no media-type parameter stripping.
  defp request_media(pairs) do
    case Keyword.fetch(pairs, :request) do
      :error ->
        []

      {:ok, entries} when is_list(entries) ->
        for entry <- entries do
          case entry do
            {media, _shape} when is_binary(media) ->
              media

            other ->
              flunk("unrecognized request media entry: #{Macro.to_string(other)}")
          end
        end
    end
  end

  # The keys of the `args:` keyword list, as strings. Absence reads as the
  # empty list on purpose: the adapter treats missing args as nothing to
  # check, and the binding test must see that as unbound parameters, not crash.
  defp arg_names(pairs) do
    for entry <- Keyword.get(pairs, :args, []) do
      case entry do
        {name, _value} when is_atom(name) -> Atom.to_string(name)
        other -> flunk("unrecognized args entry: #{Macro.to_string(other)}")
      end
    end
  end

  defp template_parameters(template) do
    for [name] <- Regex.scan(~r/\{([^}]+)\}/, template, capture: :all_but_first), do: name
  end
end
