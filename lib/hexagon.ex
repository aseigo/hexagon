defmodule Hexagon do
  @moduledoc """
  A hex repo fetcher and builder
  """

  require Logger

  def check(path) do
    File.mkdir_p(path)
    {:ok, %{packages: packages}, _} = :hex_repo.get_versions()

    packages
    |> Flow.from_enumerable()
    |> Flow.map(fn info -> sync_package(info, path) end)
    |> Flow.each(fn path -> build_package(path) end)
    |> Enum.count()
  end

  defp sync_package(%{name: package, versions: versions}, base_path) do
    current_version = Enum.at(versions, Enum.count(versions) - 1)
    package_dir = Path.join(base_path, package)
    #IO.puts("Checking #{inspect package}, #{inspect current_version}")
    if File.exists?(package_dir) do
      clean_package_dir(package_dir, current_version)
    else
      full_path = Path.join(package_dir, current_version)
      :ok = File.mkdir_p(full_path)
      fetch_package(full_path, package, current_version)
    end

    Path.join(package_dir, current_version)
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
  def build_package(path) do
    path = String.to_charlist(path)
    with :ok <- get_deps(path),
         :ok <- compile(path) do
      :ok
    end

    cleanup(path)
  end

  defp get_deps(path) do
    :exec.run('mix deps.get', [:sync, :stderr, :stdout, {:cd, path}])
    |> command_completed(path, "deps.get")
  end

  defp compile(path) do
    :exec.run('mix compile', [:sync, :stderr, :stdout, {:cd, path}])
    |> command_completed(path, "compile")
  end

  defp cleanup(path) do
    :exec.run('mix deps.clean --all', [:sync, {:cd, path}])
    :exec.run('mix clean', [:sync, {:cd, path}])
    :ok
  end

  defp command_completed({:ok, _}, _path, _doing), do: :ok
  defp command_completed({:error, rv}, path, doing) do
    #TODO: this could be a LOT nicer
    stderr = Keyword.get(rv, :stderr)
    stdout = Keyword.get(rv, :stdout, [])
             |> Enum.filter(fn x -> String.contains?(x, "error") end)
             |> Enum.join("\n")
    msg = "FAILED at #{doing}: #{path}\nstdout =>\n#{stdout}\nstderr =>\n#{stderr}"

    Logger.error(msg)
    :error
  end
end
