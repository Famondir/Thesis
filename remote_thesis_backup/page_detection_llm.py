from abc import ABC, abstractmethod
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, AutoConfig
from accelerate import Accelerator
import time
import json

phrase_dict = {
        "GuV": "a 'Gewinn- und Verlustrechnung' (profit and loss statement) table",
        "Aktiva": "a 'Aktiva' (assets) table",
        "Passiva": "a 'Passiva' (liabilities) table",
        "othertable": "a table that is not a 'Gewinn- und Verlustrechnung' (profit and loss statement), 'Aktiva' (assets) or 'Passiva' (liabilities)",
        "notable": "a text that does not contain a table",
        "other": "a text that does not contain any table or a table that is not a 'Gewinn- und Verlustrechnung' (profit and loss statement), 'Aktiva' (assets) or 'Passiva' (liabilities)",
    }

def get_random_example_message(all_entries, n_guv=1, n_activa=1, n_passiva=1, n_othertable=1, n_notable=1, n_other=1):
    import random

    examples = {key: [] for key in phrase_dict.keys()}
    system_messages = []

    for key, n in zip(phrase_dict.keys(), [n_guv, n_activa, n_passiva, n_othertable, n_notable, n_other]):
        examples[key] = [s.get("text") for s in random.sample([entry for entry in all_entries if entry.get("type") == key], n)]

    for key, item in examples.items():
        for example in item:
            system_messages.append(f"You know this example for {phrase_dict.get(key, 'unknown type')}: \n\n'''\n{example}\n'''.")

    return system_messages

def get_rag_example_messages(text, collection, filepath, exclude_company="", embedding=None, report_distance=True, n_guv=1, n_activa=1, n_passiva=1, n_othertable=1, n_notable=1, n_other=1):
    examples = {key: [] for key in phrase_dict.keys()}
    system_messages = []

    # Embed the text only once
    if embedding is not None:
        embedded_text = embedding
    else:
        # Use the sentence_transformer_ef to embed the text
        embedded_text = sentence_transformer_ef([text])

    # Now use the embedded_text in all queries
    for key, n in zip(phrase_dict.keys(), [n_guv, n_activa, n_passiva, n_othertable, n_notable, n_other]):
        if n>0:
            examples[key] = collection.query(
                query_embeddings=embedded_text,
                n_results=n,
                where={"$and": [{"company": {"$ne": exclude_company}}, {"type": key}, {"filepath": {"$ne": filepath}}]}
            )

    for key, rag_examples in examples.items():
        if rag_examples:  # Check if there are any examples for this type
            for example, meta_data, distance in zip(rag_examples['documents'][0], rag_examples['metadatas'][0], rag_examples['distances'][0]):
                system_messages.append(
                    f"You know this example for {phrase_dict.get(key, 'unknown type')}: \n\n'''\n{example}\n'''." + 
                    (f" (The L2 distance of this example text is: {round(distance, 3)})" if report_distance else "")
                )
        
    return system_messages

def get_top_n_rag_example_messages(text, collection, filepath, exclude_company="", embedding=None, report_distance=True, n_examples=5):
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
        system_messages.append(
            f"You know this example for {phrase_dict.get(meta_data.get('type'), 'unknown type')}: \n\n'''\n{example}\n'''." + 
            (f" (The L2 distance of this example text is: {round(distance, 3)})" if report_distance else "")
        )

    return system_messages

class StringClassifier(ABC):
    def __init__(self, model, model_name):
        self.model_name = model_name
        self.model = model
        self.tokenizer = AutoTokenizer.from_pretrained(model_name)
        self.config = AutoConfig.from_pretrained(model_name)

    @abstractmethod
    def classify(self, text):
        pass

