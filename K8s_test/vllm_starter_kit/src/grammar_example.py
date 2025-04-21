#%%
# SPDX-License-Identifier: Apache-2.0

from enum import Enum

from openai import BadRequestError, OpenAI
from pydantic import BaseModel

client = OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="-",
)

#%%
# Guided decoding by Choice (list of possible options)
completion = client.chat.completions.create(
    model="Qwen/Qwen2.5-7B",
    messages=[{
        "role": "user",
        "content": "Classify this sentiment: vLLM is wonderful!"
    }],
    extra_body={"guided_choice": ["positive", "negative"]},
)
print(completion.choices[0].message.content)
 
#%%
# Guided decoding by Regex
prompt = ("Generate an email address for Alan Turing, who works in Enigma."
          "End in .com and new line. Example result:"
          "alan.turing@enigma.com\n")

completion = client.chat.completions.create(
    model="Qwen/Qwen2.5-7B",
    messages=[{
        "role": "user",
        "content": prompt,
    }],
    extra_body={
        "guided_regex": r"\w+@\w+\.com\n",
        "stop": ["\n"]
    },
)
print(completion.choices[0].message.content)

#%%
# Guided decoding by JSON using Pydantic schema
class CarType(str, Enum):
    sedan = "sedan"
    suv = "SUV"
    truck = "Truck"
    coupe = "Coupe"


class CarDescription(BaseModel):
    brand: str
    model: str
    car_type: CarType


json_schema = CarDescription.model_json_schema()

prompt = ("Generate a JSON with the brand, model and car_type of"
          "the most iconic car from the 90's")
completion = client.chat.completions.create(
    model="Qwen/Qwen2.5-7B",
    messages=[{
        "role": "user",
        "content": prompt,
    }],
    extra_body={"guided_json": json_schema},
)
print(completion.choices[0].message.content)

#%%
# Guided decoding by Grammar
wrong_simplified_sql_grammar = r"""
?start: select_statement
?select_statement: "SELECT " column_list " FROM " table_name
?column_list: column_name ("," column_name)*
?table_name: identifier
?column_name: identifier
?identifier: /[a-zA-Z_][a-zA-Z0-9_]*/
"""

prompt = ("Generate an SQL query to show the 'username' and 'email'"
          "from the 'users' table.")
completion = client.chat.completions.create(
    model="Qwen/Qwen2.5-7B",
    messages=[{
        "role": "user",
        "content": prompt,
    }],
    extra_body={
        "guided_grammar": wrong_simplified_sql_grammar
        },
)
print(completion.choices[0].message.content)

#%%
# Extra backend options
prompt = ("Generate an email address for Alan Turing, who works in Enigma."
          "End in .com and new line. Example result:"
          "alan.turing@enigma.com\n")

try:
    # The no-fallback option forces vLLM to use xgrammar, so when it fails
    # you get a 400 with the reason why
    completion = client.chat.completions.create(
        model="Qwen/Qwen2.5-7B",
        messages=[{
            "role": "user",
            "content": prompt,
        }],
        extra_body={
            "guided_regex": r"\w+@\w+\.com\n",
            "stop": ["\n"],
            "guided_decoding_backend": "xgrammar:no-fallback"
        },
    )
except BadRequestError as e:
    print("This error is expected:", e)

# %%
import xgrammar as xgr
from transformers import AutoTokenizer, AutoConfig

import os
os.environ['LD_LIBRARY_PATH'] = '/usr/lib/x86_64-linux-gnu'

model_id = "Qwen/Qwen2.5-7B"
tokenizer = AutoTokenizer.from_pretrained(model_id)
config = AutoConfig.from_pretrained(model_id)
# This can be larger than tokenizer.vocab_size due to paddings
full_vocab_size = config.vocab_size
tokenizer_info = xgr.TokenizerInfo.from_huggingface(tokenizer, vocab_size=full_vocab_size)
compiler = xgr.GrammarCompiler(tokenizer_info, max_threads=8)

ebnf_grammar_str = """root ::= (expr "=" term)+
expr  ::= term ([-+*/] term)*
term  ::= num | "(" expr ")"
num   ::= [0-9]+"""

compiled_grammar = compiler.compile_grammar(ebnf_grammar_str)

print("Compiled grammar:", compiled_grammar)

#%%
import xgrammar as xgr
from transformers import AutoTokenizer, AutoConfig, AutoModelForCausalLM
import torch

import os
os.environ['LD_LIBRARY_PATH'] = '/usr/lib/x86_64-linux-gnu'

