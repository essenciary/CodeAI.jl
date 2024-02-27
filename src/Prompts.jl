module Prompts


const PROMPT = Ref("")
const EOR = "~~end~~"
const BOR = "~~start~~"

function codegen()
  return """
    \n
    THIS IS IMPORTANT: Respond only with code in the requested language! To add any other information, use code comments.
    If you don't know the answer or the request makes no sense, leave the code block empty and add a comment with your error message.
    Your response should be a valid code snippet in the requested language. It will be parsed as such so make sure it's valid code.
    \n
  """
end


function system(lang = "Julia"; fn = true, fname::Union{Nothing, String} = nothing, dc = fn)
  prompt = """
    \n
    You are an expert $lang developer and generate high quality $lang code.
    You always answer with JSON in the requested format.
    Send only JSON code, as requested, never anything else!

    You answer only with JSON, in the following format: "
    {"r":{"c":"<response>","e":"<error>"}}
    ".

    At the beginning of your response, add the following string: $BOR.
    At the end of your response, add the following string: $EOR.

    If you don't know the answer, leave `c` empty and set `e` to your error message.
    Escape single quotes with backslash in your response.

    Never ever answer with anything else but the JSON response. If you do, your response will be rejected.
    \n
  """

  fn && (prompt *= """
    Wrap code in a function.
  """)

  if fname !== nothing
    prompt *= "The function name is $fname."
  elseif fn
    prompt *= "Pick function name to reflect functionality."
  end

  if dc
    prompt *= """
      Document the function by adding a doc comment. Do not wrap the doc string in backticks.
    """

    if lowercase(lang) == "julia"
      prompt *= """
        In Julia doc comments are written above the function definition and wrapped in triple double quotes.
      """
    end
  end

  lowercase(lang) == "julia" && (prompt *= """
    \n
    Use as much as possible Julia's built-in functions and libraries and the most popular packages.
    Use the most popular style guide and best practices and idiomatic Julia code.
    Add type annotations to function arguments and return values.
    \n
  """)

  lowercase(lang) == "html" && (prompt *= """
    Don't generate the whole HTML document, only the requested HTML snippet.
  """)

  PROMPT[] = prompt

  return prompt
end


function refactor(code::String, prompt::String; implementation_only = true, fn = true)
  prompt = """
    Refactor the following code:
    ```
    $code
    ```

    Update code to $prompt.

  """

  implementation_only && fn && (prompt *= """
    You can only change the implementation of the function. Do not change the function name.
  """)

  return prompt
end


function explain(code::String, prompt::String = "")
  prompt = """
    Explain the following code:
    ```
    $code
    ```

    $prompt
  """

  PROMPT[] = prompt

  return prompt
end


function debug(code::String, error::String, prompt::String = "")
  prompt = """
    Debug the following code by replacing the current code with your fixed code:
    ```
    $code
    ```

    The code throws the following error:
    ```
    $error
    ```

    $prompt
  """

  PROMPT[] = prompt

  return prompt
end


function prompt()
  return PROMPT[]
end

end