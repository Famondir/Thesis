import argparse

import pandas as pd
import json
import numpy as np
import re
import time
import random

import chromadb
from chromadb.utils import embedding_functions

from final_synth_table_extraction_vllm import TableTemplateFillingExtractor, TableExtractionBenchmarkLLM

import os
from huggingface_hub import login
import torch
# from transformers import AutoModelForCausalLM, AutoTokenizer, AutoConfig
from vllm import LLM, SamplingParams
import accelerate

import shutil

def main(model_name, extractor_type, test_run, n_loops, verbose, combine_system_prompts, no_think, batched, tensor_parallel_size, temperature, enforce_eager):
    global_start_time = time.time()
    
    # loading embeddings and entries
    embeddings = np.load("/pvc/thesis_benchmarks/embeddings_synthetic_tables_final_markdown.npy")

    with open("/pvc/thesis_benchmarks/markdown_texts_synthetic_tables_final.json", "r", encoding="utf-8") as f:
        pdf_texts = json.load(f)
    entries = [{"filepath": key, "text": value, "type": "Aktiva"} for key, value in pdf_texts.items()]  
        
    for i, entry in enumerate(entries):
        entry['embedding'] = embeddings[i]

    # print(entries[0])  # Print first entry to verify loading

    # loading ChromaDB client and collection
    # embedding_model_name = "BAAI/bge-m3"
    # sentence_transformer_ef = embedding_functions.SentenceTransformerEmbeddingFunction(
    #     model_name= embedding_model_name
    # )

    client = chromadb.PersistentClient(path="/pvc/thesis_benchmarks/chroma_db")
    collection = client.get_or_create_collection(
        "synthetic_tables_final_markdown", 
        # embedding_function=sentence_transformer_ef
    )

    login(token=os.environ["HUGGING_FACE_HUB_TOKEN"])

    if model_name not in ["mistralai/Mistral-Small-3.2-24B-Instruct-2506", "mistralai/Mistral-Small-3.1-24B-Instruct-2503"]:
        llm = LLM(
            model=model_name, 
            max_model_len=32768,
            tensor_parallel_size=tensor_parallel_size,
            enforce_eager=enforce_eager
        )
    else:
        llm = LLM(
            model=model_name, 
            enforce_eager=enforce_eager,
            tensor_parallel_size=tensor_parallel_size,
            tokenizer_mode="mistral", config_format="mistral", load_format="mistral",
        )
        
    extractor = TableTemplateFillingExtractor(model=llm, model_name=model_name, temperature=temperature) if extractor_type == "table_template_filling" else None
    benchmark = TableExtractionBenchmarkLLM(extractor=extractor, extractor_type=extractor_type, verbose=verbose, combine_system_prompts=combine_system_prompts)

    random.seed(42)
    if test_run:
        sample = []
        n_samples = 10  # Use 1% of the entries for the benchmark
        sample.extend(random.sample(entries, n_samples))
    else:
        sample = []
        n_samples = max(1, int(len(entries) * 0.1))  # Use 10% of the entries for the benchmark
        sample.extend(random.sample(entries, n_samples))

    # extractor.extract(sample[0]["text"], static_example=True)
    # out_of_sample = False if rag_same_company else True
    # print(f"Running benchmark with out_of_sample={out_of_sample}")

    setup_time = time.time()
    setup_duration = setup_time - global_start_time
    print(f"Total setup time: {setup_duration:.2f} seconds")

    for i in range(n_loops):
        print(f"Running loop {i+1}/{n_loops} for model {model_name} with extractor {extractor_type}")            
        for ignore_units in [True, False]:
            print(f"Running benchmark with ignore_units={ignore_units}")
            if batched:
                benchmark.extract_tables_queued(sample, ignore_units=ignore_units, result_dir="/pvc/benchmark_results/table_extraction/llm/final/synth_tables/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{extractor_type}_from_markdown"+f"__temperature_{temperature}"+("_test" if test_run else "")+f"__zero_shot__ignore_units_{ignore_units}__loop_{i}", no_think=no_think)
                # benchmark.extract_tables_queued(sample, ignore_units=ignore_units, static_example=True, result_dir="/pvc/benchmark_results/table_extraction/llm/final/synth_tables/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{extractor_type}_from_markdown"+f"__temperature_{temperature}"+("_test" if test_run else "")+f"__static_example__ignore_units_{ignore_units}__loop_{i}", no_think=no_think)
                for n_examples in [
                    1, 3#, 5
                    ]:
                    print(f"Running benchmark with n_examples={n_examples}")
                    benchmark.extract_tables_queued(sample, ignore_units=ignore_units, random_examples=True, n_examples=n_examples, all_entries=entries, result_dir="/pvc/benchmark_results/table_extraction/llm/final/synth_tables/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{extractor_type}_from_markdown"+f"__temperature_{temperature}"+("_test" if test_run else "")+f"__{n_examples}_random_examples__ignore_units_{ignore_units}__loop_{i}", no_think=no_think)
                    for out_of_sample in [
                        # False, 
                        True
                        ]:
                        print(f"Running benchmark with out_of_sample={out_of_sample}")
                        benchmark.extract_tables_queued(sample, ignore_units=ignore_units, top_n_rag_examples=True, n_examples=n_examples, collection=collection, out_of_sample=out_of_sample, result_dir="/pvc/benchmark_results/table_extraction/llm/final/synth_tables/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{extractor_type}_from_markdown"+f"__temperature_{temperature}"+("_test" if test_run else "")+f"__top_{n_examples}_rag_examples"+("_out_of_sample" if out_of_sample else "")+f"__ignore_units_{ignore_units}__loop_{i}", no_think=no_think)

    global_end_time = time.time()
    classification_time = global_end_time - setup_time
    print(f"Total classification time: {classification_time:.2f} seconds")
    print(f"Total time for benchmark: {global_end_time - global_start_time:.2f} seconds")

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
    parser.add_argument("--temperature", type=float, default=0)
    parser.add_argument("--enforce_eager", action="store_true", help="Set this flag to enable debugging")
    # parser.add_argument("--rag_same_company", action="store_true", help="Set this flag to enable RAG same company mode")
    args = parser.parse_args()
    print(f"Running benchmark with model: {args.model_name}, extractor: {args.extractor}, test_run: {args.test_run}, n_loops: {args.n_loops}, verbose: {args.verbose}, combine_system_prompts: {args.combine_system_prompts}, no_think: {args.no_think}, batched: {args.batched}, tensor_parallel_size: {args.tensor_parallel_size}, temperature: {args.temperature}, enforce_eager: {args.enforce_eager}")
    main(args.model_name, args.extractor, args.test_run, args.n_loops, args.verbose, args.combine_system_prompts, args.no_think, args.batched, args.tensor_parallel_size, args.temperature, args.enforce_eager)