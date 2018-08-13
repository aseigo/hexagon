defmodule Hexagon do
  @moduledoc """
  A hex repo fetcher and builder with several modes of operation:

  * `Hexagon.check_all()` => This will download and attempt to build all packages
  * `Hexagon.check_updated()` => This will sync the local package cache, and build packages
  with new versions available
  * `Hexagon.check_failures(logfile)` => This will build all packages that previous failed
  as recorded in the file pointed to by logfile. Logfile may be either the name of a log
  file or a full path. The file should be a Hexagon logfile from a previous run.
  * `Hexagon.check_one(packagename)` => This checks a single package
  * `Hexagon.sync_package_cache()` => Ensures the local package cache is current; the `check_*`
  functions all take appropriate syncronization steps, so one does not usually need to
  run this explicitly

  With the exception of `Hexagon.check_one/1`, the Hexagon function accept the following
  options:

  * `only`: a list of packages to limit the build to
  * `exclude`: a list of packages to exclude from builds
  * `logfile`: a string to use as part of the logfile name
  """

  require Logger

  @spec check_all(opts :: Keyword.t()) :: package_processed_count :: non_neg_integer
  @doc """
  Checks all packages after first sync'ing the local cache.
  """
  def check_all(opts \\ []) do
    logfile = Keyword.get(opts, :logfile, "all")
    {log, logfile_path} = Hexagon.Log.new(logfile)

    parallel_builds = Application.get_env(:hexagon, :parallel_builds, 1)

    prep_package_sync(opts)
    |> Flow.partition(stages: parallel_builds, max_demand: parallel_builds)
    |> Flow.each(fn package -> build_package(package, log) end)
    |> Flow.run()

    Hexagon.Log.close(log)

    {processed, failed} = Hexagon.Log.package_counts(logfile_path)
    if processed > 0 do
      fail_percent = Float.round(failed / processed, 3) * 100
      IO.puts("Processed #{processed} packages, encountered #{failed} build failures (#{fail_percent}%)")
    else
      IO.puts("No packages processed")
    end

    processed
  end

  @spec check_one(package_name :: binary) :: :ok | {:error, any()}
  @doc """
  Updates and checks one package
  """
  def check_one(package_name) do
    case :hex_repo.get_package(hex_config(), package_name) do
      {:error, _} = error -> error
      {:ok, {_response_code, _response_headers, %{releases: releases}}} ->
        {log, _} = Hexagon.Log.new(package_name)

        version = version_from_releases(releases)
        path = packages_dir()
        sync_package(package_name, version, path, :all)
        |> build_package(log)

        Hexagon.Log.close(log)
        :ok
    end
  end

  @spec check_updated(opts :: Keyword.t()) :: package_processed_count :: non_neg_integer
  def check_updated(opts \\ []) do
    Keyword.put(opts, :only_updated, true)
    |> prepend_logfile_name("updates")
    |> check_all()
  end

  @spec check_failures(logfile :: String.t(), opts :: Keyword.t()) :: package_processed_count :: non_neg_integer
  def check_failures(logfile, opts \\ []) do
    Keyword.put(opts, :only, Hexagon.Log.failures(logfile))
    |> prepend_logfile_name("failures")
    |> check_all()
  end

  @spec sync_package_cache(opts :: Keyword.t()) :: :ok
  def sync_package_cache(opts \\ []) do
    prep_package_sync(opts)
    |> Flow.run()
  end

  @spec prepend_logfile_name(opts :: Keyword.t(), prefix :: String.t()) :: String.t()
  defp prepend_logfile_name(opts, prefix) do
    Keyword.get(opts, :logfile)
    |> merge_logfile_parts(prefix)
    |> (fn fullname -> Keyword.put(opts, :logfile, fullname) end).()
  end

  @spec merge_logfile_parts(nil | String.t(), prefix :: String.t()) :: String.t()
  defp merge_logfile_parts(nil, prefix), do: prefix
  defp merge_logfile_parts(name, prefix), do: "#{prefix}_#{name}"

  @spec prep_package_sync(opts :: Keyword.t()) :: %Flow{}
  defp prep_package_sync(opts) do
    path = packages_dir()
    File.mkdir_p(path)
    {:ok, {_response_code, _response_headers, %{packages: packages}}} = :hex_repo.get_versions(hex_config())

    only_updated = Keyword.get(opts, :only_updated, :all)

    packages
    |> Flow.from_enumerable()
    |> add_whitelist_filter(Keyword.get(opts, :only))
    |> add_blacklist_filter(Keyword.get(opts, :exclude))
    #|> Flow.each(fn %{name: package} -> IO.puts("Doing #{package}") end)
    |> Flow.map(fn info -> sync_package(info, path, only_updated) end)
    |> Flow.filter(fn x -> x != nil end)
  end

  @spec add_blacklist_filter(%Flow{}, exclude_packages :: []) :: %Flow{}
  defp add_blacklist_filter(flow, list) when is_list(list) do
    blacklist = Enum.reduce(list, %{}, fn p, acc -> Map.put(acc, p, 1) end)
    Flow.filter(flow, fn %{name: package} -> !Map.has_key?(blacklist, package) end)
  end

  defp add_blacklist_filter(flow, _), do: flow

  @spec add_whitelist_filter(%Flow{}, include_packages :: []) :: %Flow{}
  defp add_whitelist_filter(flow, list) when is_list(list) do
    whitelist = Enum.reduce(list, %{}, fn p, acc -> Map.put(acc, p, 1) end)
    Flow.filter(flow, fn %{name: package} -> Map.has_key?(whitelist, package) end)
  end

  defp add_whitelist_filter(flow, _), do: flow

  @spec packages_dir() :: String.t()
  defp packages_dir() do
    base_path = Application.get_env(:hexagon, :package_path, "~/packages")
                |> Path.expand()
    File.mkdir_p(base_path)
    base_path
  end

  @spec sync_package(package_desc :: %{}, packages_path :: String.t(), only_updated :: false | any()) :: nil | {package :: String.t(), path :: String.t()}
  defp sync_package(%{name: package, versions: versions}, base_path, only_updated) do
    version = Enum.at(versions, Enum.count(versions) - 1)
    sync_package(package, version, base_path, only_updated)
  end

  @spec sync_package(package :: String.t(), verson :: String.t(), packages_path :: String.t(), only_updated :: false | any()) :: nil | {package :: String.t(), path :: String.t()}
  defp sync_package(package, version, base_path, only_updated) do
    package_dir = Path.join(base_path, package)
    #IO.puts("Checking #{inspect package}, #{inspect version}")

    fetch? =
    if File.exists?(package_dir) do
      clean_package_dir(package_dir, version)
    else
      true
    end

    if fetch? do
      full_path = Path.join(package_dir, version)
      :ok = File.mkdir_p(full_path)
      fetch_package(full_path, package, version)
    end

    if only_updated === true and !fetch? do
      nil
    else
      {package, Path.join(package_dir, version)}
    end
  end

  @spec version_from_releases(release_info :: [%{}]) :: version :: String.t()
  defp version_from_releases(releases) do
    Enum.reduce(releases, "0.0.0",
                fn %{version: version}, acc ->
                  if Version.compare(version, acc) == :gt do
                    version
                  else
                    acc
                  end
                end)
  end

  @spec clean_package_dir(dir :: String.t(), keep_subdir :: boolean) :: current_version_exists :: boolean
  defp clean_package_dir(dir, keep_subdir) do
    {:ok, files} = File.ls(dir)

    found_keeper =
    Enum.reduce(files, false,
                fn ^keep_subdir, _ -> true
                    subdir, acc -> 
                      File.rmdir(dir <> subdir)
                      acc
                end)

    !found_keeper
  end

  @spec fetch_package(packages_path :: String.t(), package :: String.t(), version :: String.t()) :: :ok | {:error, reason :: any()}
  defp fetch_package(path, package, version) do
    IO.puts("=> Fetching #{package} #{version}")

    case :hex_repo.get_tarball(hex_config(), package, version) do
      {:ok, {_response_code, _response_headers, tarball}} ->
        unpack(tarball, String.to_charlist(path))

      error ->
        Logger.debug("Failed to download #{package} v#{version} with #{inspect error}")
        File.rmdir(path)
        {:error, {:download_failed, package, version}}
    end
  end

  @spec create_petridish() :: path_to_petridish :: String.t()
  defp create_petridish() do
    petridish_template = Path.join(System.cwd(), "priv/petridish")
    {:ok, petridish} = Temp.mkdir(%{prefix: "hexagon_petridish"})
    File.cp_r(petridish_template, petridish)
    String.to_charlist(petridish)
  end

  @spec destroy_petridish(path_to_petridish :: String.t()) :: :ok
  defp destroy_petridish(petridish) do
    File.rm_rf(petridish)
    :ok
  end

  @spec build_package({package_name :: String.t(), path :: String.t()}, logfile :: pid()) :: :ok
  defp build_package({package, path}, log) do
    petridish = create_petridish()
    Hexagon.MixFile.gen(petridish, package, path)

    with :ok <- get_deps(petridish, package, path, log),
         :ok <- compile(petridish, package, path, log) do
      :ok
    end

    destroy_petridish(petridish)
  end

  @spec unpack(tarball :: :hext_tarball.tarball(), path :: String.t()) :: :ok | {:error, reason :: any}
  defp unpack(tarball, path) do
    case :hex_tarball.unpack(tarball, path) do
      {:ok, _} -> :ok
      {:error, reason} ->
        Logger.debug("Failed to unpack to #{path}, reason: #{inspect reason}")
        {:error, reason}
    end
  end

  @spec get_deps(path_to_petridish :: String.t(), package_name :: String.t(), packages_path :: String.t(), log :: pid()) :: :ok | :error
  defp get_deps(petridish, package, path, log) do
    :exec.run('MIX_ENV=prod mix deps.get', [:sync, :stderr, :stdout, {:cd, petridish}])
    |> command_completed(package, path, :deps, log)
  end

  @spec compile(path_to_petridish :: String.t(), package_name :: String.t(), packages_path :: String.t(), log :: pid()) :: :ok | :error
  defp compile(petridish, package, path, log) do
    :exec.run('MIX_ENV=prod mix compile', [:sync, :stderr, :stdout, {:cd, petridish}])
    |> command_completed(package, path, :compile, log)
  end

  @spec command_completed({:ok | :error, info :: any}, package_name :: String.t(), packages_path :: String.t(), action :: atom(), log :: pid()) :: :ok | :error
  defp command_completed({:ok, _}, package, path, :compile, log) do
    data = %{
      built: true,
      package: "#{package}",
      version: Path.basename(path)
    }

    Hexagon.Log.add_entry(log, data)
    :ok
  end
  defp command_completed({:ok, _}, _package, _path, _doing, _log), do: :ok

  defp command_completed({:error, rv}, package, path, doing, log) do
    stderr = Keyword.get(rv, :stderr)
    stdout = Keyword.get(rv, :stdout, [])
             |> Enum.filter(fn x -> String.contains?(x, "error") end)
             |> Enum.join("\n")

    data = %{
      built: false,
      package: "#{package}",
      version: Path.basename(path),
      stage: doing,
      stderr: stderr,
      stdout: stdout
    }

    Hexagon.Log.add_entry(log, data)
    IO.puts("😞 FAILED => #{package} @ #{path}")
    :error
  end

  @spec hex_config() :: config :: %{}
  defp hex_config(), do: :hex_core.default_config()
end
