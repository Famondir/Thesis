from abc import ABC, abstractmethod
import re
import torch
# from transformers import AutoModelForCausalLM, AutoTokenizer, AutoConfig
from vllm import LLM, SamplingParams
from vllm.sampling_params import GuidedDecodingParams
import time
import json
import xgrammar as xgr
import pandas as pd
import pypdfium2 as pdfium
from pprint import pprint
from deepdiff import DeepDiff
import nltk
import numpy as np

unit_list = {
    'EUR': 1, 
    '€': 1, 
    'Tsd. EUR': 1000, 
    'Mio. EUR': 1000000, 
    'TEUR': 1000, 
    'T€': 1000, 
    'Tsd. €': 1000, 
    'Mio. €': 1000000
}

class Extractor(ABC):
    def __init__(self, model, model_name, temperature):
        self.model = model
        self.model_name = model_name
        self.tokenizer = self.model.get_tokenizer()
        self.temperature = temperature
        # self.tokenizer = AutoTokenizer.from_pretrained(self.model_name)

    # @abstractmethod
    # def extract(self, text, **kwargs):
    #     pass

class TableTemplateFillingExtractor(Extractor):
    def __init__(self, model, model_name, temperature):
        super().__init__(model, model_name, temperature)

        self.ebnf_str = self.replace_special_characters(r"""
        root ::= "[{\"E1\":\"Anlagevermögen\",\"E2\":\"Immaterielle Vermögensgegenstände\",\"E3\":\"Selbst geschaffene gewerbliche Schutzrechte und ähnliche Rechte und Werte\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Immaterielle Vermögensgegenstände\",\"E3\":\"Geschäfts- oder Firmenwert\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Immaterielle Vermögensgegenstände\",\"E3\":\"geleistete Anzahlungen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Immaterielle Vermögensgegenstände\",\"E3\":\"entgeltlich erworbene Konzessionen, gewerbliche Schutzrechte und ähnliche Rechte und Werte sowie Lizenzen an solchen Rechten und Werten\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Sachanlagen\",\"E3\":\"Grundstücke, grundstücksgleiche Rechte und Bauten einschließlich der Bauten auf fremden Grundstücken\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Sachanlagen\",\"E3\":\"Technische Anlagen und Maschinen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Sachanlagen\",\"E3\":\"Andere Anlagen, Betriebs- und Geschäftsausstattung\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Sachanlagen\",\"E3\":\"geleistete Anzahlungen und Anlagen im Bau\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Finanzanlagen\",\"E3\":\"Sonstige Finanzanlagen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Finanzanlagen\",\"E3\":\"Anteile an verbundenen Unternehmen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Finanzanlagen\",\"E3\":\"Ausleihungen an verbundene Unternehmen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Finanzanlagen\",\"E3\":\"Beteiligungen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Finanzanlagen\",\"E3\":\"Ausleihungen an Unternehmen, mit denen ein Beteiligungsverhältnis besteht\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Finanzanlagen\",\"E3\":\"Wertpapiere des Anlagevermögens\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Finanzanlagen\",\"E3\":\"Sonstige Ausleihungen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Vorräte\",\"E3\":\"Roh-, Hilfs- und Betriebsstoffe\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Vorräte\",\"E3\":\"Unfertige Erzeugnisse, unfertige Leistungen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Vorräte\",\"E3\":\"Fertige Erzeugnisse und Waren\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Vorräte\",\"E3\":\"Geleistete Anzahlungen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Forderungen und sonstige Vermögensgegenstände\",\"E3\":\"Forderungen aus Lieferungen und Leistungen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Forderungen und sonstige Vermögensgegenstände\",\"E3\":\"Forderungen gegen verbundene Unternehmen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Forderungen und sonstige Vermögensgegenstände\",\"E3\":\"Forderungen gegen Unternehmen, mit denen ein Beteiligungsverhältnis besteht\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Forderungen und sonstige Vermögensgegenstände\",\"E3\":\"Sonstige Vermögensgegenstände\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Wertpapiere\",\"E3\":\"Anteile an verbundenen Unternehmen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Wertpapiere\",\"E3\":\"Sonstige Wertpapiere\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Kassenbestand, Bundesbankguthaben, Guthaben bei Kreditinstituten und Schecks\",\"E3\":null,\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Rechnungsabgrenzungsposten\",\"E2\":null,\"E3\":null,\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Aktive latente Steuern\",\"E2\":null,\"E3\":null,\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Aktiver Unterschiedsbetrag aus der Vermögensverrechnung\",\"E2\":null,\"E3\":null,\"year\":" number_or_null ",\"previous_year\":" number_or_null "}]"
        number_or_null ::= number | "null"
        number ::= "0" | ([1-9][0-9]{0,14}) ("." [0-9]{1,15})?
        """)
        self.ebnf_rows = pd.read_csv("/pvc/benchmark_truth/real_tables/ebnf_rows.csv")

    def get_json_string(self, df, multiplier=1):
        df_rounded = df.copy()
        df_rounded = self.ebnf_rows.merge(df_rounded, how="left", on=["E1", "E2", "E3"])
        if len(df_rounded.columns) >= 2:
            last_two = df_rounded.columns[-2:]
            df_rounded = df_rounded.rename(columns={last_two[-2]: "year", last_two[-1]: "previous_year"})
        for col in ["year", "previous_year"]:
            if col in df_rounded.columns:
                df_rounded[col] = pd.to_numeric(df_rounded[col], errors='coerce')
                df_rounded[col] = df_rounded[col].apply(lambda x: f"{x/multiplier:.2f}" if pd.notnull(x) else x)
        # print(df_rounded.head(5))
        # print(df_rounded.shape[0], "rows in the dataframe after merging with EBNF rows.")

        s = df_rounded.to_json(orient='records', indent=0, force_ascii=False)#.replace("null", '"null"')
        s_fixed = re.sub(r'("year":)"([0-9\.\-e]+)"', r'\1\2', s)
        s_fixed = re.sub(r'("previous_year":)"([0-9\.\-e]+)"', r'\1\2', s_fixed)
        json_str = self.replace_special_characters(s_fixed)

        prev_entry = ",{\"E1\":\"Anlagevermoegen\",\"E2\":\"Finanzanlagen\",\"E3\":\"Ausleihungen an Unternehmen, mit denen ein Beteiligungsverhaeltnis besteht\""
        beteilingungen_entry = ",{\"E1\":\"Anlagevermoegen\",\"E2\":\"Finanzanlagen\",\"E3\":\"Beteiligungen\""

        if beteilingungen_entry not in json_str:
            json_str = json_str.replace(prev_entry, beteilingungen_entry + ',"year":null,"previous_year":null}' + prev_entry)
            # print(f"Ground truth JSON string: \n{json_str}")
        
        return json_str

    def __get_random_example_message(self, all_entries, n_examples=3, **kwargs):
        import random

        system_messages = []

        sample = random.sample(all_entries, n_examples)
        examples = [entry.get('text') for entry in sample]
        # print(examples)

        solutions = []
        for entry in sample:
            entry_filepath = entry.get('filepath', 'unknown').replace('.pdf', '.csv')
            df = pd.read_csv(entry_filepath)

            unit = entry_filepath.split('_')[-4]
            multiplier = unit_list.get(unit, 1)
            json_str = self.get_json_string(df, multiplier=multiplier)
            solutions.append(json_str)

        for idx, (ex, sol) in enumerate(zip(examples, solutions)):
            system_messages.append(f'\nHere is an example of input and the output you should produce:\n\nExample input {idx}:\n{ex}\n            ')
            system_messages.append(f'\nExample output {idx}:\n{sol}\n')

        # for example in examples:
        #     system_messages.append(f"You know this example {example.get('text')}\n'''.")

        # pprint(system_messages)
        return system_messages

    def __get_top_n_rag_example_message(self, text, collection, filepath, exclude_company="", embedding=None, report_distance=True, n_examples=5, **kwargs):
        # Embed the text only once
        if embedding is not None:
            embedded_text = embedding
            # print("Using provided embedding for the text.")
        else:
            # Use the sentence_transformer_ef to embed the text
            embedded_text = sentence_transformer_ef([text])

        orig_filepath = filepath.replace('/pvc/benchmark_truth/real_tables/', '/pvc/benchmark_truth/real_tables/manual_download/').replace('__', '/')

        examples = collection.query(
            query_embeddings=embedded_text,
            n_results=n_examples,
            where={"$and": [{"company": {"$ne": exclude_company}}, {"filepath": {"$ne": orig_filepath}}]}
        )

        # print(filepath)
        # print(exclude_company)
        # print(examples['metadatas'])
        # print(examples['distances'])

        system_messages = []

        for idx, (example, meta_data, distance) in enumerate(zip(examples['documents'][0], examples['metadatas'][0], examples['distances'][0])):
            entry_filepath = meta_data.get('filepath', 'unknown').replace('.pdf', '.csv')
            entry_filepath = re.sub(
            r"/pvc/benchmark_truth/real_tables/manual_download/([^/]+)/([^/]+)$",
            r"/pvc/benchmark_truth/real_tables/\1__\2",
            entry_filepath
            )
            df = pd.read_csv(entry_filepath)

            unit = entry_filepath.split('_')[-4]
            multiplier = unit_list.get(unit, 1)
            json_str = self.get_json_string(df, multiplier=multiplier)
            sol = json_str

            system_messages.append(f'\nHere is an example of input and the output you should produce:\n\nExample input {idx}:\n{example}\n            ')
            system_messages.append(f'\nExample output {idx}:\n{sol}\n')
            system_messages.append(
                (f"\n(The L2 distance of this example text is: {round(distance, 3)})\n" if report_distance else "")
            )

        # pprint(["---------Messages: ------------\n\n"] + system_messages)
        return system_messages

    def __get_static_example_message(self, **kwargs):
        system_messages = []

        # print("Using static example for table extraction")
        file_path_example = '/pvc/benchmark_truth/synthetic_tables/separate_files/aktiva_table_4_columns_span_False_thin_True_year_as_date_unit_in_first_cell_False_€_enumeration_True_0'
        df_example = pd.read_csv(file_path_example+'.csv')

        pdf_example = pdfium.PdfDocument(file_path_example+'.pdf')
        text_example = pdf_example.get_page(0).get_textpage().get_text_bounded()

        prompt_example = f"""
Here is an example of an input and the output you should produce:

Input:
{text_example}
        """

        prompt_solution =f"""
Output:
{self.get_json_string(df_example)}
        """

        system_messages.append(prompt_example)
        system_messages.append(prompt_solution)

        pdf_example.close()

        return system_messages

    def get_messages(self, text, static_example = False, random_examples=False, top_n_rag_examples = False, combine_system_prompts= False, **kwargs):
        messages = [
        {"role": "system", "content": "You are a helpful assistant that extracts information from tables."}
        ]
        
        baseprompt = """
Extract the information from the given table as JSON list. Each row should be an entry with five keys. The keys names are "E1", "E2", "E3", "year", "previous_year".

The entries for "E1", "E2" and "E3" are given by an EBNF. You just have to extract the numeric values for "year" and "previous_year" from the second and third or fourth and fifth columns, respectively.

If there are no corresponding numeric values for a given triple of "E1", "E2" and "E3" it should be represented by "null".

Skip the first one or two rows if they contain headers or units.
        """
        #Do not alter the numeric values. Just extract the numeric values as they are. Ignore the currency symbol and the thousands separator.
        
        messages.append({"role": "system", "content": baseprompt})
        # messages.append({
        #     "role": "system",
        #     "content": (
        #         "You will have to satisfy this ebnf grammar:\n\n"
        #         f"{self.ebnf_str}\n\n"
        #     ),
        # })

        if static_example:
            system_messages = self.__get_static_example_message(**kwargs)
            for msg in system_messages:
                messages.append({"role": "system", "content": msg})

        if random_examples:
            system_messages = self.__get_random_example_message(**kwargs)
            for msg in system_messages:
                messages.append({"role": "system", "content": msg})

        if top_n_rag_examples:
            system_messages = self.__get_top_n_rag_example_message(text, **kwargs)
            for msg in system_messages:
                messages.append({"role": "system", "content": msg})

        # Combine all "system" messages so far into one
        if combine_system_prompts:
            # print('Combining system prompts...')
            system_contents = [msg["content"] for msg in messages if msg["role"] == "system"]
            if system_contents:
                combined_content = "\n\n".join(system_contents)
                # Remove all previous system messages
                messages = [msg for msg in messages if msg["role"] != "system"]
                # Add the combined system message
                messages.insert(0, {"role": "system", "content": combined_content})

        messages.append({
            "role": "user",
            "content": (
                "This is the table you should extract the information from:\n"
                "```\n"
                f"{text}\n"
                "```\n"
                f"""
                You should fullfill this ebnf grammar:\n
                '''
                {self.ebnf_str}
                '''
                """
            ),
        })

        # print(messages)
        return messages

    def replace_special_characters(self, text):
        # Replace German special characters in the input text
        return (
            text.replace("ä", "ae")
            .replace("ö", "oe")
            .replace("ü", "ue")
            .replace("Ä", "Ae")
            .replace("Ö", "Oe")
            .replace("Ü", "Ue")
            .replace("ß", "ss")
        )

    def calc_confidence_scores(self, output):
        logprobs = output.outputs[0].logprobs
        # print(f"Logprobs: {[value for entry in logprobs for key, value in entry.items()]}")
        tokens = [(value.decoded_token, value.logprob) for entry in logprobs for key, value in entry.items()]

        confidence_scores = []
        number_queue = []
        last_token = ""

        # print(tokens[0:10])  # Print first 10 tokens to verify loading

        for token, logprob in tokens:
            # print(f"Processing token: {token}, logprob: {logprob}")    
            if token.isnumeric() or token == '.':
                # skip the interger in the hierarchy headings E1, E2, E3
                if last_token != "E":
                    number_queue.append((token, logprob))
            else:  
                if token == 'null':
                    confidence_scores.append((np.nan, np.exp(logprob)))
                if number_queue:
                    num = "".join([num[0] for num in number_queue])
                    try:
                        num = float(num)
                    except ValueError:
                        num = np.nan
                    confidence_scores.append((num, np.exp(sum([num[1] for num in number_queue]))))
                    # print([num[1] for num in number_queue])
                    number_queue = []

            last_token = token

        # print(f"Current confidence scores: {confidence_scores}")
        return confidence_scores

    def prepare_to_extract(self, text, max_tokens=4096, **kwargs):
        messages = self.get_messages(text, **kwargs)

        if "qwen3" in self.model_name.lower() and kwargs.get("no_think", True):
            messages[0]["content"] = "/no_think "+messages[0]["content"]
            
        # Replace German special characters in the messages
        messages = [{'role': msg['role'], 'content': self.replace_special_characters(msg['content'])} for msg in messages]
        texts = self.tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)  # You can keep this if you want to use the same prompt formatting
        # print(f"Prepared text for extraction: {texts!r}")

        if isinstance(texts, list) and all(isinstance(x, int) for x in texts):
            # print(f"Decoding tokens...\n{texts[0:10]}")
            texts = self.tokenizer.decode(texts, skip_special_tokens=True)

        return texts

    def extract_queued(self, texts, max_tokens=40096, **kwargs):
        guided_decoding_params = GuidedDecodingParams(grammar=self.ebnf_str)
        sampling_params = SamplingParams(
            guided_decoding=guided_decoding_params, max_tokens=max_tokens, 
            temperature=self.temperature, logprobs=1
            )

        try:
            outputs = self.model.generate(texts, sampling_params)
        except RuntimeError as e:
            # Check for the specific error message
            if "Invalid token id" in str(e):
                # Find the offending token id(s)
                input_ids = self.tokenizer(texts)["input_ids"]
                vocab_size = len(self.tokenizer)
                for token_id in input_ids:
                    if token_id < 0 or token_id >= vocab_size:
                        print(f"Offending token id: {token_id}")
                        try:
                            token_bytes = self.tokenizer.decode([token_id]).encode("utf-8")
                            print(f"Decoded token (utf-8): {token_bytes}")
                        except Exception as decode_err:
                            print(f"Could not decode token id {token_id}: {decode_err}")
            # raise  # Re-raise the error after printing debug info
            else:
                print(f"RuntimeError during generation: {e}")
            return None
        except Exception as e:
            print(f"Unexpected error during generation: {e}")
            return None



        confidence_scores = []
        for output in outputs:
            prob_values = self.calc_confidence_scores(output)
            confidence_scores.append(prob_values)

        # for output in outputs[0:2]:
        #     prompt = output.prompt
        #     generated_text = output.outputs[0].text
        #     print(f"Generated text: {generated_text!r}")
        results = [re.sub(r'^.*?assistantfinal', '', output.outputs[0].text, flags=re.DOTALL) for output in outputs]
        # print(f"Confidence score:\n{confidence_scores[-1]}")

        # print(f"Extracted result:\n\n{result}")
        return results, confidence_scores

