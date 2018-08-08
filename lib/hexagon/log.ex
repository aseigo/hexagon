defmodule Hexagon.Log do
  import OK, only: [~>>: 2]

  def new(name \\ "") when is_binary(name)  do
    full_path = Path.join(directory(), generate_filename(name))
    IO.puts("Starting a log at: #{full_path}")
    {:ok, file} = File.open(full_path, [:write, :utf8])
    IO.write(file, "[\n")
    file
  end

  def add_entry(file, data) when is_map(data) do
    {:ok, json} = Jason.encode(data)
    IO.write(file, json)
    IO.write(file, ",\n")
  end

  def close(file) do
    # we write the closing 2 bytes back to over-write the trailing comma
    :file.pwrite(file, {:cur, -2}, "\n]")
    File.close(file)
  end

  def fullpath(filename) do
    if File.exists?(filename) do
      Path.expand(filename)
    else
      Path.join(directory(), filename) |> Path.expand()
    end
  end

  def failures(filename) do
    fullpath(filename)
    |> File.read()
    ~>> Jason.decode()
    ~>> Enum.reduce([], fn %{"built" => false, "package" => package}, acc -> [package | acc]
                          _, acc -> acc
                        end)
  end

  def package_counts(filename) do
    fullpath(filename)
    |> File.read()
    ~>> Jason.decode()
    ~>> Enum.reduce({0, 0}, fn %{"built" => false}, {p, f} -> {p + 1, f + 1}
                               _, {p, f} -> {p + 1, f}
                            end)
  end

  defp directory() do
    base_path = Application.get_env(:hexagon, :log_path, "~/package_logs")
                |> Path.expand()
    File.mkdir_p(base_path)
    base_path
  end

  defp generate_filename(name) do
    filename = DateTime.utc_now() |> DateTime.to_unix() |> to_string()

    if name != "" do
      filename <> "_" <> name <> "_hexagon.log"
    else
      filename <> "_hexagon.log"
    end
  end
end
