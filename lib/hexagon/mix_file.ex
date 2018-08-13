defmodule Hexagon.MixFile do
  def gen(project_path, package_name, package_path) do
    project_path
    |> Path.join("mix.lock")
    |> File.rm()

    package_version = Path.basename(package_path)

    content = [~s(
defmodule Petridish.MixProject do
use Mix.Project

def project do
[
  app: :petridish,
  version: "0.1.0",
  deps: [{:), package_name, ~s(, "~> ), package_version, ~s("}]
]
end
end)]

    project_path
    |> Path.join("mix.exs")
    |> File.write!(content)
  end
end
