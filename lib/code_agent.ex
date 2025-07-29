defmodule CodeAgent do
  @moduledoc """
  A code modification agent that uses Claude AI to intelligently modify files.
  
  ## Usage
  
      # Create an agent for a directory
      agent = CodeAgent.new(base_dir: "/path/to/project")
      
      # Execute modifications with reference files
      {:ok, result, agent} = CodeAgent.execute(agent, 
        "Add error handling to all functions",
        ["lib/", "config/config.exs"]
      )
      
      # Ask questions about the codebase
      {:ok, answer, agent} = CodeAgent.ask(agent,
        "What's the purpose of the GenServer in this module?",
        ["lib/my_app/server.ex"]
      )
  """
  
  alias CodeAgent.Agent
  
  @doc """
  Creates a new code agent for the specified directory.
  
  ## Options
    - `:base_dir` - The base directory to operate in (required)
    
  ## Examples
  
      agent = CodeAgent.new(base_dir: "./my_project")
  """
  defdelegate new(opts), to: Agent
  
  @doc """
  Executes code modifications based on instructions.
  
  ## Parameters
    - `agent` - The agent instance
    - `instructions` - Natural language instructions for modifications
    - `reference_paths` - List of files/directories to include as context
    
  ## Returns
    - `{:ok, result, updated_agent}` - Success with results and updated agent
    - `{:error, reason}` - Error with reason
    
  ## Result Structure
    - `:analysis` - Claude's analysis of the task
    - `:operations` - List of operations performed
    - `:questions` - Any clarifying questions
    - `:summary` - Human-readable summary
    - `:applied_operations` - Results of file operations
    
  ## Examples
  
      {:ok, result, agent} = CodeAgent.execute(agent,
        "Refactor all database queries to use Ecto",
        ["lib/my_app/", "test/"]
      )
  """
  defdelegate execute(agent, instructions, reference_paths \\ []), to: Agent
  
  @doc """
  Ask questions about the codebase without making modifications.
  
  ## Parameters
    - `agent` - The agent instance  
    - `question` - Your question about the code
    - `reference_paths` - List of files/directories to include as context
    
  ## Returns
    - `{:ok, answer, updated_agent}` - Success with answer and updated agent
    - `{:error, reason}` - Error with reason
    
  ## Examples
  
      {:ok, answer, agent} = CodeAgent.ask(agent,
        "How does the authentication system work?",
        ["lib/my_app/auth/", "lib/my_app_web/controllers/session_controller.ex"]
      )
  """
  defdelegate ask(agent, question, reference_paths \\ []), to: Agent
end