class BinaryStringClassifier(StringClassifier):
    def __init__(self, model, model_name):
        super().__init__(model, model_name)
        self.valid_token_ids = [
            self.tokenizer("no", add_special_tokens=False)["input_ids"][0],
            self.tokenizer("yes", add_special_tokens=False)["input_ids"][0]
        ]

        # Initialize the Accelerator
        self.accelerator = Accelerator(mixed_precision="bf16")  # Use bf16 for reduced VRAM usage

        # Prepare the model and tokenizer with Accelerate
        self.model, self.tokenizer = self.accelerator.prepare(self.model, self.tokenizer)

    def prefix_allowed_tokens_fn(self, batch_id, input_ids):
        return self.valid_token_ids

    def __get_random_example_message(self, **kwargs):
        return get_random_example_message(all_entries=kwargs.get("all_entries", []), n_guv=3, n_activa=1, n_passiva=1, n_othertable=0, n_notable=0, n_other=1)

    def __get_rag_example_message(self, text, **kwargs):
        return get_rag_example_messages(
            text=text,
            collection=kwargs.get("collection", None),
            filepath=kwargs.get("filepath", ""),
            exclude_company=kwargs.get("exclude_company", ""),
            report_distance=kwargs.get("report_distance", True),
            n_guv=kwargs.get("n_guv", 1),
            n_activa=kwargs.get("n_activa", 1),
            n_passiva=kwargs.get("n_passiva", 1),
            n_othertable=kwargs.get("n_othertable", 0),
            n_notable=kwargs.get("n_notable", 0),
            n_other=kwargs.get("n_other", 1),
            embedding=kwargs.get("embedding", None)
        )

    def __get_top_n_rag_example_message(self, text, **kwargs):
        return get_top_n_rag_example_messages(
            text=text,
            collection=kwargs.get("collection", None),
            filepath=kwargs.get("filepath", ""),
            exclude_company=kwargs.get("exclude_company", ""),
            report_distance=kwargs.get("report_distance", True),
            n_examples=kwargs.get("n_examples", 3),
            embedding=kwargs.get("embedding", None)
        )

    def get_messages(self, text, law_context = False, random_examples = False, rag_examples = False, top_n_rag_examples = False, combine_system_prompts = False, **kwargs):
        messages = [{"role": "system", "content": "You are a helpful assistant that can classify texts extracted from PDFs."}]

        if law_context:
            messages.append({"role": "system", "content": f"You know the laws about how to structure the 'Gewinn- und Verlustrechnung' (profit and loss statement) table:' \n\n'''\n{hgb_guv}\n'''."})

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

        messages.append({"role": "user", "content": f"Bewerte, ob der folgende Text die Tabelle zur 'Gewinn- und Verlustrechnung' (profit and loss statement) enthält: \n\n'''\n{text}\n'''."})
        return messages

    def prepare_messages(self, text, **kwargs):
        messages = self.get_messages(text, **kwargs)
        if "qwen3" in self.model_name.lower() and kwargs.get("no_think", True):
            messages[0]["content"] = "/no_think "+messages[0]["content"]
            # print(messages[0])
        total_tokens = sum(len(self.tokenizer(msg["content"], add_special_tokens=False)["input_ids"]) for msg in messages)
        # print(f"Total tokens in all messages: {total_tokens}")
        texts = self.tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
        return texts, total_tokens

    def classify(self, texts, **kwargs):
        model_inputs = self.tokenizer(
            texts, return_tensors="pt", 
            # padding=True, 
            padding='longest'
            # truncation=True
            ).to(self.accelerator.device)#.to(self.model.device)

        generated_ids = self.model.generate(
            **model_inputs,
            max_new_tokens=1,
            prefix_allowed_tokens_fn=self.prefix_allowed_tokens_fn,
            pad_token_id=self.tokenizer.eos_token_id
        )

        result = [self.tokenizer.decode(id[-1], skip_special_tokens=True) for id in generated_ids]
        # print(f"page {start+i}: {result}")
        return result

