import argparse

import pandas as pd
import json
import numpy as np
import re

import chromadb
from chromadb.utils import embedding_functions

from real_table_extraction_vllm import TableTemplateFillingExtractor, TableExtractionBenchmarkLLM

import os
from huggingface_hub import login
import torch
# from transformers import AutoModelForCausalLM, AutoTokenizer, AutoConfig
from vllm import LLM, SamplingParams
import accelerate

import shutil

def gather_gold_truth():
    # Destination folder for all .xlsx files
    root_dir = "/pvc/benchmark_truth/"
    destination_folder = os.path.join(root_dir, "real_tables")
    os.makedirs(destination_folder, exist_ok=True)

    root_dir = "/pvc/benchmark_truth/real_tables/manual_download/"
    subfolders = [name for name in os.listdir(root_dir) if os.path.isdir(os.path.join(root_dir, name))]

    for subfolder in subfolders:
        subfolder_path = os.path.join(root_dir, subfolder)
        for filename in os.listdir(subfolder_path):
            if filename.endswith(".xlsx"):
                src = os.path.join(subfolder_path, filename)
                # Append subfolder name to filename
                new_filename = f"{subfolder}__{os.path.splitext(filename)[0]}.xlsx"
                dst = os.path.join(destination_folder, new_filename)
                shutil.copy2(src, dst)
                # Open the .xlsx file and save it as .csv
                xlsx_path = dst
                csv_filename = os.path.splitext(new_filename)[0] + ".csv"
                csv_path = os.path.join(destination_folder, csv_filename)
                try:
                    df = pd.read_excel(xlsx_path)
                    df.to_csv(csv_path, index=False)
                except Exception as e:
                    print(f"Failed to convert {xlsx_path} to CSV: {e}")
    
    

