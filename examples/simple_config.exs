#!/usr/bin/env elixir

# Simple Configuration Example
# 
# Usage:
#   elixir simple_config.exs

Mix.install([
  {:code_agent, github: "u2i/code_agent"}
])

alias CodeAgent.ConfigAgent

# Define your configuration specification
config_spec = %{
  instructions: "Set up a basic Elixir project configuration",
  
  files: [
    %{
      path: ".formatter.exs",
      description: "Elixir formatter configuration with 100 character line length",
      template: """
      [
        line_length: 100,
        inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
      ]
      """,
      format: "elixir"
    },
    
    %{
      path: ".gitignore", 
      description: "Git ignore file for Elixir projects with standard exclusions",
      template: """
      # The directory Mix will write compiled artifacts to.
      /_build/
      
      # If you run "mix test --cover", coverage assets end up here.
      /cover/
      
      # The directory Mix downloads your dependencies sources to.
      /deps/
      
      # Where 3rd-party dependencies like ExDoc output generated docs.
      /doc/
      
      # Ignore .fetch files in case you like to edit your project deps locally.
      /.fetch
      
      # If the VM crashes, it generates a dump, let's ignore it too.
      erl_crash.dump
      
      # Also ignore archive artifacts (built via "mix archive.build").
      *.ez
      
      # Ignore package tarball (built via "mix hex.build").
      *.tar
      
      # Since we are building assets from assets/, we ignore priv/static.
      /priv/static/
      
      # Environment variables
      .env
      .env.*
      """,
      format: "text"
    },
    
    %{
      path: "config/config.exs",
      description: "Main configuration file that imports environment-specific configs",
      template: """
      import Config
      
      # Import environment specific config
      import_config "\#{config_env()}.exs"
      """,
      format: "elixir"
    }
  ]
}

# Ensure configuration
case ConfigAgent.ensure_configuration(".", config_spec) do
  {:ok, results} ->
    IO.puts("✅ Configuration applied successfully!")
    
    Enum.each(results, fn {:ok, result} ->
      IO.puts("  • #{result.path}")
    end)
    
  {:error, reason} ->
    IO.puts("❌ Error: #{inspect(reason)}")
end