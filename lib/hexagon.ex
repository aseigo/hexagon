defmodule Hexagon do
  @moduledoc """
  A hex repo fetcher and builder
  """

  @doc """
  """
  def sync_packages(%{package_path: path}) do
    File.mkdir_p(path)
    {:ok, %{packages: packages}, _} = :hex_repo.get_versions()

    Enum.each(packages, fn package -> sync_package(package, path) end)
  end

  def sync_package(%{name: package, versions: versions}, base_path) do
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
end
