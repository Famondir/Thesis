from abc import ABC, abstractmethod
import torch
# from transformers import AutoModelForCausalLM, AutoTokenizer, AutoConfig
from vllm import LLM, SamplingParams
from vllm.sampling_params import GuidedDecodingParams
import time
import json
import numpy as np

phrase_dict = {
        "GuV": "a 'Gewinn- und Verlustrechnung' (profit and loss statement) table",
        "Aktiva": "a 'Aktiva' (assets) table",
        "Passiva": "a 'Passiva' (liabilities) table",
        'other': "a text that does not suit the categories of interest",
        # "othertable": "a table that is not a 'Gewinn- und Verlustrechnung' (profit and loss statement), 'Aktiva' (assets) or 'Passiva' (liabilities)",
        # "notable": "a text that does not contain a table"
    }

def get_random_example_message_multiclass(all_entries, n_examples=1): # optimized for binary classification
    import random

    examples = {key: [] for key in phrase_dict.keys()}
    system_messages = []

    for key in phrase_dict.keys():
        examples[key] = [s.get("text") for s in random.sample([entry for entry in all_entries if entry.get("type") == key], n_examples)]

    for key, item in examples.items():
        for example in item:
            system_messages.append(f'You know this example for {phrase_dict.get(key, 'unknown type')} and for this example you should answer with "{key}":\n\n"""\n{example}\n""".') # is the 'and you should answer with' part necessary?

    return system_messages

