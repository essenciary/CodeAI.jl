module CodeAI

import DotEnv
import HTTP
import JSON3
import OpenAI
import Markdown
using Logging

include("Prompts.jl")
using .Prompts

const API_VERSION = "v1"
const API_URL = "https://api.openai.com/$API_VERSION"

const ANS = Ref("")
const LANG = Ref("Julia")
const OPENAI_MODEL = "gpt-4"

Base.@kwdef mutable struct ModelSettings
  model::String = get(ENV, "OPENAI_MODEL", OPENAI_MODEL)
  temperature::Float64 = 0.0
  top_p::Float64 = 1.0
  frequency_penalty::Float64 = 0.0
  presence_penalty::Float64 = 0.0
  max_tokens::Int = 2048
  n::Int = 1
  stream::Bool = false
  stop::Union{String, Nothing} = nothing
end


"""
# Configuration

Mutable struct used for setting up the OpenAI basic configuration for the API access. If the API key is not
set, the package will try to read the API key from the environment variable OPENAI_API_KEY. If the organization is not set,
the package will try to read the organization from the environment variable OPENAI_ORGANIZATION.

Fields:
* api_key::String # OpenAI API key.
* organization::String # OpenAI organization
"""
Base.@kwdef mutable struct Configuration
  api_key::Union{String, Nothing} = get(ENV, "OPENAI_API_KEY", nothing)
  organization::Union{String, Nothing} = get(ENV, "OPENAI_ORGANIZATION", nothing)
  defaults::ModelSettings = ModelSettings()
end


function __init__()
  # Load the environment variables from the .env file
  # DotEnv.load!() # wait for compatibility of DotEnv with Julia 1.6
  DotEnv.config()
end


function nt(obj::T) where T
  fields = fieldnames(T)
  values = [getfield(obj, f) for f in fields]

  return NamedTuple{fields, Tuple{typeof.(values)...}}(values)
end


"""
# models

Returns a list of models available to the authenticated user.
"""
function models(config::Configuration; kwargs...)
  r = OpenAI.list_models(config.api_key; kwargs...)
  r.status != 200 && error("Error retrieving models: $(response.status)")

  return r.response["data"]
end


"""
# model

Returns the model information for the given model.
"""
function model(config::Configuration, model::String; kwargs...)
  r = OpenAI.retrieve_model(config.api_key, model; kwargs...)
  r.status != 200 && error("Error retrieving model: $(response.status)")

  return r.response
end


"""
# parseresponse

Parses the given response and returns the corresponding code -- or throws an error.
"""
function parseresponse(r)
  r.status != 200 && error("Error generating code with OpenAI")

  json_response = ""
  g = try
    # Regular expression pattern
    pattern = Regex("$(Prompts.BOR)(.*)$(Prompts.EOR)", "s")
    input_string = r.response.choices[begin][:message][:content]

    # Extract the matched substring
    match_result = match(pattern, input_string)

    # Check if there is a match
    if match_result !== nothing
      json_response = match_result.captures[1] |> strip |> String
      json_response = replace(json_response, "\n" => "\\n")
      json_response = replace(json_response, "\\n" => "\\n")
      json_response |> JSON3.read
    else
      json_response = replace(input_string, Prompts.BOR => "")
      json_response = replace(input_string, Prompts.EOR => "")
      json_response = replace(input_string, "\n" => "\\n")
      json_response = replace(input_string, "\n" => "\\n")
      json_response |> JSON3.read
    end
  catch e
    @error "Error parsing response: $(r.response.choices[begin][:message][:content])"
    rethrow(e)
  end

  !isempty(g["r"]["e"]) && error("Error generating code. This error was received from the AI model: \n$(g["r"]["e"])\n")

  return ANS[] = g["r"]["c"]
end


"""
# code

Generates a snippet of code based on the given prompt.
"""
function code(config::Configuration, prompt::String;  lang = "Julia",
                                                      model = config.defaults.model,
                                                      implementation_only = false,
                                                      system_prompt = Prompts.system(lang; fn = !implementation_only),
                                                      kwargs...
)
  isempty(kwargs) && (kwargs = nt(config.defaults))

  messages = [
    Dict("role" => "system", "content" => system_prompt),
    Dict("role" => "user", "content" => prompt)
  ]

  r = OpenAI.create_chat(config.api_key, model, messages; kwargs...)
  code = parseresponse(r)
  LANG[] = lang

  return code
end


"""
# code

Returns last generated code
"""
function code()
  return ANS[]
end


"""
# julia

Generates a snippet of Julia code based on the given prompt.
"""
function julia(config::Configuration, prompt::String; model = config.defaults.model,
                                                      lang = "Julia",
                                                      implementation_only = false,
                                                      system_prompt = Prompts.system(lang; fn = !implementation_only) * Prompts.codegen(),
                                                      kwargs = nt(config.defaults)
)
  return code(config, prompt; lang, model, implementation_only, system_prompt, kwargs...)
end


"""
# html

Generates a snippet of HTML code based on the given prompt.
"""
function html(config::Configuration, prompt::String;  model = config.defaults.model,
                                                      lang = "HTML",
                                                      implementation_only = true,
                                                      system_prompt = Prompts.system(lang; fn = !implementation_only),
                                                      kwargs = nt(config.defaults)
)
  return code(config, prompt; lang, model, implementation_only, system_prompt, kwargs...)
end


"""
# refactor

Refactors the given code snippet.
"""

function refactor(config::Configuration, prompt::String;  code = ANS[],
                                                          lang = LANG[],
                                                          model = config.defaults.model,
                                                          implementation_only = true,
                                                          fn = !implementation_only,
                                                          system_prompt = Prompts.system(lang; fn = !implementation_only),
                                                          kwargs = nt(config.defaults)
)
  messages = [
    Dict("role" => "system", "content" => system_prompt),
    Dict("role" => "user", "content" => Prompts.refactor(code, prompt; implementation_only, fn))
  ]

  r = OpenAI.create_chat(config.api_key, model, messages; kwargs...)
  code = parseresponse(r)
  LANG[] = lang

  return code
end


"""
# explain

Explains the given code snippet.
"""

function explain(config::Configuration, prompt::String = "";  code = ANS[],
                                                              lang = LANG[],
                                                              model = config.defaults.model,
                                                              system_prompt = Prompts.system(lang; fn = false),
                                                              kwargs = nt(config.defaults)
)
  messages = [
    Dict("role" => "system", "content" => system_prompt),
    Dict("role" => "user", "content" => Prompts.explain(code, prompt))
  ]

  return OpenAI.create_chat(config.api_key, model, messages; kwargs...) |> parseresponse
end


function help(config::Configuration, prompt::String; role::String = "", model = config.defaults.model, kwargs = nt(config.defaults))
  messages = [
    Dict("role" => "system", "content" => role),
    Dict("role" => "user", "content" => prompt)
  ]

  r = OpenAI.create_chat(config.api_key, model, messages; kwargs...)
  r.status != 200 && error("Error asking for help: $(response.status)")

  return r.response.choices[begin][:message][:content]
end


function show(code::String; lang = "julia")
  code = """
  ```$lang
  $code
  ```
  """

  Markdown.parse(code)
end

end
