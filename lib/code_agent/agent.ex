defmodule CodeAgent.Agent do
  @moduledoc """
  Main agent API for code modifications.
  """
  
  alias CodeAgent.{FileSystem, ClaudeClient}
  
  defstruct [:base_dir, :conversation_history]
  
  @doc """
  Creates a new agent instance for a specific directory.
  
  ## Options
    - `:base_dir` - The base directory to operate in (required)
  """
  def new(opts) do
    base_dir = Keyword.fetch!(opts, :base_dir)
    
    %__MODULE__{
      base_dir: Path.expand(base_dir),
      conversation_history: []
    }
  end
  
  @doc """
  Executes instructions with reference files/directories.
  
  ## Parameters
    - `agent` - The agent instance
    - `instructions` - String instructions for what to do
    - `reference_paths` - List of file paths or directory paths to include as context
    
  ## Returns
    - `{:ok, result, updated_agent}` - Success with result map and updated agent
    - `{:error, reason}` - Error with reason
  """
  def execute(agent, instructions, reference_paths \\ []) do
    with {:ok, all_files} <- load_all_files(agent.base_dir, reference_paths),
         {:ok, response} <- send_to_claude(agent, instructions, all_files),
         {:ok, parsed} <- parse_response(response),
         {:ok, result} <- apply_operations(agent, parsed) do
      
      # Update conversation history
      updated_agent = update_history(agent, instructions, result)
      
      {:ok, result, updated_agent}
    end
  end
  
  @doc """
  Ask a question without making modifications.
  """
  def ask(agent, question, reference_paths \\ []) do
    with {:ok, all_files} <- load_all_files(agent.base_dir, reference_paths) do
      prompt = build_question_prompt(question, all_files)
      
      case ClaudeClient.chat(prompt, agent.conversation_history) do
        {:ok, response} ->
          updated_agent = update_history(agent, question, %{response: response})
          {:ok, response, updated_agent}
        {:error, reason} ->
          {:error, reason}
      end
    end
  end
  
  # Private functions
  
  defp load_all_files(base_dir, paths) do
    files = Enum.flat_map(paths, fn path ->
      full_path = Path.join(base_dir, path)
      
      cond do
        File.dir?(full_path) ->
          # Load all files from directory
          load_directory_files(base_dir, path)
          
        File.regular?(full_path) ->
          # Load single file
          case FileSystem.read_file(base_dir, path) do
            {:ok, content} -> [{path, content}]
            {:error, _} -> []
          end
          
        true ->
          []
      end
    end)
    
    {:ok, files}
  end
  
  defp load_directory_files(base_dir, dir_path) do
    case FileSystem.list_files(base_dir, dir_path) do
      {:ok, file_list} ->
        Enum.flat_map(file_list, fn file_path ->
          case FileSystem.read_file(base_dir, file_path) do
            {:ok, content} -> [{file_path, content}]
            {:error, _} -> []
          end
        end)
      {:error, _} ->
        []
    end
  end
  
  defp send_to_claude(agent, instructions, files) do
    prompt = build_modification_prompt(instructions, files, agent.base_dir)
    ClaudeClient.chat(prompt, agent.conversation_history)
  end
  
  defp build_modification_prompt(instructions, files, base_dir) do
    files_section = if Enum.empty?(files) do
      "No reference files provided."
    else
      """
      ## Available Files:
      #{Enum.map_join(files, "\n\n", fn {path, content} ->
        "### File: #{path}\n```\n#{content}\n```"
      end)}
      """
    end
    
    """
    You are a code modification assistant with access to modify files in: #{base_dir}
    
    #{files_section}
    
    ## Instructions:
    #{instructions}
    
    Based on the files provided and the instructions, analyze what needs to be done and provide your response in this JSON format:
    
    ```json
    {
      "analysis": "Your detailed analysis of what needs to be done",
      "operations": [
        {
          "type": "edit",
          "file": "path/to/file.ex",
          "find": "exact content to find including whitespace",
          "replace": "new content to replace with"
        },
        {
          "type": "create",
          "file": "path/to/new/file.ex",
          "content": "full file content here"
        }
      ],
      "questions": ["Any clarifying questions if you need more information"],
      "summary": "A brief human-readable summary of what you did"
    }
    ```
    
    Important notes:
    - For "edit" operations: match the EXACT text including all whitespace and newlines
    - For "create" operations: provide the complete file content
    - Multiple edit operations on the same file will be applied sequentially
    - All file paths should be relative to the base directory
    - If you have questions or need clarification, include them in the "questions" array
    - Always include a brief summary of your changes
    """
  end
  
  defp build_question_prompt(question, files) do
    files_section = if Enum.empty?(files) do
      ""
    else
      """
      ## Context Files:
      #{Enum.map_join(files, "\n\n", fn {path, content} ->
        "### File: #{path}\n```\n#{content}\n```"
      end)}
      """
    end
    
    """
    #{files_section}
    
    ## Question:
    #{question}
    
    Please provide a helpful and detailed response based on the files and context provided.
    """
  end
  
  defp parse_response(response) do
    case extract_and_parse_json(response) do
      {:ok, parsed} -> 
        validate_response_format(parsed)
      {:error, _} ->
        # If no JSON found, treat as a simple response
        {:ok, %{
          "summary" => response,
          "operations" => [],
          "questions" => [],
          "analysis" => ""
        }}
    end
  end
  
  defp extract_and_parse_json(text) do
    # Try to extract JSON between ```json and ```
    case Regex.run(~r/```json\s*(.*?)\s*```/s, text) do
      [_, json] -> Jason.decode(json)
      _ -> 
        # Try to parse the whole text as JSON
        Jason.decode(text)
    end
  end
  
  defp validate_response_format(parsed) do
    # Ensure required fields exist with defaults
    validated = %{
      "analysis" => Map.get(parsed, "analysis", ""),
      "operations" => Map.get(parsed, "operations", []),
      "questions" => Map.get(parsed, "questions", []),
      "summary" => Map.get(parsed, "summary", "")
    }
    
    # Validate operations format
    case validate_operations(validated["operations"]) do
      :ok -> {:ok, validated}
      {:error, reason} -> {:error, {:invalid_operations, reason}}
    end
  end
  
  defp validate_operations(operations) do
    Enum.reduce_while(operations, :ok, fn op, _acc ->
      case validate_operation(op) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
  
  defp validate_operation(%{"type" => "edit"} = op) do
    required = ["type", "file", "find", "replace"]
    if Enum.all?(required, &Map.has_key?(op, &1)) do
      :ok
    else
      {:error, "Edit operation missing required fields"}
    end
  end
  
  defp validate_operation(%{"type" => "create"} = op) do
    required = ["type", "file", "content"]
    if Enum.all?(required, &Map.has_key?(op, &1)) do
      :ok
    else
      {:error, "Create operation missing required fields"}
    end
  end
  
  defp validate_operation(_), do: {:error, "Unknown operation type"}
  
  defp apply_operations(agent, parsed_response) do
    operations = Map.get(parsed_response, "operations", [])
    
    # Group operations by file for efficiency
    grouped_ops = Enum.group_by(operations, & &1["file"])
    
    # Apply operations
    results = Enum.map(grouped_ops, fn {file, ops} ->
      apply_file_operations(agent.base_dir, file, ops)
    end)
    
    errors = Enum.filter(results, &match?({:error, _}, &1))
    
    if Enum.empty?(errors) do
      {:ok, Map.put(parsed_response, :applied_operations, results)}
    else
      {:error, {:operation_errors, errors}}
    end
  end
  
  defp apply_file_operations(base_dir, file_path, operations) do
    # Separate create and edit operations
    {creates, edits} = Enum.split_with(operations, & &1["type"] == "create")
    
    # Handle create operations (should only be one per file)
    create_result = case creates do
      [create_op | _] ->
        FileSystem.write_file(base_dir, file_path, create_op["content"])
      [] ->
        :no_create
    end
    
    # Handle edit operations
    edit_result = if Enum.empty?(edits) do
      :no_edits
    else
      apply_edit_operations(base_dir, file_path, edits)
    end
    
    case {create_result, edit_result} do
      {:no_create, :no_edits} -> {:ok, {file_path, :no_operations}}
      {{:error, _} = err, _} -> err
      {_, {:error, _} = err} -> err
      _ -> {:ok, {file_path, :success}}
    end
  end
  
  defp apply_edit_operations(base_dir, file_path, edits) do
    # Read current content
    case FileSystem.read_file(base_dir, file_path) do
      {:ok, content} ->
        # Apply edits sequentially
        final_content = Enum.reduce(edits, content, fn edit, acc ->
          String.replace(acc, edit["find"], edit["replace"])
        end)
        
        # Write back
        FileSystem.write_file(base_dir, file_path, final_content)
        
      {:error, reason} ->
        {:error, {:file_not_found, file_path, reason}}
    end
  end
  
  defp update_history(agent, user_input, result) do
    response_text = Map.get(result, "summary", Map.get(result, :response, ""))
    
    history_entry = [
      {:user, user_input},
      {:assistant, response_text}
    ]
    
    %{agent | conversation_history: agent.conversation_history ++ history_entry}
  end
end