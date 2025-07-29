defmodule CodeAgent.FileSystemTest do
  use ExUnit.Case
  alias CodeAgent.FileSystem
  
  @test_dir Path.join(System.tmp_dir!(), "file_system_test_#{:erlang.system_time()}")
  
  setup do
    File.mkdir_p!(@test_dir)
    
    on_exit(fn ->
      File.rm_rf!(@test_dir)
    end)
    
    {:ok, test_dir: @test_dir}
  end
  
  describe "list_files/2" do
    test "lists files recursively", %{test_dir: test_dir} do
      # Create test structure
      File.mkdir_p!(Path.join(test_dir, "lib/sub"))
      File.write!(Path.join(test_dir, "lib/file1.ex"), "content1")
      File.write!(Path.join(test_dir, "lib/file2.ex"), "content2")
      File.write!(Path.join(test_dir, "lib/sub/file3.ex"), "content3")
      
      {:ok, files} = FileSystem.list_files(test_dir, "lib")
      
      assert "lib/file1.ex" in files
      assert "lib/file2.ex" in files
      assert "lib/sub/file3.ex" in files
    end
    
    test "returns error for non-existent directory", %{test_dir: test_dir} do
      assert {:error, "Directory does not exist"} = FileSystem.list_files(test_dir, "nonexistent")
    end
  end
  
  describe "read_file/2" do
    test "reads file content", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "test.txt"), "Hello, World!")
      
      assert {:ok, "Hello, World!"} = FileSystem.read_file(test_dir, "test.txt")
    end
    
    test "prevents path traversal", %{test_dir: test_dir} do
      assert {:error, "Path traversal detected - access denied"} = 
        FileSystem.read_file(test_dir, "../../../etc/passwd")
    end
  end
  
  describe "write_file/3" do
    test "writes file content", %{test_dir: test_dir} do
      assert :ok = FileSystem.write_file(test_dir, "new.txt", "New content")
      assert {:ok, "New content"} = File.read(Path.join(test_dir, "new.txt"))
    end
    
    test "creates directories if needed", %{test_dir: test_dir} do
      assert :ok = FileSystem.write_file(test_dir, "deep/nested/file.txt", "content")
      assert File.exists?(Path.join(test_dir, "deep/nested/file.txt"))
    end
    
    test "prevents path traversal", %{test_dir: test_dir} do
      assert {:error, "Path traversal detected - access denied"} = 
        FileSystem.write_file(test_dir, "../outside.txt", "content")
    end
  end
  
  describe "update_file/4" do
    test "updates file content", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "update.txt"), "Hello, World!")
      
      assert :ok = FileSystem.update_file(test_dir, "update.txt", "World", "Elixir")
      assert {:ok, "Hello, Elixir!"} = File.read(Path.join(test_dir, "update.txt"))
    end
    
    test "returns error if file doesn't exist", %{test_dir: test_dir} do
      assert {:error, _} = FileSystem.update_file(test_dir, "nonexistent.txt", "old", "new")
    end
  end
end