def get_random_example_message_binary(classification_type, all_entries, n_examples=1): # optimized for binary classification
    import random

    examples = {key: [] for key in phrase_dict.keys()}
    system_messages = []

    for key in phrase_dict.keys():
        examples[key] = [s.get("text") for s in random.sample([entry for entry in all_entries if entry.get("type") == key], n_examples if key in [classification_type, "other"] else max(n_examples//2, 1))] # how many 'other' examples do we want?

    for key, item in examples.items():
        for example in item:
            system_messages.append(f"You know this example for {phrase_dict.get(key, 'unknown type')} and for this example you should answer with {'"yes"' if key == classification_type else '"no"'}:\n\n'''\n{example}\n'''.") # is the 'and you should answer with' part necessary?

    return system_messages

def get_rag_example_messages_multiclass(text, collection, filepath, exclude_company="", embedding=None, report_distance=True, n_examples=1):
    examples = {key: [] for key in phrase_dict.keys()}
    system_messages = []

    # Embed the text only once
    if embedding is not None:
        embedded_text = embedding
    else:
        # Use the sentence_transformer_ef to embed the text
        embedded_text = sentence_transformer_ef([text])

    # Now use the embedded_text in all queries
    for key in phrase_dict.keys():
        examples[key] = collection.query(
            query_embeddings=embedded_text,
            n_results=n_examples, # how many 'other' examples do we want?
            where={"$and": [{"company": {"$ne": exclude_company}}, {"type": key}, {"filepath": {"$ne": filepath}}]}
        )

    for key, rag_examples in examples.items():
        for example, meta_data, distance in zip(rag_examples['documents'][0], rag_examples['metadatas'][0], rag_examples['distances'][0]):
            system_messages.append(
                f'You know this example for {phrase_dict.get(key, 'unknown type')} and for this example you should answer with "{key}":\n\n"""\n{example}\n""".' + 
                (f" (The L2 distance of this example text is: {round(distance, 3)})" if report_distance else "")
            )
        
    return system_messages

def get_rag_example_messages_binary(text, classification_type, collection, filepath, exclude_company="", embedding=None, report_distance=True, n_examples=1):
    examples = {key: [] for key in phrase_dict.keys()}
    system_messages = []

    # Embed the text only once
    if embedding is not None:
        embedded_text = embedding
    else:
        # Use the sentence_transformer_ef to embed the text
        embedded_text = sentence_transformer_ef([text])

    # Now use the embedded_text in all queries
    for key in phrase_dict.keys():
        examples[key] = collection.query(
            query_embeddings=embedded_text,
            n_results=n_examples if key in [classification_type, "other"] else max(n_examples//2, 1), # how many 'other' examples do we want?
            where={"$and": [{"company": {"$ne": exclude_company}}, {"type": key}, {"filepath": {"$ne": filepath}}]}
        )

    for key, rag_examples in examples.items():
        for example, meta_data, distance in zip(rag_examples['documents'][0], rag_examples['metadatas'][0], rag_examples['distances'][0]):
            system_messages.append(
                f"You know this example for {phrase_dict.get(key, 'unknown type')} and for this example you should answer with {'"yes"' if key == classification_type else '"no"'}:\n\n'''\n{example}\n'''." + 
                (f" (The L2 distance of this example text is: {round(distance, 3)})" if report_distance else "")
            )
        
    return system_messages

def get_top_n_rag_example_messages_multiclass(text, collection, filepath, exclude_company="", embedding=None, report_distance=True, n_examples=5):
    # Embed the text only once
    if embedding is not None:
        embedded_text = embedding
    else:
        # Use the sentence_transformer_ef to embed the text
        embedded_text = sentence_transformer_ef([text])

    examples = collection.query(
        query_embeddings=embedded_text,
        n_results=n_examples,
        where={"$and": [{"company": {"$ne": exclude_company}}, {"filepath": {"$ne": filepath}}]}
    )

    system_messages = []
    
    for example, meta_data, distance in zip(examples['documents'][0], examples['metadatas'][0], examples['distances'][0]):
        # print(f"filepath: {filepath}")
        # print(f"meta_data: {meta_data.get('filepath', '')}")
        system_messages.append(
            f'You know this example for {phrase_dict.get(meta_data.get("type"), "unknown type")} and for this example you should answer with "{meta_data.get("type")}":\n\n"""\n{example}\n""".' + 
            (f" (The L2 distance of this example text is: {round(distance, 3)})" if report_distance else "")
        )

    return system_messages

def get_top_n_rag_example_messages_binary(text, classification_type, collection, filepath, exclude_company="", embedding=None, report_distance=True, n_examples=5):
    # Embed the text only once
    if embedding is not None:
        embedded_text = embedding
    else:
        # Use the sentence_transformer_ef to embed the text
        embedded_text = sentence_transformer_ef([text])

    examples = collection.query(
        query_embeddings=embedded_text,
        n_results=n_examples,
        where={"$and": [{"company": {"$ne": exclude_company}}, {"filepath": {"$ne": filepath}}]}
    )

    system_messages = []
    
    for example, meta_data, distance in zip(examples['documents'][0], examples['metadatas'][0], examples['distances'][0]):
        # print(f"filepath: {filepath}")
        # print(f"meta_data: {meta_data.get('filepath', '')}")
        system_messages.append(
            f"You know this example for {phrase_dict.get(meta_data.get('type'), 'unknown type')} and for this example you should answer with {'"yes"' if meta_data.get('type') == classification_type else '"no"'}:\n\n'''\n{example}\n'''." + 
            (f" (The L2 distance of this example text is: {round(distance, 3)})" if report_distance else "")
        )

    return system_messages

class StringClassifier(ABC):
    def __init__(self, model, model_name):
        self.model_name = model_name
        self.model = model
        self.tokenizer = self.model.get_tokenizer()
        # self.tokenizer = AutoTokenizer.from_pretrained(model_name)
        # self.config = AutoConfig.from_pretrained(model_name)

    # @abstractmethod
    # def classify(self, text):
    #     pass

class BinaryStringClassifier(StringClassifier):
    def __init__(self, model, model_name):
        super().__init__(model, model_name)

    # def prefix_allowed_tokens_fn(self, batch_id, input_ids):
    #     return self.valid_token_ids

    def __get_random_example_message(self, classification_type, **kwargs):
        return get_random_example_message_binary(classification_type=classification_type, all_entries=kwargs.get("all_entries", []), n_examples=kwargs.get("n_examples", 1))

    def __get_rag_example_message(self, text, classification_type, **kwargs):
        return get_rag_example_messages_binary(
            text=text,
            classification_type=classification_type,
            collection=kwargs.get("collection", None),
            filepath=kwargs.get("filepath", ""),
            exclude_company=kwargs.get("exclude_company", ""),
            report_distance=kwargs.get("report_distance", True),
            n_examples=kwargs.get("n_examples", 5),
            embedding=kwargs.get("embedding", None)
        )

    def __get_top_n_rag_example_message(self, text, classification_type, **kwargs):
        return get_top_n_rag_example_messages_binary(
            text=text,
            classification_type=classification_type,
            collection=kwargs.get("collection", None),
            filepath=kwargs.get("filepath", ""),
            exclude_company=kwargs.get("exclude_company", ""),
            report_distance=kwargs.get("report_distance", True),
            n_examples=kwargs.get("n_examples", 5),
            embedding=kwargs.get("embedding", None)
        )

    def get_messages(self, text, classification_type='GuV', law_context = False, random_examples = False, rag_examples = False, top_n_rag_examples = False, combine_system_prompts = False, **kwargs):
        messages = [{"role": "system", "content": "[Role and Context]: You are a helpful assistant that can classify texts extracted from PDFs."}]

        if law_context:
            if classification_type == "GuV":
                messages.append({"role": "system", "content": f"You know the laws about how to structure the 'Gewinn- und Verlustrechnung' (profit and loss statement) table:' \n\n'''\n{hgb_guv}\n'''."})
            elif classification_type == "Aktiva":
                messages.append({"role": "system", "content": f"You know the laws about how to structure the 'Aktiva' (assets) table for a 'Bilanz' (balance sheet):' \n\n'''\n{hgb_aktiva}\n'''."})
            elif classification_type == "Passiva":
                messages.append({"role": "system", "content": f"You know the laws about how to structure the 'Passiva' (liabilities) table for a 'Bilanz' (balance sheet):' \n\n'''\n{hgb_passiva}\n'''."})
            else:
                raise ValueError(f"Unknown classification type: {classification_type}. Expected 'GuV', 'Aktiva', or 'Passiva'.")

        if random_examples:
            system_messages = self.__get_random_example_message(classification_type, **kwargs)
            for msg in system_messages:
                messages.append({"role": "system", "content": msg})

        if rag_examples:
            system_messages = self.__get_rag_example_message(text, classification_type, **kwargs)
            for msg in system_messages:
                messages.append({"role": "system", "content": msg})
        
        if top_n_rag_examples:
            system_messages = self.__get_top_n_rag_example_message(text, classification_type, **kwargs)
            for msg in system_messages:
                messages.append({"role": "system", "content": msg})

        # Combine all "system" messages so far into one
        # print(f"combine_system_prompts: {combine_system_prompts}")
        if combine_system_prompts:
            system_contents = [msg["content"] for msg in messages if msg["role"] == "system"]
            if system_contents:
                combined_content = "\n\n".join(system_contents)
                # Remove all previous system messages
                messages = [msg for msg in messages if msg["role"] != "system"]
                # Add the combined system message
                messages.insert(0, {"role": "system", "content": combined_content})
        
        messages.append({"role": "user", "content": f"[Task]: Decide if the given text contains {phrase_dict[classification_type]}.\n\n[Rule]: Answer with 'yes' if it does. Otherwise answer with 'no'.\n\n[Text]: Here is the text to classify: \n\n'''\n{text}\n'''"})
        return messages

    def prepare_to_detect(self, text, classification_type, **kwargs):
        messages = self.get_messages(text, classification_type=classification_type, **kwargs)
        # print(f"\n###### Messages: #####\n\n{messages}")
        if "qwen3" in self.model_name.lower() and kwargs.get("no_think", True):
            messages[0]["content"] = "/no_think "+messages[0]["content"]
            # print(messages[0])
        # print(f"Messages: {messages}")
        # print(type(messages))

        texts = self.tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
        # If you get a list of token IDs, you can convert it back to text using the tokenizer's decode method:
        if isinstance(texts, list) and all(isinstance(x, int) for x in texts):
            # print(f"Decoding tokens...\n{texts[0:10]}")
            texts = self.tokenizer.decode(texts, skip_special_tokens=True)
            
        return texts

    def classify_batched(self, texts, **kwargs):
        guided_decoding_params = GuidedDecodingParams(choice=["no", "yes"],)
        sampling_params = SamplingParams(guided_decoding=guided_decoding_params, logprobs=1, temperature=0)

        # texts = texts[0] if isinstance(texts, list) else texts  # Ensure texts is a single string or a list of strings
        # print(type(texts))
        # print(f"Texts: {texts}")
        # print([str(text) for text in texts])
        outputs = self.model.generate(texts, sampling_params)
        # outputs = [self.model.generate(text, sampling_params) for text in texts]
        confidence_scores = []
        for output in outputs:
            # logprobs is a list of dicts, one per token; get the first token's logprob if available
            token_logprobs = output.outputs[0].logprobs[0]
            # Extract the logprob value itself (for the first token)
            logprob_value = list(token_logprobs.values())[0].logprob if token_logprobs else None
            confidence_scores.append(np.exp(logprob_value))

        results = [output.outputs[0].text for output in outputs]

        return results, confidence_scores

class FourClassStringClassifier(StringClassifier):
    def __init__(self, model, model_name):
        super().__init__(model, model_name)

    def __get_random_example_message(self, **kwargs):
        return get_random_example_message_multiclass(all_entries=kwargs.get("all_entries", []), n_examples=kwargs.get("n_examples", 1))

    def __get_rag_example_message(self, page, **kwargs):
        return get_rag_example_messages_multiclass(
            text=page,
            collection=kwargs.get("collection", None),
            filepath=kwargs.get("filepath", ""),
            exclude_company=kwargs.get("exclude_company", ""),
            report_distance=kwargs.get("report_distance", True),
            n_examples=kwargs.get("n_examples", 1),
            embedding=kwargs.get("embedding", None)
        )
    
    def __get_top_n_rag_example_message(self, page, **kwargs):
        return get_top_n_rag_example_messages_multiclass(
            text=page,
            collection=kwargs.get("collection", None),
            filepath=kwargs.get("filepath", ""),
            exclude_company=kwargs.get("exclude_company", ""),
            report_distance=kwargs.get("report_distance", True),
            n_examples=kwargs.get("n_examples", 1),
            embedding=kwargs.get("embedding", None)
        )

    def get_messages(self, text, law_context = False, random_examples = False, rag_examples = False, top_n_rag_examples = False, combine_system_prompts = False, **kwargs):
        messages = [
            {"role": "system", "content": "[Role and Context]: You are a helpful assistant that can classify texts extracted from PDFs."},
        ]

        if law_context:
            messages.append({"role": "system", "content": f"You know the laws about how to structure the 'Gewinn- und Verlustrechnung' (profit and loss statement) table:' \n\n'''\n{hgb_guv}\n'''."})
            messages.append({"role": "system", "content": f"You also know the laws about how to structure the 'Aktiva' (assets) and 'Passiva' (liabilities) table for a 'Bilanz' (balance sheet):' \n\n'''\n{hgb_bilanz}\n'''."})

        if random_examples:
            system_messages = self.__get_random_example_message(**kwargs)
            for msg in system_messages:
                messages.append({"role": "system", "content": msg})

        if rag_examples:
            system_messages = self.__get_rag_example_message(text, **kwargs)
            for msg in system_messages:
                messages.append({"role": "system", "content": msg})
        
        if top_n_rag_examples:
            system_messages = self.__get_top_n_rag_example_message(text, **kwargs)
            for msg in system_messages:
                messages.append({"role": "system", "content": msg})

        # Combine all "system" messages so far into one
        if combine_system_prompts:
            system_contents = [msg["content"] for msg in messages if msg["role"] == "system"]
            if system_contents:
                combined_content = "\n\n".join(system_contents)
                # Remove all previous system messages
                messages = [msg for msg in messages if msg["role"] != "system"]
                # Add the combined system message
                messages.insert(0, {"role": "system", "content": combined_content})

        messages.append({"role": "user", "content": f"""
        [Task]: Decide of what type the given text is. You can differentiate between four types of pages: 'Aktiva', 'GuV', 'Passiva' and 'other'.\n\n
        [Rules]:\n
            1) If the text contains a 'Gewinn- und Verlustrechnung' (profit and loss statement) table, answer with 'GuV'.\n\n
            2) If the text contains an 'Aktiva' (assets) table, answer with 'Aktiva'.\n\n
            3) If the text contains a 'Passiva' (liabilities) table, answer with 'Passiva'.\n\n
            4) If the text contains something else, answer with 'other'.\n\n
        [Text]: Here is the text to classify: \n\n'''\n{text}\n'''
        """})
        return messages

    def prepare_to_detect(self, text, **kwargs):
        messages = self.get_messages(text, **kwargs)
        # print(f"Messages: {messages}")
        if "qwen3" in self.model_name.lower() and kwargs.get("no_think", True):
            messages[0]["content"] = "/no_think "+messages[0]["content"]
            # print(messages[0])

        texts = self.tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
        # If you get a list of token IDs, you can convert it back to text using the tokenizer's decode method:
        if isinstance(texts, list) and all(isinstance(x, int) for x in texts):
            # print(f"Decoding tokens...\n{texts[0:10]}")
            texts = self.tokenizer.decode(texts, skip_special_tokens=True)

        return texts

    def classify_batched(self, texts, **kwargs):
        guided_decoding_params = GuidedDecodingParams(choice=["Aktiva", "Passiva", "GuV", "other"],)
        sampling_params = SamplingParams(guided_decoding=guided_decoding_params, logprobs=1, temperature=0)

        # outputs = self.model.generate(texts, sampling_params)
        # results = [output.outputs[0].text for output in outputs]

        outputs = self.model.generate(texts, sampling_params)
        confidence_scores = []
        for output in outputs:
            # logprobs is a list of dicts, one per token; get the first token's logprob if available
            token_logprobs = output.outputs[0].logprobs
            # print(f"token_logprobs: {token_logprobs}")
            # Extract the logprob value itself (for the first token)
            logprob_value = list(token_logprobs[0].values())[0].logprob if token_logprobs else None
            confidence_scores.append(np.exp(logprob_value))

        results = [output.outputs[0].text for output in outputs]

        return results, confidence_scores

import time
import json
import pandas as pd
import re

class PageIdentificationBenchmarkLLM:
    def __init__(self, classifier, classifier_type, verbose=False, combine_system_prompts=False):
        self.classifier = classifier
        self.classifier_type = classifier_type
        self.verbose = verbose
        self.combine_system_prompts = combine_system_prompts

    def calculate_metrics(self, df, classification_type):
        if self.classifier_type == "binary":
            metrics = {classification_type: {
                "true_positive": df[df['predicted_type'] == classification_type]['match'].sum(),
                "false_positive": df[df['predicted_type'] == classification_type]['match'].count() - df[df['predicted_type'] == classification_type]['match'].sum(),
                "false_negative": df[df['type'] == classification_type]['match'].count() - df[df['predicted_type'] == classification_type]['match'].sum(),
            }}

            metrics[classification_type]["precision"] = metrics[classification_type]["true_positive"] / (metrics[classification_type]["true_positive"] + metrics[classification_type]["false_positive"]) if (metrics[classification_type]["true_positive"] + metrics[classification_type]["false_positive"]) > 0 else 0
            metrics[classification_type]["recall"] = metrics[classification_type]["true_positive"] / (metrics[classification_type]["true_positive"] + metrics[classification_type]["false_negative"]) if (metrics[classification_type]["true_positive"] + metrics[classification_type]["false_negative"]) > 0 else 0
            metrics[classification_type]["f1_score"] = (2 * metrics[classification_type]["precision"] * metrics[classification_type]["recall"]) / (metrics[classification_type]["precision"] + metrics[classification_type]["recall"]) if (metrics[classification_type]["precision"] + metrics[classification_type]["recall"]) > 0 else 0

        elif self.classifier_type == "four_classes":
            metrics = {
                'Aktiva': {}, 
                'GuV': {},
                'other': {},
                'Passiva': {}
                }

            for key, value in metrics.items():
                value["true_positive"] = df[df['predicted_type'] == key]['match'].sum()
                value["false_positive"] = df[df['predicted_type'] == key]['match'].count() - value["true_positive"]
                value["false_negative"] = df[df['type'] == key]['match'].count() - value["true_positive"]
                value["precision"] = value["true_positive"] / (value["true_positive"] + value["false_positive"]) if (value["true_positive"] + value["false_positive"]) > 0 else 0
                value["recall"] = value["true_positive"] / (value["true_positive"] + value["false_negative"]) if (value["true_positive"] + value["false_negative"]) > 0 else 0
                value["f1_score"] = (2 * value["precision"] * value["recall"]) / (value["precision"] + value["recall"]) if (value["precision"] + value["recall"]) > 0 else 0
            
            macro_precision = sum([value['precision'] for value in metrics.values()]) / len(metrics)
            macro_recall = sum([value['recall'] for value in metrics.values()]) / len(metrics)
            macro_f1 = 2 * (macro_precision * macro_recall) / (macro_precision + macro_recall) if (macro_precision + macro_recall) > 0 else 0
            micro_precision = sum([value['true_positive'] for value in metrics.values()]) / (sum([value['true_positive'] for value in metrics.values()]) + sum([value['false_positive'] for value in metrics.values()])) if (sum([value['true_positive'] for value in metrics.values()]) + sum([value['false_positive'] for value in metrics.values()])) > 0 else 0
            micro_recall = sum([value['true_positive'] for value in metrics.values()]) / (sum([value['true_positive'] for value in metrics.values()]) + sum([value['false_negative'] for value in metrics.values()])) if (sum([value['true_positive'] for value in metrics.values()]) + sum([value['false_negative'] for value in metrics.values()])) > 0 else 0
            micro_f1 = 2 * (micro_precision * micro_recall) / (micro_precision + micro_recall) if (micro_precision + micro_recall) > 0 else 0

            metrics['aggregated'] = {
                'macro_precision': macro_precision,
                'macro_recall': macro_recall,
                'macro_f1': macro_f1,
                'micro_precision': micro_precision,
                'micro_recall': micro_recall,
                'micro_f1': micro_f1
            }

        return metrics

    def clean_text(self, text):
        # Replace sequences of whitespace and dots (longer than 5) with a tab
        text = re.sub(r'([\.\s]{5,})', '\t', text).strip()
        return text

    def classify_pages_batched(self, entries, result_dir, out_of_sample = True, **kwargs):
        classification_type = kwargs.get("classification_type", None)
        print(f'classification type: {classification_type}')
        predictions = entries.copy()
        # print(predictions)

        start_time = time.time()
        n_pdfs = len(entries)

        if kwargs['no_think']:
            # print("Using no_think mode")
            result_dir = result_dir + "__no_think"

        texts = []

        for entry in entries:
            text = self.clean_text(entry['text'])
            kwargs['embedding'] = entry['embedding']
            texts.append(self.classifier.prepare_to_detect(text, combine_system_prompts=self.combine_system_prompts, filepath=entry['filepath'], exclude_company = entry['company'] if out_of_sample else "", **kwargs))

        print(len(self.classifier.tokenizer(texts[0])['input_ids']))

        # print(texts[0])

        # # Get the max input token number from the model config if available
        # max_input_tokens = min(getattr(self.classifier.tokenizer, "model_max_length", 32768), 32768)
        # # print(f"Max input tokens for model: {max_input_tokens}")

        # texts = [text for text in texts if len(self.classifier.tokenizer(text, add_special_tokens=False)["input_ids"]) < max_input_tokens]  # Remove texts exceeding max tokens
        # token_counts = [len(self.classifier.tokenizer(text, add_special_tokens=False)["input_ids"]) for text in texts]
        # print("Token counts for each entry:", token_counts)

        results, confidence_scores = self.classifier.classify_batched(texts, **kwargs)

        end_time = time.time()
        runtime = end_time - start_time
        print(f"Total runtime: {runtime:.2f} seconds")

        df = pd.DataFrame(predictions)
        df['predicted_type'] = results
        df['confidence_score'] = confidence_scores

        if self.classifier_type == "binary":
            df['predicted_type'] = df['predicted_type'].replace({'yes': classification_type})
            # df['match'] = ((df['type'] == classification_type) & (df['predicted_type'] == classification_type)) | ((df['type'] != classification_type) & (df['predicted_type'] != classification_type))
            df['match'] = df.apply(lambda row: ((classification_type in row['type']) & (row['predicted_type'] == classification_type)) | ((classification_type not in row['type']) & (row['predicted_type'] != classification_type)), axis=1)
        if self.classifier_type == "four_classes": 
            df['match'] = df.apply(lambda row: row['predicted_type'] in row['type'], axis=1)
        df.drop(columns=['text', 'embedding'], inplace=True, errors='ignore') #'text'
        print(df[df.columns[3:]].head(12))
        
        n_request_tokens = [len(self.classifier.tokenizer(text, add_special_tokens=False)["input_ids"]) for text in texts]

        results = {"results": df, "runtime": runtime, "metrics": self.calculate_metrics(df, classification_type), 'requested_token': n_request_tokens}
        # print(f"Metrics: {results['metrics']}")

        with open(f"{result_dir}_queued.json", "w") as json_file:
            json.dump(
                {key: value.to_json(orient='records') if hasattr(value, 'to_json') else value 
                for key, value in results.items()}, 
                json_file, 
                indent=4, 
                default=str
            )

        return results


hgb_guv = '''
Handelsgesetzbuch
§ 275 Gliederung
(1) Die Gewinn- und Verlustrechnung ist in Staffelform nach dem Gesamtkostenverfahren oder dem Umsatzkostenverfahren aufzustellen. Dabei sind die in Absatz 2 oder 3 bezeichneten Posten in der angegebenen Reihenfolge gesondert auszuweisen.
(2) Bei Anwendung des Gesamtkostenverfahrens sind auszuweisen:

1.
    Umsatzerlöse
2.
    Erhöhung oder Verminderung des Bestands an fertigen und unfertigen Erzeugnissen
3.
    andere aktivierte Eigenleistungen
4.
    sonstige betriebliche Erträge
5.
    Materialaufwand:

    a)
        Aufwendungen für Roh-, Hilfs- und Betriebsstoffe und für bezogene Waren
    b)
        Aufwendungen für bezogene Leistungen

6.
    Personalaufwand:

    a)
        Löhne und Gehälter
    b)
        soziale Abgaben und Aufwendungen für Altersversorgung und für Unterstützung,
        davon für Altersversorgung

7.
    Abschreibungen:

    a)
        auf immaterielle Vermögensgegenstände des Anlagevermögens und Sachanlagen
    b)
        auf Vermögensgegenstände des Umlaufvermögens, soweit diese die in der Kapitalgesellschaft üblichen Abschreibungen überschreiten

8.
    sonstige betriebliche Aufwendungen
9.
    Erträge aus Beteiligungen,
    davon aus verbundenen Unternehmen
10.
    Erträge aus anderen Wertpapieren und Ausleihungen des Finanzanlagevermögens,
    davon aus verbundenen Unternehmen
11.
    sonstige Zinsen und ähnliche Erträge,
    davon aus verbundenen Unternehmen
12.
    Abschreibungen auf Finanzanlagen und auf Wertpapiere des Umlaufvermögens
13.
    Zinsen und ähnliche Aufwendungen,
    davon an verbundene Unternehmen
14.
    Steuern vom Einkommen und vom Ertrag
15.
    Ergebnis nach Steuern
16.
    sonstige Steuern
17.
    Jahresüberschuss/Jahresfehlbetrag.

(3) Bei Anwendung des Umsatzkostenverfahrens sind auszuweisen:

1.
    Umsatzerlöse
2.
    Herstellungskosten der zur Erzielung der Umsatzerlöse erbrachten Leistungen
3.
    Bruttoergebnis vom Umsatz
4.
    Vertriebskosten
5.
    allgemeine Verwaltungskosten
6.
    sonstige betriebliche Erträge
7.
    sonstige betriebliche Aufwendungen
8.
    Erträge aus Beteiligungen,
    davon aus verbundenen Unternehmen
9.
    Erträge aus anderen Wertpapieren und Ausleihungen des Finanzanlagevermögens,
    davon aus verbundenen Unternehmen
10.
    sonstige Zinsen und ähnliche Erträge,
    davon aus verbundenen Unternehmen
11.
    Abschreibungen auf Finanzanlagen und auf Wertpapiere des Umlaufvermögens
12.
    Zinsen und ähnliche Aufwendungen,
    davon an verbundene Unternehmen
13.
    Steuern vom Einkommen und vom Ertrag
14.
    Ergebnis nach Steuern
15.
    sonstige Steuern
16.
    Jahresüberschuss/Jahresfehlbetrag.

(4) Veränderungen der Kapital- und Gewinnrücklagen dürfen in der Gewinn- und Verlustrechnung erst nach dem Posten "Jahresüberschuß/Jahresfehlbetrag" ausgewiesen werden.
(5) Kleinstkapitalgesellschaften (§ 267a) können anstelle der Staffelungen nach den Absätzen 2 und 3 die Gewinn- und Verlustrechnung wie folgt darstellen:

1.
    Umsatzerlöse,
2.
    sonstige Erträge,
3.
    Materialaufwand,
4.
    Personalaufwand,
5.
    Abschreibungen,
6.
    sonstige Aufwendungen,
7.
    Steuern,
8.
    Jahresüberschuss/Jahresfehlbetrag.
'''

hgb_bilanz = '''
Handelsgesetzbuch
§ 266 Gliederung der Bilanz
(1) Die Bilanz ist in Kontoform aufzustellen. Dabei haben mittelgroße und große Kapitalgesellschaften (§ 267 Absatz 2 und 3) auf der Aktivseite die in Absatz 2 und auf der Passivseite die in Absatz 3 bezeichneten Posten gesondert und in der vorgeschriebenen Reihenfolge auszuweisen. Kleine Kapitalgesellschaften (§ 267 Abs. 1) brauchen nur eine verkürzte Bilanz aufzustellen, in die nur die in den Absätzen 2 und 3 mit Buchstaben und römischen Zahlen bezeichneten Posten gesondert und in der vorgeschriebenen Reihenfolge aufgenommen werden. Kleinstkapitalgesellschaften (§ 267a) brauchen nur eine verkürzte Bilanz aufzustellen, in die nur die in den Absätzen 2 und 3 mit Buchstaben bezeichneten Posten gesondert und in der vorgeschriebenen Reihenfolge aufgenommen werden.
(2) Aktivseite

A.
    Anlagevermögen:

    I.
        Immaterielle Vermögensgegenstände:

        1.
            Selbst geschaffene gewerbliche Schutzrechte und ähnliche Rechte und Werte;
        2.
            entgeltlich erworbene Konzessionen, gewerbliche Schutzrechte und ähnliche Rechte und Werte sowie Lizenzen an solchen Rechten und Werten;
        3.
            Geschäfts- oder Firmenwert;
        4.
            geleistete Anzahlungen;

    II.
        Sachanlagen:

        1.
            Grundstücke, grundstücksgleiche Rechte und Bauten einschließlich der Bauten auf fremden Grundstücken;
        2.
            technische Anlagen und Maschinen;
        3.
            andere Anlagen, Betriebs- und Geschäftsausstattung;
        4.
            geleistete Anzahlungen und Anlagen im Bau;

    III.
        Finanzanlagen:

        1.
            Anteile an verbundenen Unternehmen;
        2.
            Ausleihungen an verbundene Unternehmen;
        3.
            Beteiligungen;
        4.
            Ausleihungen an Unternehmen, mit denen ein Beteiligungsverhältnis besteht;
        5.
            Wertpapiere des Anlagevermögens;
        6.
            sonstige Ausleihungen.

B.
    Umlaufvermögen:

    I.
        Vorräte:

        1.
            Roh-, Hilfs- und Betriebsstoffe;
        2.
            unfertige Erzeugnisse, unfertige Leistungen;
        3.
            fertige Erzeugnisse und Waren;
        4.
            geleistete Anzahlungen;

    II.
        Forderungen und sonstige Vermögensgegenstände:

        1.
            Forderungen aus Lieferungen und Leistungen;
        2.
            Forderungen gegen verbundene Unternehmen;
        3.
            Forderungen gegen Unternehmen, mit denen ein Beteiligungsverhältnis besteht;
        4.
            sonstige Vermögensgegenstände;

    III.
        Wertpapiere:

        1.
            Anteile an verbundenen Unternehmen;
        2.
            sonstige Wertpapiere;

    IV.
        Kassenbestand, Bundesbankguthaben, Guthaben bei Kreditinstituten und Schecks.

C.
    Rechnungsabgrenzungsposten.
D.
    Aktive latente Steuern.
E.
    Aktiver Unterschiedsbetrag aus der Vermögensverrechnung.

(3) Passivseite

A.
    Eigenkapital:

    I.
        Gezeichnetes Kapital;
    II.
        Kapitalrücklage;
    III.
        Gewinnrücklagen:

        1.
            gesetzliche Rücklage;
        2.
            Rücklage für Anteile an einem herrschenden oder mehrheitlich beteiligten Unternehmen;
        3.
            satzungsmäßige Rücklagen;
        4.
            andere Gewinnrücklagen;

    IV.
        Gewinnvortrag/Verlustvortrag;
    V.
        Jahresüberschuß/Jahresfehlbetrag.

B.
    Rückstellungen:

    1.
        Rückstellungen für Pensionen und ähnliche Verpflichtungen;
    2.
        Steuerrückstellungen;
    3.
        sonstige Rückstellungen.

C.
    Verbindlichkeiten:

    1.
        Anleihen,
        davon konvertibel;
    2.
        Verbindlichkeiten gegenüber Kreditinstituten;
    3.
        erhaltene Anzahlungen auf Bestellungen;
    4.
        Verbindlichkeiten aus Lieferungen und Leistungen;
    5.
        Verbindlichkeiten aus der Annahme gezogener Wechsel und der Ausstellung eigener Wechsel;
    6.
        Verbindlichkeiten gegenüber verbundenen Unternehmen;
    7.
        Verbindlichkeiten gegenüber Unternehmen, mit denen ein Beteiligungsverhältnis besteht;
    8.
        sonstige Verbindlichkeiten,
        davon aus Steuern,
        davon im Rahmen der sozialen Sicherheit.

D.
    Rechnungsabgrenzungsposten.
E.
    Passive latente Steuern.
'''

hgb_aktiva = '''
Handelsgesetzbuch
§ 266 Gliederung der Bilanz
(1) Die Bilanz ist in Kontoform aufzustellen. Dabei haben mittelgroße und große Kapitalgesellschaften (§ 267 Absatz 2 und 3) auf der Aktivseite die in Absatz 2 und auf der Passivseite die in Absatz 3 bezeichneten Posten gesondert und in der vorgeschriebenen Reihenfolge auszuweisen. Kleine Kapitalgesellschaften (§ 267 Abs. 1) brauchen nur eine verkürzte Bilanz aufzustellen, in die nur die in den Absätzen 2 und 3 mit Buchstaben und römischen Zahlen bezeichneten Posten gesondert und in der vorgeschriebenen Reihenfolge aufgenommen werden. Kleinstkapitalgesellschaften (§ 267a) brauchen nur eine verkürzte Bilanz aufzustellen, in die nur die in den Absätzen 2 und 3 mit Buchstaben bezeichneten Posten gesondert und in der vorgeschriebenen Reihenfolge aufgenommen werden.
(2) Aktivseite

A.
    Anlagevermögen:

    I.
        Immaterielle Vermögensgegenstände:

        1.
            Selbst geschaffene gewerbliche Schutzrechte und ähnliche Rechte und Werte;
        2.
            entgeltlich erworbene Konzessionen, gewerbliche Schutzrechte und ähnliche Rechte und Werte sowie Lizenzen an solchen Rechten und Werten;
        3.
            Geschäfts- oder Firmenwert;
        4.
            geleistete Anzahlungen;

    II.
        Sachanlagen:

        1.
            Grundstücke, grundstücksgleiche Rechte und Bauten einschließlich der Bauten auf fremden Grundstücken;
        2.
            technische Anlagen und Maschinen;
        3.
            andere Anlagen, Betriebs- und Geschäftsausstattung;
        4.
            geleistete Anzahlungen und Anlagen im Bau;

    III.
        Finanzanlagen:

        1.
            Anteile an verbundenen Unternehmen;
        2.
            Ausleihungen an verbundene Unternehmen;
        3.
            Beteiligungen;
        4.
            Ausleihungen an Unternehmen, mit denen ein Beteiligungsverhältnis besteht;
        5.
            Wertpapiere des Anlagevermögens;
        6.
            sonstige Ausleihungen.

B.
    Umlaufvermögen:

    I.
        Vorräte:

        1.
            Roh-, Hilfs- und Betriebsstoffe;
        2.
            unfertige Erzeugnisse, unfertige Leistungen;
        3.
            fertige Erzeugnisse und Waren;
        4.
            geleistete Anzahlungen;

    II.
        Forderungen und sonstige Vermögensgegenstände:

        1.
            Forderungen aus Lieferungen und Leistungen;
        2.
            Forderungen gegen verbundene Unternehmen;
        3.
            Forderungen gegen Unternehmen, mit denen ein Beteiligungsverhältnis besteht;
        4.
            sonstige Vermögensgegenstände;

    III.
        Wertpapiere:

        1.
            Anteile an verbundenen Unternehmen;
        2.
            sonstige Wertpapiere;

    IV.
        Kassenbestand, Bundesbankguthaben, Guthaben bei Kreditinstituten und Schecks.

C.
    Rechnungsabgrenzungsposten.
D.
    Aktive latente Steuern.
E.
    Aktiver Unterschiedsbetrag aus der Vermögensverrechnung.
'''

hgb_passiva = '''
Handelsgesetzbuch
§ 266 Gliederung der Bilanz
(1) Die Bilanz ist in Kontoform aufzustellen. Dabei haben mittelgroße und große Kapitalgesellschaften (§ 267 Absatz 2 und 3) auf der Aktivseite die in Absatz 2 und auf der Passivseite die in Absatz 3 bezeichneten Posten gesondert und in der vorgeschriebenen Reihenfolge auszuweisen. Kleine Kapitalgesellschaften (§ 267 Abs. 1) brauchen nur eine verkürzte Bilanz aufzustellen, in die nur die in den Absätzen 2 und 3 mit Buchstaben und römischen Zahlen bezeichneten Posten gesondert und in der vorgeschriebenen Reihenfolge aufgenommen werden. Kleinstkapitalgesellschaften (§ 267a) brauchen nur eine verkürzte Bilanz aufzustellen, in die nur die in den Absätzen 2 und 3 mit Buchstaben bezeichneten Posten gesondert und in der vorgeschriebenen Reihenfolge aufgenommen werden.
(3) Passivseite

A.
    Eigenkapital:

    I.
        Gezeichnetes Kapital;
    II.
        Kapitalrücklage;
    III.
        Gewinnrücklagen:

        1.
            gesetzliche Rücklage;
        2.
            Rücklage für Anteile an einem herrschenden oder mehrheitlich beteiligten Unternehmen;
        3.
            satzungsmäßige Rücklagen;
        4.
            andere Gewinnrücklagen;

    IV.
        Gewinnvortrag/Verlustvortrag;
    V.
        Jahresüberschuß/Jahresfehlbetrag.

B.
    Rückstellungen:

    1.
        Rückstellungen für Pensionen und ähnliche Verpflichtungen;
    2.
        Steuerrückstellungen;
    3.
        sonstige Rückstellungen.

C.
    Verbindlichkeiten:

    1.
        Anleihen,
        davon konvertibel;
    2.
        Verbindlichkeiten gegenüber Kreditinstituten;
    3.
        erhaltene Anzahlungen auf Bestellungen;
    4.
        Verbindlichkeiten aus Lieferungen und Leistungen;
    5.
        Verbindlichkeiten aus der Annahme gezogener Wechsel und der Ausstellung eigener Wechsel;
    6.
        Verbindlichkeiten gegenüber verbundenen Unternehmen;
    7.
        Verbindlichkeiten gegenüber Unternehmen, mit denen ein Beteiligungsverhältnis besteht;
    8.
        sonstige Verbindlichkeiten,
        davon aus Steuern,
        davon im Rahmen der sozialen Sicherheit.

D.
    Rechnungsabgrenzungsposten.
E.
    Passive latente Steuern.
'''