model_name = "Qwen/Qwen2.5-7B"
device = "cpu"
model = AutoModelForCausalLM.from_pretrained(
    model_name, torch_dtype=torch.float32, device_map=device
)
tokenizer = AutoTokenizer.from_pretrained(model_name)
config = AutoConfig.from_pretrained(model_name)

messages = [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Introduce yourself in JSON briefly."},
]
texts = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
model_inputs = tokenizer(texts, return_tensors="pt").to(model.device)

tokenizer_info = xgr.TokenizerInfo.from_huggingface(tokenizer, vocab_size=config.vocab_size)
grammar_compiler = xgr.GrammarCompiler(tokenizer_info)
# Grammar string that represents a JSON schema
json_grammar_ebnf_str = r"""
root ::= basic_array | basic_object
basic_any ::= basic_number | basic_string | basic_boolean | basic_null | basic_array | basic_object
basic_integer ::= ("0" | "-"? [1-9] [0-9]*) ".0"?
basic_number ::= ("0" | "-"? [1-9] [0-9]*) ("." [0-9]+)? ([eE] [+-]? [0-9]+)?
basic_string ::= (([\"] basic_string_1 [\"]))
basic_string_1 ::= "" | [^"\\\x00-\x1F] basic_string_1 | "\\" escape basic_string_1
escape ::= ["\\/bfnrt] | "u" [A-Fa-f0-9] [A-Fa-f0-9] [A-Fa-f0-9] [A-Fa-f0-9]
basic_boolean ::= "true" | "false"
basic_null ::= "null"
basic_array ::= "[" ("" | ws basic_any (ws "," ws basic_any)*) ws "]"
basic_object ::= "{" ("" | ws basic_string ws ":" ws basic_any ( ws "," ws basic_string ws ":" ws basic_any)*) ws "}"
ws ::= [ \n\t]*
"""
compiled_grammar = grammar_compiler.compile_grammar(json_grammar_ebnf_str)

xgr_logits_processor = xgr.contrib.hf.LogitsProcessor(compiled_grammar)
generated_ids = model.generate(
    **model_inputs, max_new_tokens=512, logits_processor=[xgr_logits_processor]
)
generated_ids = generated_ids[0][len(model_inputs.input_ids[0]) :]
print(tokenizer.decode(generated_ids, skip_special_tokens=True))

#%%
# Guided decoding by Grammar
simplified_sql_grammar = r"""
root ::= select_statement
select_statement ::= "SELECT " column_list " FROM " table_name
column_list ::= column_name (", " column_name)*
table_name ::= identifier
column_name ::= identifier
identifier ::= [a-zA-Z_][a-zA-Z_]*
"""

prompt = ("Generate an SQL query to show the 'username' and 'email' from the 'users' table.")
completion = client.chat.completions.create(
    model="Qwen/Qwen2.5-7B",
    messages=[{
        "role": "user",
        "content": prompt,
    }],
    extra_body={
        "guided_grammar": simplified_sql_grammar
        },
)
print(completion.choices[0].message.content)

# %%
# Guided decoding by Grammar
son_grammar_ebnf_str = r"""
root ::= basic_array | basic_object
basic_any ::= basic_number | basic_string | basic_boolean | basic_null | basic_array | basic_object
basic_integer ::= ("0" | "-"? [1-9] [0-9]*) ".0"?
basic_number ::= ("0" | "-"? [1-9] [0-9]*) ("." [0-9]+)? ([eE] [+-]? [0-9]+)?
basic_string ::= (([\"] basic_string_1 [\"]))
basic_string_1 ::= "" | [^"\\\x00-\x1F] basic_string_1 | "\\" escape basic_string_1
escape ::= ["\\/bfnrt] | "u" [A-Fa-f0-9] [A-Fa-f0-9] [A-Fa-f0-9] [A-Fa-f0-9]
basic_boolean ::= "true" | "false"
basic_null ::= "null"
basic_array ::= "[" ("" | ws basic_any (ws "," ws basic_any)*) ws "]"
basic_object ::= "{" ("" | ws basic_string ws ":" ws basic_any ( ws "," ws basic_string ws ":" ws basic_any)*) ws "}"
ws ::= [ \n\t]*
"""

messages = [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Introduce yourself in JSON briefly."},
]

prompt = ("Generate an SQL query to show the 'username' from the 'users' table.")
completion = client.chat.completions.create(
    model="Qwen/Qwen2.5-7B",
    messages=messages,
    extra_body={
        "guided_grammar": son_grammar_ebnf_str
        },
)
print(completion.choices[0].message.content)

#%%
