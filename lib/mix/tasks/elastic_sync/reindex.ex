defmodule Mix.Tasks.ElasticSync.Reindex do
  import ElasticSync.Schema, only: [get_index: 1, get_alias: 1]

  def run(args) do
    Mix.Task.run "loadpaths", args

    unless "--no-compile" in args do
      Mix.Project.compile(args)
    end

    case parse_args(args) do
      {:ok, schema, sync_repo} ->
        ecto_repo = sync_repo.__elastic_sync__(:ecto)
        search_repo = sync_repo.__elastic_sync__(:search)
        Mix.Ecto.ensure_started(ecto_repo, args)
        reindex(schema, ecto_repo, search_repo, args)
      {:error, message} ->
        Mix.raise(message)
    end
  end

  def reindex(schema, ecto_repo, search_repo, _args) do
    records = ecto_repo.all(schema)
    index_name = get_index(schema)
    alias_name = get_alias(schema)

    # Create a new index with the name of the alias
    {:ok, _, _} = search_repo.create_index(alias_name)

    # Populate the new index
    {:ok, _, _} = search_repo.bulk_index(schema, records, index: alias_name)

    # Refresh the index
    {:ok, _, _} = search_repo.refresh(schema, index: alias_name)

    # Alias our new index as the old index
    {:ok, _, _} = search_repo.swap_alias(index_name, alias_name)

    # TODO: Clean up old aliases...
  end

  defp parse_args(args) when length(args) < 2 do
    {:error, "Wrong number of arguments."}
  end

  defp parse_args([sync_repo_name, schema_name | _args]) do
    with {:ok, schema} <- parse_elastic_sync(schema_name),
         {:ok, sync_repo} <- parse_elastic_sync(sync_repo_name),
         do: {:ok, schema, sync_repo}
  end

  defp parse_elastic_sync(name) do
    mod = Module.concat([name])

    case Code.ensure_compiled(mod) do
      {:module, _} ->
        if function_exported?(mod, :__elastic_sync__, 1) do
          {:ok, mod}
        else
          {:error, "Module #{inspect mod} isn't using elastic_sync."}
        end
      {:error, error} ->
        {:error, "Could not load #{inspect mod}, error: #{inspect error}."}
    end
  end
end