def main(model_name, extractor_type, test_run, n_loops, verbose, combine_system_prompts, no_think, batched, tensor_parallel_size, temperature, rag_same_company=False):
    gather_gold_truth()
    
    # loading embeddings and entries
    embeddings = np.load("/pvc/thesis_benchmarks/embeddings_real_tables.npy")

    with open("/pvc/thesis_benchmarks/pdf_texts_real_tables.json", "r", encoding="utf-8") as f:
        pdf_texts = json.load(f)
    entries = [{"filepath": key, "text": value, "type": "Aktiva", "company": key.split("/")[-2]} for key, value in pdf_texts.items()]  
        
    for i, entry in enumerate(entries):
        entry['embedding'] = embeddings[i]
        entry["filepath"] = re.sub(
            r"/pvc/benchmark_truth/real_tables/manual_download/([^/]+)/([^/]+)$",
            r"/pvc/benchmark_truth/real_tables/\1__\2",
            entry["filepath"]
        )

    # print(entries[0])  # Print first entry to verify loading

    # loading ChromaDB client and collection
    embedding_model_name = "BAAI/bge-m3"
    sentence_transformer_ef = embedding_functions.SentenceTransformerEmbeddingFunction(
        model_name= embedding_model_name
    )

    client = chromadb.PersistentClient(path="/pvc/thesis_benchmarks/chroma_db")
    collection = client.get_or_create_collection("real_tables", embedding_function=sentence_transformer_ef)

    login(token=os.environ["HUGGING_FACE_HUB_TOKEN"])

    llm = LLM(model=model_name, tensor_parallel_size=tensor_parallel_size) # if "mistral" not in model_name else LLM(model=model_name, tensor_parallel_size=tensor_parallel_size, tokenizer_mode="mistral", config_format="mistral", load_format="mistral")

    extractor = TableTemplateFillingExtractor(model=llm, model_name=model_name, temperature=temperature) if extractor_type == "table_template_filling" else None
    benchmark = TableExtractionBenchmarkLLM(extractor=extractor, extractor_type=extractor_type, verbose=verbose, combine_system_prompts=combine_system_prompts)

    if test_run:
        sample = entries[0:10]  # Use first 10 entries for test run
    else:
        sample = entries

    # extractor.extract(sample[0]["text"], static_example=True)
    out_of_sample = False if rag_same_company else True
    # print(f"Running benchmark with out_of_sample={out_of_sample}")

    for i in range(n_loops):
        print(f"Running loop {i+1}/{n_loops} for model {model_name} with extractor {extractor_type}")
        if batched:
            if out_of_sample:
                benchmark.extract_tables_queued(sample, result_dir="/pvc/benchmark_results/table_extraction/llm/real_tables/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{extractor_type}"+f"__temperature_{temperature}"+("_test" if test_run else "")+f"__zero_shot__loop_{i}", no_think=no_think)
                benchmark.extract_tables_queued(sample, static_example=True, result_dir="/pvc/benchmark_results/table_extraction/llm/real_tables/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{extractor_type}"+f"__temperature_{temperature}"+("_test" if test_run else "")+f"__static_example__loop_{i}", no_think=no_think)
                benchmark.extract_tables_queued(sample, random_examples=True, n_examples=3, all_entries=entries, result_dir="/pvc/benchmark_results/table_extraction/llm/real_tables/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{extractor_type}"+f"__temperature_{temperature}"+("_test" if test_run else "")+f"__random_examples__loop_{i}", no_think=no_think)
            benchmark.extract_tables_queued(sample, top_n_rag_examples=True, n_examples=3, collection=collection, out_of_sample=out_of_sample, result_dir="/pvc/benchmark_results/table_extraction/llm/real_tables/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{extractor_type}"+f"__temperature_{temperature}"+("_test" if test_run else "")+f"__top_n_rag_examples"+("_same_company" if rag_same_company else "")+f"__loop_{i}", no_think=no_think)
        else: 
            benchmark.extract_tables(sample, static_example=True, result_dir="/pvc/benchmark_results/table_extraction/llm/real_tables/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{extractor_type}"+f"__temperature_{temperature}"+("_test" if test_run else "")+f"__static_example__loop_{i}", no_think=no_think)
        # benchmark.extract_tables_queued(sample, static_example=True, result_dir="/pvc/benchmark_results/table_extraction/llm/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{extractor_type}"+("_test" if test_run else "")+f"__static_example__loop_{i}", no_think=no_think)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--model_name", type=str, default="Qwen/Qwen2.5-0.5B-Instruct")
    parser.add_argument("--extractor", type=str, default="table_template_filling", choices=["table_template_filling"],)
    parser.add_argument("--test_run", action="store_true", help="Set this flag to run a test run")
    parser.add_argument("--combine_system_prompts", action="store_true", help="Set this flag to run a test run")
    parser.add_argument("--n_loops", type=int, default=5)
    parser.add_argument("--verbose", action="store_true", help="Set this flag to enable verbose output")
    parser.add_argument("--no_think", action="store_true", help="Set this flag to enable no_think mode")
    parser.add_argument("--batched", action="store_true", help="Set this flag to enable batch mode")
    parser.add_argument("--tensor_parallel_size", type=int, default=1, help="Number of GPUs to use for tensor parallelism")
    parser.add_argument("--temperature", type=float, default=1.0)
    parser.add_argument("--rag_same_company", action="store_true", help="Set this flag to enable RAG same company mode")
    args = parser.parse_args()
    print(f"Running benchmark with model: {args.model_name}, extractor: {args.extractor}, test_run: {args.test_run}, n_loops: {args.n_loops}, verbose: {args.verbose}, combine_system_prompts: {args.combine_system_prompts}, no_think: {args.no_think}, batched: {args.batched}, tensor_parallel_size: {args.tensor_parallel_size}, temperature: {args.temperature}, rag_same_company: {args.rag_same_company}")
    main(args.model_name, args.extractor, args.test_run, args.n_loops, args.verbose, args.combine_system_prompts, args.no_think, args.batched, args.tensor_parallel_size, args.temperature, args.rag_same_company)