class TableExtractionBenchmarkLLM():
    def __init__(self, extractor, extractor_type, verbose=False, combine_system_prompts=False):
        self.extractor = extractor
        self.extractor_type = extractor_type
        self.verbose = verbose
        self.combine_system_prompts = combine_system_prompts

    def parse_json(self, string):
        # Remove code block markers and extra whitespace, then parse as JSON
        json_str = string.strip()
        if json_str.startswith("```json"):
            json_str = json_str[len("```json"):].strip()
        if json_str.endswith("```"):
            json_str = json_str[:-3].strip()
        parsed_json = json.loads(json_str)
        return parsed_json

    def evaluate_single_result(self, result, entry):
        evaluation = {
            'json_error': False,
            'grammar_error': False,
        }

        entry_filepath = entry.get('filepath', 'unknown').replace('.pdf', '.csv')
        df = pd.read_csv(entry_filepath)

        # unit = entry_filepath.split('_')[-4]
        # multiplier = unit_list.get(unit, 1)

        # rounds values matching with the one in the pdfs (synthetic tables important)
        multiplier = 1  # Default multiplier, can be adjusted based on the unit in the entry
        json_str = self.extractor.get_json_string(df, multiplier=multiplier)

        try:
            truth = self.parse_json(json_str)
        except json.JSONDecodeError as e:
            raise ValueError(f"Error parsing JSON for truth: {json_str[:100]}\nError message: {e}")
        # pprint(truth)
        df_truth = pd.DataFrame(truth)

        result = result.replace('๏', 'äf').replace('࿌', 'üc')
        # print(result)
        try:
            result_json = self.parse_json(result)
        except json.JSONDecodeError as e:
            print(f"Error parsing result: {result}\nError message: {e}")
            evaluation['json_error'] = True
            return evaluation

        try:
            df_result = pd.DataFrame(result_json)
            df_result = df_result.map(lambda x: np.nan if x is None else x)
        except OverflowError:
            print(f"OverflowError parsing result to pandas df: {result_json}")
            evaluation['grammar_error'] = True
            return evaluation
            
        # Join the ground truth and result dataframes on E1, E2, and E3 for comparison
        df_joined = pd.merge(
            df_truth,
            df_result,
            on=["E1", "E2", "E3"],
            how="left",
            suffixes=("_truth", "_result"),
            indicator=True
        )
        evaluation['df_joined'] = df_joined
        # print(df_joined[['E1', 'E2', 'E3', 'year_truth', 'year_result',]])

        try:
            diff = DeepDiff(truth, result_json, significant_digits=2, get_deep_distance=True)
            evaluation['deep_distance'] = diff.get('deep_distance', None)
            # evaluation['changed_values'] = diff.get('values_changed', {})
            # print(diff)
        except OverflowError:
            print(f"OverflowError parsing result for DeepDiff: {result_json}")
            # evaluation['grammar_error'] = True
            # return evaluation

        evaluation['NA'] = {
            "true_positive": df_joined[(df_joined['_merge'] == 'both') & (df_joined['year_truth'].isna() & df_joined['year_result'].isna())].shape[0] + df_joined[(df_joined['_merge'] == 'both') & (df_joined['previous_year_truth'].isna() & df_joined['previous_year_result'].isna())].shape[0],
            "false_positive": df_joined[(df_joined['_merge'] == 'both') & (df_joined['year_truth'].notna() & df_joined['year_result'].isna())].shape[0] + df_joined[(df_joined['_merge'] == 'both') & (df_joined['previous_year_truth'].notna() & df_joined['previous_year_result'].isna())].shape[0],
            "false_negative": df_joined[(df_joined['_merge'] == 'both') & (df_joined['year_truth'].isna() & df_joined['year_result'].notna())].shape[0] + df_joined[(df_joined['_merge'] == 'both') & (df_joined['previous_year_truth'].isna() & df_joined['previous_year_result'].notna())].shape[0],
            "true_negative": df_joined[(df_joined['_merge'] == 'both') & (df_joined['year_truth'].notna() & df_joined['year_result'].notna())].shape[0] + df_joined[(df_joined['_merge'] == 'both') & (df_joined['previous_year_truth'].notna() & df_joined['previous_year_result'].notna())].shape[0]
        }

        df_year_non_na = df_joined[(df_joined['_merge'] == 'both') & (df_joined['year_truth'].notna() & df_joined['year_result'].notna())]
        df_year_non_na = df_year_non_na.drop(
            columns=[col for col in df_year_non_na.columns if 'previous_year' in col],
            errors='ignore'
        )
        try:
            df_year_non_na['relative_numeric_difference'] = (
                (df_year_non_na['year_result'] - df_year_non_na['year_truth']).abs() /
                df_year_non_na['year_truth'].abs().replace(0, 1)
            )
        except OverflowError:
            print(f"OverflowError calculating relative numeric difference: {result_json}")
            
        df_year_non_na['levenstein_distance'] = df_year_non_na.apply(
            lambda row: nltk.edit_distance(
            str(row['year_truth']), str(row['year_result'])
            ),
            axis=1
        )

        df_previous_year_non_na = df_joined[(df_joined['_merge'] == 'both') & (df_joined['previous_year_truth'].notna() & df_joined['previous_year_result'].notna())]
        df_previous_year_non_na = df_previous_year_non_na.drop(
            columns=[col for col in df_previous_year_non_na.columns if col.startswith('year')],
            errors='ignore'
        )
        df_previous_year_non_na['relative_numeric_difference'] = (
            (df_previous_year_non_na['previous_year_result'] - df_previous_year_non_na['previous_year_truth']).abs() /
            df_previous_year_non_na['previous_year_truth'].abs().replace(0, 1)
        )
        df_previous_year_non_na['levenstein_distance'] = df_previous_year_non_na.apply(
            lambda row: nltk.edit_distance(
            str(row['previous_year_truth']), str(row['previous_year_result'])
            ),
            axis=1
        )

        # Attach both columns for detailed analysis
        evaluation['relative_numeric_difference'] = {
            "mean": (df_year_non_na['relative_numeric_difference'].mean() + df_previous_year_non_na['relative_numeric_difference'].mean())/2,
            "median": (pd.concat([df_year_non_na['relative_numeric_difference'], df_previous_year_non_na['relative_numeric_difference']]).median())
        }
        evaluation['levenstein_distance'] = {
            "mean": (df_year_non_na['levenstein_distance'].mean() + df_previous_year_non_na['levenstein_distance'].mean())/2,
            "median": (pd.concat([df_year_non_na['levenstein_distance'], df_previous_year_non_na['levenstein_distance']]).median())
        }
        evaluation['correct_numeric'] = df_year_non_na[df_year_non_na['year_truth'] == df_year_non_na['year_result']].shape[0] + df_previous_year_non_na[df_previous_year_non_na['previous_year_truth'] == df_previous_year_non_na['previous_year_result']].shape[0]
        evaluation['incorrect_numeric'] = df_year_non_na[df_year_non_na['year_truth'] != df_year_non_na['year_result']].shape[0] + df_previous_year_non_na[df_previous_year_non_na['previous_year_truth'] != df_previous_year_non_na['previous_year_result']].shape[0]
        evaluation['total_entries'] = df_joined.shape[0]*2

        return evaluation

    def extract_tables_queued(self, entries, result_dir, out_of_sample = True, **kwargs):
        start_time = time.time()
        n_pdfs = len(entries)
        evaluations = []

        if kwargs['no_think']:
            # print("Using no_think mode")
            result_dir = result_dir + "__no_think"

        texts = []

        for entry in entries:
            text = self.extractor.replace_special_characters(entry['text'])
            # print(text)
            kwargs['embedding'] = entry['embedding']
            texts.append(self.extractor.prepare_to_extract(text, exclude_company = entry.get('company', '') if out_of_sample else "", filepath=entry['filepath'], combine_system_prompts=self.combine_system_prompts, **kwargs))

        results, confidence_scores = self.extractor.extract_queued(texts, **kwargs)

        evaluations = []
        for result, entry, confidence, text in zip(results, entries, confidence_scores, texts):
            evaluation = self.evaluate_single_result(result, entry)
            evaluation['filepath'] = entry['filepath']
            try:
                evaluation['request_tokens'] = len(self.extractor.tokenizer(text)['input_ids'])
            except TypeError:
                print(f"TypeError calculating request tokens for text: {text}")
                evaluation['request_tokens'] = np.nan

            if evaluation['json_error']:
                print(f"JSON error for entry: {entry['filepath']}")
                evaluation['error_message'] = "JSON parsing error"
                evaluations.append(evaluation)
                continue

            # Add the confidence scores to the evaluation
            i = 0
            nrows = evaluation['df_joined'].shape[0]

            numbers_confidence = []
            for number, conf in confidence:
                if (i % 2 == 0 and nrows > i // 2):
                    df_number = float(evaluation['df_joined'].iloc[i // 2]['year_result'])
                elif (i % 2 == 1 and nrows > i // 2):
                    df_number = float(evaluation['df_joined'].iloc[i // 2]['previous_year_result'])
                else:
                    pass

                if nrows < i//2+1:
                    continue

                if ((df_number == number) or (np.isnan(df_number) and np.isnan(number))):
                    i += 1
                    numbers_confidence.append((number, conf))

            # Assign confidence scores to the dataframe
            confidence_this_year = [conf for idx, (number, conf) in enumerate(numbers_confidence) if idx % 2 == 0]
            confidence_previous_year = [conf for idx, (number, conf) in enumerate(numbers_confidence) if idx % 2 == 1]

            evaluation['df_joined']['confidence_this_year'] = pd.Series(confidence_this_year)
            evaluation['df_joined']['confidence_previous_year'] = pd.Series(confidence_previous_year)

            evaluations.append(evaluation)

        end_time = time.time()
        runtime = end_time - start_time
        print(f"Total runtime: {runtime:.2f} seconds")

        with open(f"{result_dir}_queued.json", "w") as json_file:
            json.dump(
                [{key: value.to_json(orient='records') if hasattr(value, 'to_json') else value for key, value in entry.items()} for entry in evaluations],
                json_file, 
                indent=4, 
                default=str
            )

        return evaluations