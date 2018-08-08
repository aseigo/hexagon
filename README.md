# Hexagon

Hexagon is a tool to check the build status of packages on [hex.pm](https://hex.pm),
the BEAM package hosting webservice. The motivation is to be able to track the build
health of packages in the Erlang/Exlixir ecosystem.

## Building

Building quite straight-forward, assuming you have Elixir installed:

    mix deps.get
    mix compile

## Usage

Currently, only interactive usage via `iex` (the Elixir REPL) is supported. To get
going do:

    iex -S mix

You should now be presented with the `iex` prompt with Hexagon loaded and ready for use.

Hexagon supports a number of operation modes:

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

## Output

The check functions all output their progress and results to a logfile in JSON format. These
logfiles are prepended by a timestamp and one is generated for each check performed.

The path to the logfile is printed to console, and if you wish to track progress of the
run, tail the file (or process it as you wish) as it is written to incrementally as
the checks are done.

## Configuration

Hexagon configuration is found in `config/config.exs` and supports the following options:

* `package_path`: string to the location where the local package cache should be kept. This
location must be readable and writable by the user Hexagon is run as.
* `log_path`: string to the location where logfiles should be stored. This location must
also be readable and writable by the user Hexagon is run as.
* `parallel_builds`: the number of builds to perform in parallel.


