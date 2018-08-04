defmodule Hexagon.Log do
  def new(name \\ "") when is_binary(name)  do
    full_path = Path.join(directory(), generate_filename(name))
    {:ok, file} = File.open(full_path, [:append])
    IO.write(file, "[\n")
    file
  end

  def add_entry(file, data) when is_map(data) do
    {:ok, json} = Jason.encode(data)
    IO.write(file, json)
    IO.write(file, ",\n")
  end

  def close(file) do
    #FIXME: we add a lame entry since we append a ',' to ever entry in add_entry
    IO.write(file, "{}\n]")
    File.close(file)
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
