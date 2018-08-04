#ifndef HEXAGON_EX
#define HEXAGON_EX
defmodule Hexagon do
  @moduledoc """
  A hex repo fetcher and builder
  """

  require Logger

  def check_all() do
    path = packages_dir()
    File.mkdir_p(path)
    {:ok, %{packages: packages}, _} = :hex_repo.get_versions()

    log = Hexagon.Log.new("all")

    packages
    |> Flow.from_enumerable()
    |> Flow.map(fn info -> sync_package(info, path) end)
    |> Enum.each(fn path -> build_package(path, log) end)

    Hexagon.Log.close(log)
  end

  def check_one(package) do
    path = packages_dir()
    case :hex_repo.get_package("ex_wpvulndb") do
      {:error, _} = error -> error
      {:ok, %{releases: releases}, _} ->
        log = Hexagon.Log.new(package)
        version = version_from_releases(releases)
        sync_package(package, version, path)
        |> build_package(log)
        Hexagon.Log.close(log)
    end
  end

  defp packages_dir() do
    base_path = Application.get_env(:hexagon, :package_path, "~/packages")
                |> Path.expand()
    File.mkdir_p(base_path)
    base_path
  end

  defp sync_package(%{name: package, versions: versions}, base_path) do
    version = Enum.at(versions, Enum.count(versions) - 1)
    sync_package(package, version, base_path)
  end

  defp sync_package(package, version, base_path) do
    package_dir = Path.join(base_path, package)
    #IO.puts("Checking #{inspect package}, #{inspect current_version}")
    if File.exists?(package_dir) do
      clean_package_dir(package_dir, version)
    else
      full_path = Path.join(package_dir, version)
      :ok = File.mkdir_p(full_path)
      fetch_package(full_path, package, version)
    end

    Path.join(package_dir, version)
  end

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

  defp clean_package_dir(dir, keep_subdir) do
    {:ok, files} = File.ls(dir)

    found_keeper = Enum.reduce(files, false,
                               fn ^keep_subdir, _ -> true
                                  subdir, acc -> 
                                    File.rmdir(dir <> subdir)
                                    acc
                               end)
    if !found_keeper do
      File.mkdir(Path.join(dir, keep_subdir))
    end
  end

  defp fetch_package(path, package, version) do
    case :hex_repo.get_tarball(package, version) do
      {:ok, tarball, _opts} ->
        :hex_tarball.unpack(tarball, String.to_charlist(path))

      _ -> {:error, {:download_failed, package, version}}
    end
  end

  # mix deps.get && mix compile && mix deps.clean --all && mix clean
  def build_package(path, log) do
    IO.puts("=> #{path}")
    path = String.to_charlist(path)
    with :ok <- get_deps(path, log),
         :ok <- compile(path, log) do
      :ok
    end

    cleanup(path)
  end

  defp get_deps(path, log) do
    :exec.run('mix deps.get', [:sync, :stderr, :stdout, {:cd, path}])
    |> command_completed(path, "deps.get", log)
  end

  defp compile(path, log) do
    :exec.run('mix compile', [:sync, :stderr, :stdout, {:cd, path}])
    |> command_completed(path, "compile", log)
  end

  defp cleanup(path) do
    :exec.run('mix deps.clean --all', [:sync, {:cd, path}])
    :exec.run('mix clean', [:sync, {:cd, path}])
    :ok
  end

  defp command_completed({:ok, _}, _path, _doing, _log), do: :ok
  defp command_completed({:error, rv}, path, doing, log) do
    stderr = Keyword.get(rv, :stderr)
    stdout = Keyword.get(rv, :stdout, [])
             |> Enum.filter(fn x -> String.contains?(x, "error") end)
             |> Enum.join("\n")

    data = %{
      status: "failed",
      package: path,
      stage: doing,
      stderr: stderr,
      stdout: stdout
    }

    Hexagon.Log.add_entry(log, data)
    :error
  end
end
#endif // HEXAGON_EX