class FiveClassStringClassifier(StringClassifier):
    def __init__(self, model, model_name):
        super().__init__(model, model_name)
        self.valid_token_ids = [
            self.tokenizer("Aktiva", add_special_tokens=False)["input_ids"][0],
            self.tokenizer("GuV", add_special_tokens=False)["input_ids"][0],
            self.tokenizer("notable", add_special_tokens=False)["input_ids"][0],
            # self.tokenizer("othertable", add_special_tokens=False)["input_ids"][0],
            self.tokenizer("other", add_special_tokens=False)["input_ids"][0],
            self.tokenizer("Passiva", add_special_tokens=False)["input_ids"][0]
        ]

        # Initialize the Accelerator
        self.accelerator = Accelerator(mixed_precision="bf16")  # Use bf16 for reduced VRAM usage

        # Prepare the model and tokenizer with Accelerate
        self.model, self.tokenizer = self.accelerator.prepare(self.model, self.tokenizer)


    def prefix_allowed_tokens_fn(self, batch_id, input_ids):
        return self.valid_token_ids

    def __get_random_example_message(self, **kwargs):
        return get_random_example_message(all_entries=kwargs.get("all_entries", []), n_guv=1, n_activa=1, n_passiva=1, n_othertable=0, n_notable=0, n_other=1)

    def __get_rag_example_message(self, page, **kwargs):
        return get_rag_example_messages(
            text=page,
            collection=kwargs.get("collection", None),
            filepath=kwargs.get("filepath", ""),
            exclude_company=kwargs.get("exclude_company", ""),
            report_distance=kwargs.get("report_distance", True),
            n_guv=kwargs.get("n_guv", 1),
            n_activa=kwargs.get("n_activa", 1),
            n_passiva=kwargs.get("n_passiva", 1),
            n_othertable=kwargs.get("n_othertable", 0),
            n_notable=kwargs.get("n_notable", 0),
            n_other=kwargs.get("n_other", 1),
            embedding=kwargs.get("embedding", None)
        )
    
    def __get_top_n_rag_example_message(self, page, **kwargs):
        return get_top_n_rag_example_messages(
            text=page,
            collection=kwargs.get("collection", None),
            filepath=kwargs.get("filepath", ""),
            exclude_company=kwargs.get("exclude_company", ""),
            report_distance=kwargs.get("report_distance", True),
            n_examples=kwargs.get("n_examples", 3),
            embedding=kwargs.get("embedding", None)
        )

    def get_messages(self, text, law_context = False, random_examples = False, rag_examples = False, top_n_rag_examples = False, combine_system_prompts = False, **kwargs):
        messages = [
            # {"role": "system", "content": "You are a helpful assistant that can classify texts extracted from PDFs. You can differentiate between those four categories: 'Aktiva', 'GuV', 'other', and 'Passiva'."},
            {"role": "system", "content": "You are a helpful assistant that can classify texts extracted from PDFs. You can differentiate between those five categories: 'Aktiva', 'GuV', 'notable', 'othertable', and 'Passiva'."},
            # {"role": "system", "content": """
            # 1) Wenn der vorliegende Text eine Tabelle zur 'Gewinn- und Verlustrechnung' (profit and loss statement) enthält, antworte mit 'GuV'.\n\n
            # 2) Wenn der Text eine zur Bilanz (balance sheet) gehörige Tabelle zu 'Aktiva' (assets) enthält, antworte mit 'Aktiva'.\n\n
            # 3) Wenn der Text eine zur Bilanz (balance sheet) gehörige Tabelle zu 'Passiva' (liabilities) enthält, antworte mit 'Passiva'.\n\n
            # 4) Wenn der Text eine Tabelle enthält, die weder 'Aktiva', 'Passiva' noch eine 'Gewinn- und Verlustrechnung' (GuV) enthält, antworte mit 'othertable'.\n\n
            # 5) Wenn der Text keine Tabelle enthält, antworte mit 'notable'.
            # """} # 4) Wenn der Text eine andere Tabelle enthält, antworte mit 'othertable'.\n\n
        ]
        # messages.append({"role": "system", "content": f"""
        # [Task]: Decide of what type the given text is. You can differentiate between four types of pages: 'Aktiva', 'GuV', 'Passiva' and 'other'.\n\n
        # [Rules]:\n
        #     1) If the text contains a 'Gewinn- und Verlustrechnung' (profit and loss statement) table, answer with 'GuV'.\n\n
        #     2) If the text contains an 'Aktiva' (assets) table, answer with 'Aktiva'.\n\n
        #     3) If the text contains a 'Passiva' (liabilities) table, answer with 'Passiva'.\n\n
        #     4) If the text contains a table that is not an 'Aktiva' (assets), 'Passiva' (liabilities) or 'Gewinn- und Verlustrechnung' (GuV) table, answer with 'othertable'.\n\n
        #     5) If the text contains something else, answer with 'other'.\n\n
        #     'Aktiva' (assets) and 'Passiva' (liabilities) tables are part of a 'Bilanz' (balance sheet).\n\n
        # """}) # [Text]: Here is the text to classify: \n\n'''\n{text}\n'''

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

        # messages.append({"role": "system", "content": f"""
        # [Task]: Decide of what type the given text is. You can differentiate between four types of pages: 'Aktiva', 'GuV', 'Passiva' and 'other'.\n\n
        # [Rules]:\n
        #     1) If the text contains a 'Gewinn- und Verlustrechnung' (profit and loss statement) table, answer with 'GuV'.\n\n
        #     2) If the text contains an 'Aktiva' (assets) table, answer with 'Aktiva'.\n\n
        #     3) If the text contains a 'Passiva' (liabilities) table, answer with 'Passiva'.\n\n
        #     4) If the text contains a table that is not an 'Aktiva' (assets), 'Passiva' (liabilities) or 'Gewinn- und Verlustrechnung' (GuV) table, answer with 'othertable'.\n\n
        #     5) If the text contains something else, answer with 'other'.\n\n
        #     'Aktiva' (assets) and 'Passiva' (liabilities) tables are part of a 'Bilanz' (balance sheet).\n\n
        # """}) # [Text]: Here is the text to classify: \n\n'''\n{text}\n'''

        # Combine all "system" messages so far into one
        if combine_system_prompts:
            system_contents = [msg["content"] for msg in messages if msg["role"] == "system"]
            if system_contents:
                combined_content = "\n\n".join(system_contents)
                # Remove all previous system messages
                messages = [msg for msg in messages if msg["role"] != "system"]
                # Add the combined system message
                messages.insert(0, {"role": "system", "content": combined_content})

        # messages.append({"role": "user", "content": f"Bestimme, was der folgende Text repräsentiert:' \n\n'''\n{text}\n'''."})
        # messages.append({"role": "user", "content": f"[Text]: Here is the text to classify: \n\n'''\n{text}\n'''."})
        # messages.append({"role": "user", "content": f"""
        # [Task]: Decide of what type the given text is. You can differentiate between four types of pages: 'Aktiva', 'GuV', 'Passiva' and 'other'.\n\n
        # [Rules]:\n
        #     1) If the text contains a 'Gewinn- und Verlustrechnung' (profit and loss statement) table, answer with 'GuV'.\n\n
        #     2) If the text contains an 'Aktiva' (assets) table, answer with 'Aktiva'.\n\n
        #     3) If the text contains a 'Passiva' (liabilities) table, answer with 'Passiva'.\n\n
        #     4) If the text contains something else, answer with 'other'.\n\n
        # [Text]: Here is the text to classify: \n\n'''\n{text}\n'''
        # """})
        messages.append({"role": "user", "content": f"""
        [Task]: Decide of what type the given text is. You can differentiate between four types of pages: 'Aktiva', 'GuV', 'Passiva' and 'other'.\n\n
        [Rules]:\n
            1) If the text contains a 'Gewinn- und Verlustrechnung' (profit and loss statement) table, answer with 'GuV'.\n\n
            2) If the text contains an 'Aktiva' (assets) table, answer with 'Aktiva'.\n\n
            3) If the text contains a 'Passiva' (liabilities) table, answer with 'Passiva'.\n\n
            4) If the text contains a table that is not an 'Aktiva' (assets), 'Passiva' (liabilities) or 'Gewinn- und Verlustrechnung' (GuV) table, answer with 'othertable'.\n\n
            5) If the text contains no table, answer 'notable'.\n\n
        [Text]: Here is the text to classify: \n\n'''\n{text}\n'''
        """})
        return messages

    def prepare_messages(self, text, **kwargs):
        messages = self.get_messages(text, **kwargs)
        if "qwen3" in self.model_name.lower() and kwargs.get("no_think", True):
            messages[0]["content"] = "/no_think "+messages[0]["content"]
            # print(messages[0])
        total_tokens = sum(len(self.tokenizer(msg["content"], add_special_tokens=False)["input_ids"]) for msg in messages)
        # print(f"Total tokens in all messages: {total_tokens}")
        texts = self.tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
        return texts, total_tokens

    def classify(self, texts, **kwargs):  
        model_inputs = self.tokenizer(
            texts, return_tensors="pt", 
            # padding=True, 
            padding='longest'
            # truncation=True
            ).to(self.accelerator.device)#.to(self.model.device)

        generated_ids = self.model.generate(
            **model_inputs,
            max_new_tokens=1,
            prefix_allowed_tokens_fn=self.prefix_allowed_tokens_fn,
            pad_token_id=self.tokenizer.eos_token_id
        )

        # print(f"Generated IDs: {generated_ids}")
        result = [self.tokenizer.decode(id[-1], skip_special_tokens=True) for id in generated_ids]
        # print(f"page {start+i}: {result}")
        # print(result)
        return result

