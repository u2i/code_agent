# CodeAgent

An Elixir library for AI-powered code modifications using Claude Opus 4 through LangChain.

## Features

- 🤖 Natural language code modifications using Claude AI
- 📁 Directory-scoped file operations with sandboxing
- 🔄 Conversation history for context-aware interactions
- 📝 JSON-based operation format for reliable modifications
- 🧪 Comprehensive test suite with unit and integration tests

## Installation

Add `code_agent` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:code_agent, "~> 0.1.0"}
  ]
end
```

## Configuration

Set your Anthropic API key as an environment variable:

```bash
export ANTHROPIC_API_KEY="your-api-key"
```

## Usage

### Basic Setup

```elixir
# Create an agent for a directory
agent = CodeAgent.new(base_dir: "/path/to/your/project")
```

### Execute Code Modifications

```elixir
# Modify code with natural language instructions
{:ok, result, agent} = CodeAgent.execute(agent,
  "Add error handling to all database queries",
  ["lib/my_app/repo", "lib/my_app/queries.ex"]  # Reference files/dirs
)

# Result includes:
# - analysis: Claude's understanding of the task
# - operations: List of file modifications performed
# - summary: Human-readable summary
# - questions: Any clarifying questions
```

### Ask Questions About Code

```elixir
# Analyze code without modifications
{:ok, answer, agent} = CodeAgent.ask(agent,
  "What patterns are used in the authentication system?",
  ["lib/my_app/auth/"]
)
```

### Conversation Context

The agent maintains conversation history between calls:

```elixir
# First, analyze the code
{:ok, _, agent} = CodeAgent.ask(agent,
  "What does this module do?",
  ["lib/calculator.ex"]
)

# Then ask a follow-up question
{:ok, response, agent} = CodeAgent.ask(agent,
  "How could we improve its performance?",
  []  # No need to re-specify files
)
```

## Operation Format

The library uses a JSON format for modifications:

```json
{
  "operations": [
    {
      "type": "edit",
      "file": "lib/example.ex",
      "find": "old_function()",
      "replace": "new_function()"
    },
    {
      "type": "create",
      "file": "lib/new_file.ex",
      "content": "defmodule NewFile do\n  # content\nend"
    }
  ]
}
```

## Testing

```bash
# Run unit tests only
mix test

# Run all tests including Claude API integration tests
ANTHROPIC_API_KEY=your-key mix test --include integration
```

## Safety Features

- All file operations are sandboxed to the specified base directory
- Path traversal attempts are blocked
- File modifications use exact string matching to prevent unintended changes

## Dependencies

- [LangChain](https://hex.pm/packages/langchain) - LLM framework
- [Plug Cowboy](https://hex.pm/packages/plug_cowboy) - HTTP server (optional)
- [Jason](https://hex.pm/packages/jason) - JSON parser

## License

This project is licensed under the MIT License - see the LICENSE file for details.

