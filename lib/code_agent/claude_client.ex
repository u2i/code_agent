defmodule CodeAgent.ClaudeClient do
  @moduledoc """
  Claude API client using LangChain
  """
  
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message
  alias LangChain.Chains.LLMChain

  @doc """
  Creates a new Claude chat model instance
  """
  def create_chat_model(opts \\ []) do
    # Get API key from environment or options
    api_key = Keyword.get(opts, :api_key, System.get_env("ANTHROPIC_API_KEY"))
    
    ChatAnthropic.new!(%{
      model: Keyword.get(opts, :model, "claude-opus-4-20250514"),
      api_key: api_key,
      temperature: Keyword.get(opts, :temperature, 0.3),
      max_tokens: Keyword.get(opts, :max_tokens, 4096)
    })
  end

  @doc """
  Sends a message to Claude and gets a response
  """
  def chat(message, context \\ [], opts \\ []) do
    model = create_chat_model(opts)
    
    messages = build_messages(message, context)
    
    chain = %{llm: model}
    |> LLMChain.new!()
    
    # Add messages to the chain
    chain_with_messages = Enum.reduce(messages, chain, fn msg, acc ->
      LLMChain.add_message(acc, msg)
    end)
    
    case LLMChain.run(chain_with_messages) do
      {:ok, %{last_message: %{content: content}}} -> 
        {:ok, content}
      {:ok, _chain} ->
        {:error, "No response content found"}
      {:error, _chain, reason} -> 
        {:error, reason}
      error ->
        {:error, error}
    end
  end

  @doc """
  Creates a code modification prompt
  """
  def code_modification_prompt(instruction, file_content, file_path) do
    """
    You are a code modification assistant. You have access to modify files in a sandboxed directory.
    
    File: #{file_path}
    Current content:
    ```
    #{file_content}
    ```
    
    User instruction: #{instruction}
    
    Please analyze the code and provide the modifications needed. 
    Return your response in the following JSON format:
    {
      "analysis": "Brief analysis of what needs to be changed",
      "modifications": [
        {
          "type": "replace",
          "old_content": "exact string to replace",
          "new_content": "replacement string"
        }
      ],
      "questions": ["Any clarifying questions if needed"]
    }
    """
  end

  defp build_messages(message, context) do
    system_message = Message.new_system!("""
    You are Claude, a helpful AI assistant specialized in code modifications.
    You can read and modify files within the provided directory.
    Always ensure code quality and follow best practices.
    """)
    
    context_messages = Enum.map(context, fn {role, content} ->
      case role do
        :user -> Message.new_user!(content)
        :assistant -> Message.new_assistant!(content)
      end
    end)
    
    user_message = Message.new_user!(message)
    
    [system_message | context_messages] ++ [user_message]
  end
end