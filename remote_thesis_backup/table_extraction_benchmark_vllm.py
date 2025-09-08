import argparse

import pandas as pd
import json
import numpy as np

import chromadb
from chromadb.utils import embedding_functions

from table_extraction_vllm import TableTemplateFillingExtractor, TableExtractionBenchmarkLLM

import os
from huggingface_hub import login
import torch
# from transformers import AutoModelForCausalLM, AutoTokenizer, AutoConfig
from vllm import LLM, SamplingParams
import accelerate

def main(model_name, extractor_type, test_run, n_loops, verbose, combine_system_prompts, no_think, batched, tensor_parallel_size, temperature):
    # loading embeddings and entries
    embeddings = np.load("/pvc/thesis_benchmarks/embeddings_synthetic_tables.npy")

    with open("/pvc/thesis_benchmarks/pdf_texts_synthetic_tables.json", "r", encoding="utf-8") as f:
        pdf_texts = json.load(f)
    entries = [{"filepath": key, "text": value, "type": "Aktiva"} for key, value in pdf_texts.items()]  

    for i, entry in enumerate(entries):
        entry['embedding'] = embeddings[i]

    # print(entries[0])  # Print first entry to verify loading

    # loading ChromaDB client and collection
    embedding_model_name = "BAAI/bge-m3"
    sentence_transformer_ef = embedding_functions.SentenceTransformerEmbeddingFunction(
        model_name= embedding_model_name
    )

    client = chromadb.PersistentClient(path="/pvc/thesis_benchmarks/chroma_db")
    collection = client.get_or_create_collection("synthetic_tables", embedding_function=sentence_transformer_ef)

    login(token=os.environ["HUGGING_FACE_HUB_TOKEN"])

    llm = LLM(model=model_name, tensor_parallel_size=tensor_parallel_size)

    extractor = TableTemplateFillingExtractor(model=llm, model_name=model_name, temperature=temperature) if extractor_type == "table_template_filling" else None
    benchmark = TableExtractionBenchmarkLLM(extractor=extractor, extractor_type=extractor_type, verbose=verbose, combine_system_prompts=combine_system_prompts)

    if test_run:
        sample = entries[0:10]  # Use first 10 entries for test run
    else:
        sample = entries

    # extractor.extract(sample[0]["text"], static_example=True)

    for i in range(n_loops):
        print(f"Running loop {i+1}/{n_loops} for model {model_name} with extractor {extractor_type}")
        if batched:
            benchmark.extract_tables_queued(sample, result_dir="/pvc/benchmark_results/table_extraction/llm/synth_tables/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{extractor_type}"+f"__temperature_{temperature}"+("_test" if test_run else "")+f"__zero_shot__loop_{i}", no_think=no_think)
            benchmark.extract_tables_queued(sample, static_example=True, result_dir="/pvc/benchmark_results/table_extraction/llm/synth_tables/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{extractor_type}"+f"__temperature_{temperature}"+("_test" if test_run else "")+f"__static_example__loop_{i}", no_think=no_think)
            benchmark.extract_tables_queued(sample, random_examples=True, n_examples=3, all_entries=entries, result_dir="/pvc/benchmark_results/table_extraction/llm/synth_tables/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{extractor_type}"+f"__temperature_{temperature}"+("_test" if test_run else "")+f"__random_examples__loop_{i}", no_think=no_think)
            benchmark.extract_tables_queued(sample, top_n_rag_examples=True, n_examples=3, collection=collection, result_dir="/pvc/benchmark_results/table_extraction/llm/synth_tables/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{extractor_type}"+f"__temperature_{temperature}"+("_test" if test_run else "")+f"__top_n_rag_examples__loop_{i}", no_think=no_think)
        else: 
            benchmark.extract_tables(sample, static_example=True, result_dir="/pvc/benchmark_results/table_extraction/llm/synth_tables/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{extractor_type}"+f"__temperature_{temperature}"+("_test" if test_run else "")+f"__static_example__loop_{i}", no_think=no_think)

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
    args = parser.parse_args()
    print(f"Running benchmark with model: {args.model_name}, extractor: {args.extractor}, test_run: {args.test_run}, n_loops: {args.n_loops}, verbose: {args.verbose}, combine_system_prompts: {args.combine_system_prompts}, no_think: {args.no_think}, batched: {args.batched}, tensor_parallel_size: {args.tensor_parallel_size}, temperature: {args.temperature}")
    main(args.model_name, args.extractor, args.test_run, args.n_loops, args.verbose, args.combine_system_prompts, args.no_think, args.batched, args.tensor_parallel_size, args.temperature)