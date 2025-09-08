from abc import ABC, abstractmethod
import re
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, AutoConfig
import time
import json
import xgrammar as xgr
import pandas as pd
import pypdfium2 as pdfium
from pprint import pprint
from deepdiff import DeepDiff
import nltk

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
    def __init__(self, model, model_name):
        self.model = model
        self.model_name = model_name
        self.tokenizer = AutoTokenizer.from_pretrained(self.model_name)

    @abstractmethod
    def extract(self, text, **kwargs):
        pass

class TableTemplateFillingExtractor(Extractor):
    def __init__(self, model, model_name):
        super().__init__(model, model_name)
        
        self.ebnf_str = self.replace_special_characters(r"""
        root ::= "[{\"E1\":\"Anlagevermögen\",\"E2\":\"Immaterielle Vermögensgegenstände\",\"E3\":\"Selbst geschaffene gewerbliche Schutzrechte und ähnliche Rechte und Werte\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Immaterielle Vermögensgegenstände\",\"E3\":\"Geschäfts- oder Firmenwert\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Immaterielle Vermögensgegenstände\",\"E3\":\"geleistete Anzahlungen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Immaterielle Vermögensgegenstände\",\"E3\":\"entgeltlich erworbene Konzessionen, gewerbliche Schutzrechte und ähnliche Rechte und Werte sowie Lizenzen an solchen Rechten und Werten\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Sachanlagen\",\"E3\":\"Grundstücke, grundstücksgleiche Rechte und Bauten einschließlich der Bauten auf fremden Grundstücken\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Sachanlagen\",\"E3\":\"Technische Anlagen und Maschinen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Sachanlagen\",\"E3\":\"Andere Anlagen, Betriebs- und Geschäftsausstattung\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Sachanlagen\",\"E3\":\"geleistete Anzahlungen und Anlagen im Bau\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Finanzanlagen\",\"E3\":\"Sonstige Finanzanlagen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Finanzanlagen\",\"E3\":\"Anteile an verbundenen Unternehmen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Finanzanlagen\",\"E3\":\"Ausleihungen an verbundene Unternehmen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Finanzanlagen\",\"E3\":\"Ausleihungen an Unternehmen, mit denen ein Beteiligungsverhältnis besteht\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Finanzanlagen\",\"E3\":\"Wertpapiere des Anlagevermögens\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Anlagevermögen\",\"E2\":\"Finanzanlagen\",\"E3\":\"Sonstige Ausleihungen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Vorräte\",\"E3\":\"Roh-, Hilfs- und Betriebsstoffe\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Vorräte\",\"E3\":\"Unfertige Erzeugnisse, unfertige Leistungen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Vorräte\",\"E3\":\"Fertige Erzeugnisse und Waren\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Vorräte\",\"E3\":\"Geleistete Anzahlungen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Forderungen und sonstige Vermögensgegenstände\",\"E3\":\"Forderungen aus Lieferungen und Leistungen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Forderungen und sonstige Vermögensgegenstände\",\"E3\":\"Forderungen gegen verbundene Unternehmen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Forderungen und sonstige Vermögensgegenstände\",\"E3\":\"Forderungen gegen Unternehmen, mit denen ein Beteiligungsverhältnis besteht\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Forderungen und sonstige Vermögensgegenstände\",\"E3\":\"Sonstige Vermögensgegenstände\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Wertpapiere\",\"E3\":\"Anteile an verbundenen Unternehmen\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Wertpapiere\",\"E3\":\"Sonstige Wertpapiere\",\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Umlaufvermögen\",\"E2\":\"Kassenbestand, Bundesbankguthaben, Guthaben bei Kreditinstituten und Schecks\",\"E3\":null,\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Rechnungsabgrenzungsposten\",\"E2\":null,\"E3\":null,\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Aktive latente Steuern\",\"E2\":null,\"E3\":null,\"year\":" number_or_null ",\"previous_year\":" number_or_null "},{\"E1\":\"Aktiver Unterschiedsbetrag aus der Vermögensverrechnung\",\"E2\":null,\"E3\":null,\"year\":" number_or_null ",\"previous_year\":" number_or_null "}]"
        number_or_null ::= number | "null"
        number ::= "0" | ([1-9][0-9]*) ("." [0-9]+)?
        """)

    def get_json_string(self, df, multiplier=1):
        df_rounded = df.copy()
        if len(df_rounded.columns) >= 2:
            last_two = df_rounded.columns[-2:]
            df_rounded = df_rounded.rename(columns={last_two[-2]: "year", last_two[-1]: "previous_year"})
        for col in ["year", "previous_year"]:
            if col in df_rounded.columns:
                df_rounded[col] = df_rounded[col].apply(lambda x: f"{x/multiplier:.2f}" if pd.notnull(x) else x)
        s = df_rounded.to_json(orient='records', indent=0, force_ascii=False)#.replace("null", '"null"')
        s_fixed = re.sub(r'("year":)"([0-9\.\-e]+)"', r'\1\2', s)
        s_fixed = re.sub(r'("previous_year":)"([0-9\.\-e]+)"', r'\1\2', s_fixed)
        return self.replace_special_characters(s_fixed)

    def get_messages(self, text, static_example = False, combine_system_prompts= False, **kwargs):
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

            messages.append({"role": "system", "content": prompt_example})
            messages.append({"role": "system", "content": prompt_solution})

            pdf_example.close()

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
            ),
        })

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

    def extract(self, text, max_tokens=4096, **kwargs):
        messages = self.get_messages(text, **kwargs)
        # Replace German special characters in the messages
        messages = [{'role': msg['role'], 'content': self.replace_special_characters(msg['content'])} for msg in messages]
        texts = self.tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
        model_inputs = self.tokenizer(texts, return_tensors="pt").to(self.model.device)

        config = AutoConfig.from_pretrained(self.model_name)
        vocab_size = config.vocab_size if hasattr(config, 'vocab_size') else len(self.tokenizer)
        # vocab_size = len(self.tokenizer)

        # Debug: Check token ids
        max_token_id = max(model_inputs['input_ids'][0].tolist())
        vocab_size = len(self.tokenizer)
        # print(f"Vocab size: {vocab_size}, Max token id: {max_token_id}")
        # assert max_token_id < vocab_size, f"Token id {max_token_id} >= vocab size {vocab_size}"

        tokenizer_info = xgr.TokenizerInfo.from_huggingface(self.tokenizer, vocab_size=vocab_size)
        grammar_compiler = xgr.GrammarCompiler(tokenizer_info)
        compiled_grammar = grammar_compiler.compile_grammar(self.ebnf_str)
        xgr_logits_processor = xgr.contrib.hf.LogitsProcessor(compiled_grammar)
        # pprint(messages)

        try:
            generated_ids = self.model.generate(
                **model_inputs, max_new_tokens=max_tokens, logits_processor=[xgr_logits_processor]
            )
        except RuntimeError as e:
            # Check for the specific error message
            if "Invalid token id" in str(e):
                # Find the offending token id(s)
                input_ids = model_inputs['input_ids'][0].tolist()
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
        generated_answer_ids = generated_ids[0][len(model_inputs.input_ids[0]) :]
        result = self.tokenizer.decode(generated_answer_ids, skip_special_tokens=True)

        # print(f"Extracted result:\n\n{result}")
        return result

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

        unit = entry_filepath.split('_')[-4]
        multiplier = unit_list.get(unit, 1)
        json_str = self.extractor.get_json_string(df, multiplier=multiplier)
        try:
            truth = self.parse_json(json_str)
        except json.JSONDecodeError as e:
            raise ValueError(f"Error parsing JSON for truth: {json_str}\nError message: {e}")
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

        df_result = pd.DataFrame(result_json)
        # Join the ground truth and result dataframes on E1, E2, and E3 for comparison
        df_joined = pd.merge(
            df_truth,
            df_result,
            on=["E1", "E2", "E3"],
            how="outer",
            suffixes=("_truth", "_result"),
            indicator=True
        )
        # print(df_joined[['E1', 'E2', 'E3', 'year_truth', 'previous_year_truth',]])

        diff = DeepDiff(truth, result_json, significant_digits=2, get_deep_distance=True)
        # print(diff)

        evaluation['deep_distance'] = diff.get('deep_distance', None)
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
        df_year_non_na['relative_numeric_difference'] = (
            (df_year_non_na['year_result'] - df_year_non_na['year_truth']).abs() /
            df_year_non_na['year_truth'].abs().replace(0, 1)
        )
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
        evaluation['changed_values'] = diff.get('values_changed', {})

        return evaluation

    def extract_tables(self, entries, result_dir, **kwargs):
        start_time = time.time()
        counter = 0
        n_pdfs = len(entries)
        evaluations = []

        if kwargs['no_think']:
            # print("Using no_think mode")
            result_dir = result_dir + "__no_think"

        for entry in entries:
            counter += 1

            # print(entry['text'])
            text = self.extractor.replace_special_characters(entry['text'][0])
            if self.verbose:
                print(f"Processing page {counter}/{n_pdfs} ...")
            if 'embedding' in entry:
                kwargs['embedding'] = entry['embedding']

            n_try = 0
            while n_try < 3:
                if n_try > 0:
                    print(f"Retrying extraction for entry {counter}/{n_pdfs} after failure...")
                result = self.extractor.extract(text, combine_system_prompts=self.combine_system_prompts, **kwargs)
                # result = '[{"E1":"Anlagevermögen","E2":"Immaterielle Vermögensgegenstände","E3":"Selbst geschaffene gewerbliche Schutzrechte und ähnliche Rechte und Werte","year":4.12,"previous_year":1.76},{"E1":"Anlagevermögen","E2":"Immaterielle Vermögensgegenstände","E3":"Geschäfts- oder Firmenwert","year":8.55,"previous_year":3.09},{"E1":"Anlagevermögen","E2":"Immaterielle Vermögensgegenstände","E3":"geleistete Anzahlungen","year":9.13,"previous_year":6.27},{"E1":"Anlagevermögen","E2":"Immaterielle Vermögensgegenstände","E3":"entgeltlich erworbene Konzessionen, gewerbliche Schutzrechte und ähnliche Rechte und Werte sowie Lizenzen an solchen Rechten und Werten","year":4.38,"previous_year":9.4},{"E1":"Anlagevermögen","E2":"Sachanlagen","E3":"Grundstücke, grundstücksgleiche Rechte und Bauten einschließlich der Bauten auf fremden Grundstücken","year":4.87,"previous_year":9.48},{"E1":"Anlagevermögen","E2":"Sachanlagen","E3":"Technische Anlagen und Maschinen","year":7.83,"previous_year":5.96},{"E1":"Anlagevermögen","E2":"Sachanlagen","E3":"Andere Anlagen, Betriebs- und Geschäftsausstattung","year":0.22,"previous_year":9.17},{"E1":"Anlagevermögen","E2":"Sachanlagen","E3":"geleistete Anzahlungen und Anlagen im Bau","year":3.78,"previous_year":8.35},{"E1":"Anlagevermögen","E2":"Finanzanlagen","E3":"Sonstige Finanzanlagen","year":null,"previous_year":null},{"E1":"Anlagevermögen","E2":"Finanzanlagen","E3":"Anteile an verbundenen Unternehmen","year":7.66,"previous_year":7.86},{"E1":"Anlagevermögen","E2":"Finanzanlagen","E3":"Ausleihungen an verbundene Unternehmen","year":7.66,"previous_year":3.33},{"E1":"Anlagevermögen","E2":"Finanzanlagen","E3":"Ausleihungen an Unternehmen, mit denen ein Beteiligungsverhältnis besteht","year":9.62,"previous_year":6.51},{"E1":"Anlagevermögen","E2":"Finanzanlagen","E3":"Wertpapiere des Anlagevermögens","year":1.48,"previous_year":1.12},{"E1":"Anlagevermögen","E2":"Finanzanlagen","E3":"Sonstige Ausleihungen","year":8.15,"previous_year":3.7},{"E1":"Umlaufvermögen","E2":"Vorräte","E3":"Roh-, Hilfs- und Betriebsstoffe","year":4.12,"previous_year":7.03},{"E1":"Umlaufvermögen","E2":"Vorräte","E3":"Unfertige Erzeugnisse, unfertige Leistungen","year":9.08,"previous_year":7.48},{"E1":"Umlaufvermögen","E2":"Vorräte","E3":"Fertige Erzeugnisse und Waren","year":6.18,"previous_year":3.59},{"E1":"Umlaufvermögen","E2":"Vorräte","E3":"Geleistete Anzahlungen","year":6.46,"previous_year":6.13},{"E1":"Umlaufvermögen","E2":"Forderungen und sonstige Vermögensgegenstände","E3":"Forderungen aus Lieferungen und Leistungen","year":7.68,"previous_year":8.17},{"E1":"Umlaufvermögen","E2":"Forderungen und sonstige Vermögensgegenstände","E3":"Forderungen gegen verbundene Unternehmen","year":4.91,"previous_year":9.02},{"E1":"Umlaufvermögen","E2":"Forderungen und sonstige Vermögensgegenstände","E3":"Forderungen gegen Unternehmen, mit denen ein Beteiligungsverhältnis besteht","year":8.39,"previous_year":5.63},{"E1":"Umlaufvermögen","E2":"Forderungen und sonstige Vermögensgegenstände","E3":"Sonstige Vermögensgegenstände","year":20.99,"previous_year":22.83},{"E1":"Umlaufvermögen","E2":"Wertpapiere","E3":"Anteile an verbundenen Unternehmen","year":9.15,"previous_year":1.55},{"E1":"Umlaufvermögen","E2":"Wertpapiere","E3":"Sonstige Wertpapiere","year":5.67,"previous_year":8.64},{"E1":"Umlaufvermögen","E2":"Kassenbestand, Bundesbankguthaben, Guthaben bei Kreditinstituten und Schecks","E3":null,"year":2.54,"previous_year":4.52},{"E1":"Rechnungsabgrenzungsposten","E2":null,"E3":null,"year":3.22,"previous_year":7.76},{"E1":"Aktive latente Steuern","E2":null,"E3":null,"year":5.47,"previous_year":0.32},{"E1":"Aktiver Unterschiedsbetrag aus der Vermögensverrechnung","E2":null,"E3":null,"year":8.27,"previous_year":7.94}]'
                if result is not None:
                    break
                n_try += 1
            
            if result is None:
                print(f"Failed to extract table from page {counter}/{n_pdfs}. Skipping...")
                evaluations.append({
                    'grammar_error': True,
                    'filepath': entry['filepath'],
                })
            else:
                evaluation = self.evaluate_single_result(result, entry)
                evaluation['filepath'] = entry['filepath']
                # pprint(evaluation)
                evaluations.append(evaluation)

            with open(f"{result_dir}.json", "w") as json_file:
                json.dump(
                    evaluations,
                    json_file, 
                    indent=4, 
                    default=str
                )

        end_time = time.time()
        runtime = end_time - start_time
        print(f"Total runtime: {runtime:.2f} seconds")

        with open(f"{result_dir}.json", "w") as json_file:
            json.dump(
                evaluations,
                json_file, 
                indent=4, 
                default=str
            )

        return evaluations