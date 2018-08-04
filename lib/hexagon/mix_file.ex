defmodule Hexagon.MixFile do
  def gen(project_path, package_name, package_path) do
    content = [~s(
defmodule Petridish.MixProject do
use Mix.Project

def project do
[
  app: :petridish,
  version: "0.1.0",
  deps: [{:), package_name, ~s(, path: "), package_path, ~s("}]
]
end
end)]

    Path.join(project_path, "mix.exs")
    |> File.write!(content)
  end
end