import time
import json
import pandas as pd
import re

class PageDetectionBenchmarkLLM:
    def __init__(self, classifier, classifier_type, verbose=False, combine_system_prompts=False):
        self.classifier = classifier
        self.classifier_type = classifier_type
        self.verbose = verbose
        self.combine_system_prompts = combine_system_prompts

    def calculate_metrics(self, df):
        if self.classifier_type == "binary":
            metrics = {'GuV': {
                "true_positive": df[df['predicted_type'] == 'GuV']['match'].sum(),
                "false_positive": df[df['predicted_type'] == 'GuV']['match'].count() - df[df['predicted_type'] == 'GuV']['match'].sum(),
                "false_negative": df[df['type'] == 'GuV']['match'].count() - df[df['predicted_type'] == 'GuV']['match'].sum(),
            }}

            metrics['GuV']["precision"] = metrics['GuV']["true_positive"] / (metrics['GuV']["true_positive"] + metrics['GuV']["false_positive"]) if (metrics['GuV']["true_positive"] + metrics['GuV']["false_positive"]) > 0 else 0
            metrics['GuV']["recall"] = metrics['GuV']["true_positive"] / (metrics['GuV']["true_positive"] + metrics['GuV']["false_negative"]) if (metrics['GuV']["true_positive"] + metrics['GuV']["false_negative"]) > 0 else 0
            metrics['GuV']["f1_score"] = (2 * metrics['GuV']["precision"] * metrics['GuV']["recall"]) / (metrics['GuV']["precision"] + metrics['GuV']["recall"]) if (metrics['GuV']["precision"] + metrics['GuV']["recall"]) > 0 else 0

        elif self.classifier_type == "five_classes":
            metrics = {'Aktiva': {}, 'GuV': {}, 'notable': {}, 'othertable': {}, 'Passiva': {}}

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

    def classify_pages(self, entries, result_dir, out_of_sample=True, **kwargs):
        predictions = entries.copy()

        start_time = time.time()
        counter = 0
        n_pdfs = len(entries)

        if kwargs['no_think']:
            # print("Using no_think mode")
            result_dir = result_dir + "__no_think"

        texts = []
        for entry in entries:
            counter += 1

            text = self.clean_text(entry['text'])
            if self.verbose:
                print(f"Preprocessing page {counter}/{n_pdfs} ...", end='\r')
            if 'embedding' in entry:
                kwargs['embedding'] = entry['embedding']

            text, total_tokens = self.classifier.prepare_messages(text, exclude_company = entry['company'] if out_of_sample else "", filepath=entry['filepath'], combine_system_prompts=self.combine_system_prompts, **kwargs)
            texts.append(text)

        # print(texts[0])

        # Process texts in batches of 16
        batch_size = 16 # 32 if two b200
        predicted_classes = []
        for i in range(0, len(texts), batch_size):
            print(f"Classifying pages {i + 1} to {min(i + batch_size, len(texts))} from {n_pdfs}...", end='\r')
            batch = texts[i:i + batch_size]
            batch_predicted_classes = self.classifier.classify(
                texts=batch,
                exclude_company=entry['company'] if out_of_sample else "",
                filepath=entry['filepath'],
                combine_system_prompts=self.combine_system_prompts,
                **kwargs
            )
            predicted_classes.extend(batch_predicted_classes)

        end_time = time.time()
        runtime = end_time - start_time
        print(f"Total runtime: {runtime:.2f} seconds")

        df = pd.DataFrame(predictions)
        df['predicted_type'] = predicted_classes
        print(predicted_classes)
        # print(df[df.columns[3:]].head(30))

        # Map shorthand predictions to full class names
        df['predicted_type'] = df['predicted_type'].replace({
            'Akt': 'Aktiva',
            'Gu': 'GuV',
            'Pass': 'Passiva',
            # 'not': 'notable',
            # 'oth': 'othertable',
            'not': 'other',
            'oth': 'other'
        })

        # Handle binary classification
        if self.classifier_type == "binary":
            df['predicted_type'] = df['predicted_type'].replace({'yes': 'GuV'})
            df['match'] = ((df['type'] == 'GuV') & (df['predicted_type'] == 'GuV')) | \
                          ((df['type'] != 'GuV') & (df['predicted_type'] != 'GuV'))

        # Handle five-class classification
        if self.classifier_type == "five_classes":
            df['match'] = df['predicted_type'] == df['type']

        # Drop unnecessary columns
        df.drop(columns=['text', 'embedding'], inplace=True, errors='ignore')

        # Print a preview of the DataFrame
        print(df[df.columns[3:]].head(30))

        results = {"results": df, "runtime": runtime, "metrics": self.calculate_metrics(df)}

        with open(f"{result_dir}.json", "w") as json_file:
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
