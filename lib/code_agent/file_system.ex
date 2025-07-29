defmodule CodeAgent.FileSystem do
  @moduledoc """
  Handles file system operations within a sandboxed directory.
  """

  @doc """
  Lists all files in the given directory recursively.
  """
  def list_files(base_dir, subdir \\ "") do
    full_path = Path.join(base_dir, subdir)
    
    if File.dir?(full_path) do
      {:ok, do_list_files(full_path, base_dir)}
    else
      {:error, "Directory does not exist"}
    end
  end

  defp do_list_files(path, base_dir) do
    path
    |> File.ls!()
    |> Enum.flat_map(fn file ->
      full_path = Path.join(path, file)
      relative_path = Path.relative_to(full_path, base_dir)
      
      if File.dir?(full_path) do
        do_list_files(full_path, base_dir)
      else
        [relative_path]
      end
    end)
  end

  @doc """
  Reads a file content within the sandboxed directory.
  """
  def read_file(base_dir, file_path) do
    full_path = safe_join(base_dir, file_path)
    
    case validate_path(base_dir, full_path) do
      :ok -> File.read(full_path)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Writes content to a file within the sandboxed directory.
  """
  def write_file(base_dir, file_path, content) do
    full_path = safe_join(base_dir, file_path)
    
    case validate_path(base_dir, full_path) do
      :ok ->
        File.mkdir_p!(Path.dirname(full_path))
        File.write(full_path, content)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates a file by replacing old content with new content.
  """
  def update_file(base_dir, file_path, old_content, new_content) do
    with {:ok, current} <- read_file(base_dir, file_path) do
      updated = String.replace(current, old_content, new_content)
      write_file(base_dir, file_path, updated)
    end
  end

  # Safely join paths and normalize
  defp safe_join(base_dir, file_path) do
    base_dir
    |> Path.join(file_path)
    |> Path.expand()
  end

  # Validate that the path is within the allowed base directory
  defp validate_path(base_dir, full_path) do
    expanded_base = Path.expand(base_dir)
    expanded_full = Path.expand(full_path)
    
    if String.starts_with?(expanded_full, expanded_base) do
      :ok
    else
      {:error, "Path traversal detected - access denied"}
    end
  end
end