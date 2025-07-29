defmodule CodeAgent.ConfigAgent do
  @moduledoc """
  Specialized agent for idempotent configuration file management.
  Designed to ensure configuration files match specifications regardless of current state.
  """
  
  alias CodeAgent.{Agent, FileSystem}
  
  @doc """
  Ensures configuration files match the provided specification.
  
  ## Parameters
    - `base_dir` - The base directory to operate in
    - `spec` - Configuration specification map with:
      - `:instructions` - Overall instructions for the configuration
      - `:files` - List of file specifications
      - `:templates` - Map of template name to content (optional)
      
  ## File Specification Format
    Each file in the `:files` list should have:
    - `:path` - Path relative to base_dir
    - `:description` - What this file should contain
    - `:template` - Template name or inline template content (optional)
    - `:format` - File format hint (yaml, json, toml, etc.)
    
  ## Returns
    - `{:ok, results}` - Success with list of file operation results
    - `{:error, reason}` - Error
  """
  def ensure_configuration(base_dir, spec) do
    agent = Agent.new(base_dir: base_dir)
    
    # Process each file specification
    results = Enum.map(spec.files, fn file_spec ->
      ensure_file(agent, file_spec, spec[:templates] || %{})
    end)
    
    # Check for any errors
    errors = Enum.filter(results, &match?({:error, _}, &1))
    
    if Enum.empty?(errors) do
      {:ok, results}
    else
      {:error, {:failed_files, errors}}
    end
  end
  
  @doc """
  Checks if all files are compliant with the specification.
  Returns a report of compliance status.
  """
  def check_compliance(base_dir, spec) do
    agent = Agent.new(base_dir: base_dir)
    
    compliance_results = Enum.map(spec.files, fn file_spec ->
      check_file_compliance(agent, file_spec, spec[:templates] || %{})
    end)
    
    %{
      compliant: Enum.all?(compliance_results, & &1.compliant),
      files: compliance_results
    }
  end
  
  # Private functions
  
  defp ensure_file(agent, file_spec, templates) do
    template_content = resolve_template(file_spec[:template], templates)
    current_content = read_current_file(agent.base_dir, file_spec.path)
    
    prompt = build_idempotent_prompt(file_spec, template_content, current_content)
    
    case Agent.execute(agent, prompt, []) do
      {:ok, result, _} ->
        {:ok, %{
          path: file_spec.path,
          operations: result["operations"],
          summary: result["summary"]
        }}
      {:error, reason} ->
        {:error, {file_spec.path, reason}}
    end
  end
  
  defp check_file_compliance(agent, file_spec, templates) do
    template_content = resolve_template(file_spec[:template], templates)
    current_content = read_current_file(agent.base_dir, file_spec.path)
    
    if current_content == :not_found do
      %{
        path: file_spec.path,
        compliant: false,
        reason: "File does not exist"
      }
    else
      prompt = build_compliance_check_prompt(file_spec, template_content, current_content)
      
      case Agent.ask(agent, prompt, []) do
        {:ok, response, _} ->
          parse_compliance_response(file_spec.path, response)
        {:error, _} ->
          %{
            path: file_spec.path,
            compliant: false,
            reason: "Failed to check compliance"
          }
      end
    end
  end
  
  defp resolve_template(nil, _), do: nil
  defp resolve_template(template_ref, templates) when is_binary(template_ref) do
    # Check if it's a template name reference
    Map.get(templates, template_ref, template_ref)
  end
  defp resolve_template(template, _), do: template
  
  defp read_current_file(base_dir, path) do
    case FileSystem.read_file(base_dir, path) do
      {:ok, content} -> content
      {:error, _} -> :not_found
    end
  end
  
  defp build_idempotent_prompt(file_spec, template, current_content) do
    """
    You are a configuration management agent. Your task is to ensure a configuration file matches specifications EXACTLY.
    
    ## File Specification
    Path: #{file_spec.path}
    Description: #{file_spec.description}
    Format: #{file_spec[:format] || "auto-detect"}
    
    #{template_section(template)}
    
    #{current_section(current_content)}
    
    ## Instructions
    1. If the file doesn't exist, create it according to the specification
    2. If the file exists but doesn't match the specification, modify it to match
    3. If the file already matches the specification, do nothing
    4. Ensure the result is idempotent - running this again should produce no changes
    5. Preserve any valid configuration that doesn't conflict with the specification
    6. Use proper formatting for the file type (proper indentation, syntax, etc.)
    
    IMPORTANT: The file must comply with the description and template (if provided).
    Make the minimum necessary changes to achieve compliance.
    """
  end
  
  defp build_compliance_check_prompt(file_spec, template, current_content) do
    """
    Check if the following configuration file is compliant with its specification.
    
    ## File Specification
    Path: #{file_spec.path}
    Description: #{file_spec.description}
    Format: #{file_spec[:format] || "auto-detect"}
    
    #{template_section(template)}
    
    ## Current File Content
    ```
    #{current_content}
    ```
    
    Please analyze if the current file is compliant with the specification.
    Respond with a JSON object:
    {
      "compliant": true/false,
      "reason": "explanation if not compliant",
      "missing": ["list of missing required elements"],
      "incorrect": ["list of incorrect elements"]
    }
    """
  end
  
  defp template_section(nil), do: ""
  defp template_section(template) do
    """
    ## Template/Example
    The file should follow this template structure:
    ```
    #{template}
    ```
    """
  end
  
  defp current_section(:not_found) do
    "## Current State\nFile does not exist."
  end
  defp current_section(content) do
    """
    ## Current File Content
    ```
    #{content}
    ```
    """
  end
  
  defp parse_compliance_response(path, response) do
    case Jason.decode(response) do
      {:ok, %{"compliant" => compliant} = data} ->
        %{
          path: path,
          compliant: compliant,
          reason: data["reason"],
          missing: data["missing"] || [],
          incorrect: data["incorrect"] || []
        }
      _ ->
        # Fallback: try to determine from response text
        %{
          path: path,
          compliant: String.contains?(response, "compliant") && !String.contains?(response, "not compliant"),
          reason: response
        }
    end
  end
end