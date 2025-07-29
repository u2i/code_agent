defmodule CodeAgentTest do
  use ExUnit.Case
  
  @test_dir Path.join(System.tmp_dir!(), "code_agent_test_#{:erlang.system_time()}")
  
  setup do
    # Create test directory structure
    File.mkdir_p!(Path.join(@test_dir, "lib"))
    File.mkdir_p!(Path.join(@test_dir, "test"))
    
    # Create sample files
    File.write!(Path.join(@test_dir, "lib/calculator.ex"), """
    defmodule Calculator do
      def add(a, b) do
        a + b
      end
      
      def subtract(a, b) do
        a - b
      end
      
      def multiply(a, b) do
        a * b
      end
    end
    """)
    
    File.write!(Path.join(@test_dir, "lib/user.ex"), """
    defmodule User do
      defstruct [:name, :email, :age]
      
      def new(name, email, age) do
        %User{name: name, email: email, age: age}
      end
      
      def adult?(user) do
        user.age >= 18
      end
    end
    """)
    
    File.write!(Path.join(@test_dir, "test/calculator_test.exs"), """
    defmodule CalculatorTest do
      use ExUnit.Case
      
      test "adds two numbers" do
        assert Calculator.add(1, 2) == 3
      end
    end
    """)
    
    on_exit(fn ->
      File.rm_rf!(@test_dir)
    end)
    
    {:ok, test_dir: @test_dir}
  end
  
  describe "new/1" do
    test "creates an agent with base directory" do
      agent = CodeAgent.new(base_dir: @test_dir)
      assert %CodeAgent.Agent{base_dir: base_dir} = agent
      assert base_dir == Path.expand(@test_dir)
    end
    
    test "requires base_dir option" do
      assert_raise KeyError, fn ->
        CodeAgent.new([])
      end
    end
  end
  
  describe "ask/3" do
    setup %{test_dir: test_dir} do
      agent = CodeAgent.new(base_dir: test_dir)
      {:ok, agent: agent}
    end
    
    @tag :integration
    test "answers questions about code", %{agent: agent} do
      {:ok, response, _updated_agent} = CodeAgent.ask(
        agent,
        "What functions are available in the Calculator module?",
        ["lib/calculator.ex"]
      )
      
      assert response =~ "add" or response =~ "Add"
      assert response =~ "subtract" or response =~ "Subtract"
      assert response =~ "multiply" or response =~ "Multiply"
    end
    
    @tag :integration
    test "can analyze multiple files", %{agent: agent} do
      {:ok, response, _updated_agent} = CodeAgent.ask(
        agent,
        "What modules are defined in this project?",
        ["lib/"]
      )
      
      assert response =~ "Calculator"
      assert response =~ "User"
    end
  end
  
  describe "execute/3" do
    setup %{test_dir: test_dir} do
      agent = CodeAgent.new(base_dir: test_dir)
      {:ok, agent: agent}
    end
    
    @tag :integration
    test "adds documentation to functions", %{agent: agent} do
      {:ok, result, _updated_agent} = CodeAgent.execute(
        agent,
        "Add @doc documentation to the add function in Calculator module",
        ["lib/calculator.ex"]
      )
      
      # Check that operations were performed
      assert %{"operations" => operations} = result
      assert length(operations) > 0
      
      # Verify the file was modified
      {:ok, content} = File.read(Path.join(@test_dir, "lib/calculator.ex"))
      assert content =~ "@doc"
    end
    
    @tag :integration
    test "creates new files", %{agent: agent} do
      {:ok, result, _updated_agent} = CodeAgent.execute(
        agent,
        "Create a new file lib/helper.ex with a module called Helper that has a function hello/0 that returns :world",
        []
      )
      
      # Check that operations were performed
      assert %{"operations" => operations} = result
      assert length(operations) > 0
      
      # Check if file was created through operations
      created_operation = Enum.find(operations, & &1["type"] == "create")
      assert created_operation != nil, "Expected a create operation"
      
      # Verify the file exists
      file_path = Path.join(@test_dir, created_operation["file"])
      assert File.exists?(file_path), "File #{created_operation["file"]} was not created"
      
      # Verify content
      {:ok, content} = File.read(file_path)
      assert content =~ "defmodule Helper"
      assert content =~ "def hello"
      assert content =~ ":world"
    end
    
    @tag :integration
    test "modifies existing code based on patterns", %{agent: agent} do
      {:ok, _result, _updated_agent} = CodeAgent.execute(
        agent,
        "Add a divide function to the Calculator module that handles division by zero",
        ["lib/calculator.ex"]
      )
      
      # Verify the file was modified
      {:ok, content} = File.read(Path.join(@test_dir, "lib/calculator.ex"))
      assert content =~ "def divide"
      assert content =~ "0" # Should handle division by zero
    end
  end
  
  describe "conversation history" do
    setup %{test_dir: test_dir} do
      agent = CodeAgent.new(base_dir: test_dir)
      {:ok, agent: agent}
    end
    
    @tag :integration
    test "maintains context between calls", %{agent: agent} do
      # First ask about the code
      {:ok, _, agent} = CodeAgent.ask(
        agent,
        "What does the Calculator module do?",
        ["lib/calculator.ex"]
      )
      
      # Then ask a follow-up without re-providing context
      {:ok, response, _} = CodeAgent.ask(
        agent,
        "What would be a good function to add to it?",
        []
      )
      
      # Response should show understanding of previous context
      assert response =~ "divide" or response =~ "Division" or 
             response =~ "power" or response =~ "Power" or
             response =~ "square" or response =~ "Square"
    end
  end
end
