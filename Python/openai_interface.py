#%%
from openai import OpenAI
from pypdf import PdfReader

easy_table = "../benchmark_tables/easy_table_german_finance_v2.pdf"

reader = PdfReader(easy_table)
page = reader.pages[0]

prompt = '''Extract all tables from the following text and return them as JSON:

"""
{#data#}
"""

If there are no tables in the text respond with an empty JSON list.

Do not give any explanation or instructions. Just return the JSON fromated tables.

For each table give a key for each column header followed by a list with all the values of that column. It should follow this format:
[{
    "column_header_1": [value_1, value_2, ...],
    "column_header_2": [value_1, value_2, ...],
    ...
    "column_header_n": [value_1, value_2, ...]
},
{
    "column_header_1": [value_1, value_2, ...],
    "column_header_2": [value_1, value_2, ...],
    ...
    "column_header_m": [value_1, value_2, ...]
}]

If there are multiple tables create an seperate entry in the JSON list.
'''.replace("{#data#}", page.extract_text())

simplified_json_grammar = """
    ?start: json_list

    ?json_list: "[" table "]"

    ?table: "{" column ("," column)* "}"

    ?column: "\"" column_header "\"" ":" "[" value ("," value)* "]"

    ?column_header: identifier

    ?identifier: /[a-zA-Z_][a-zA-Z0-9_]*/

    ?value: /[a-zA-Z0-9"."","" "]*/
"""

copilot_json_grammar = '''
json_list ::= "[" table ("," table)* "]"

table ::= "{" column ("," column)* "}"

column ::= "\"" column_header "\"" ":" "[" value ("," value)* "]"

column_header ::= string

value ::= string | number | "true" | "false" | "null"

string ::= "\"" character* "\""

character ::= any_unicode_character_except_quotation_mark_or_backslash
             | "\\" escape_sequence

escape_sequence ::= "\"" | "\\" | "/" | "b" | "f" | "n" | "r" | "t" | "u" hex_digit hex_digit hex_digit hex_digit

number ::= integer (fraction)? (exponent)?

integer ::= "0" | non_zero_digit digit*

fraction ::= "." digit+

exponent ::= ("e" | "E") ("+" | "-")? digit+

digit ::= "0" | non_zero_digit

non_zero_digit ::= "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9"

hex_digit ::= digit | "a" | "b" | "c" | "d" | "e" | "f" | "A" | "B" | "C" | "D" | "E" | "F"
'''

# Modify OpenAI's API key and API base to use vLLM's API server.
openai_api_key = "EMPTY"
openai_api_base = "http://localhost:8001/v1"


def main():
    client = OpenAI(
        # defaults to os.environ.get("OPENAI_API_KEY")
        api_key=openai_api_key,
        base_url=openai_api_base,
    )

    models = client.models.list()
    model = models.data[0].id

    # Completion API
    stream = False
    completion = client.completions.create(
        model=model,
        prompt=prompt,
        echo=False,
        n=2,
        max_tokens=300,
        stream=stream,
        logprobs=3,
        extra_body={"guided_grammar": simplified_json_grammar}
    )

    """
    print("-" * 50)
    print("Completion results:")
    if stream:
        for c in completion:
            print(c)
    else:
        print(completion) # how to extract the text?
    print("-" * 50)
    """

    return completion


#%%
result = main()
#%%
result.choices[0].text
# %%
