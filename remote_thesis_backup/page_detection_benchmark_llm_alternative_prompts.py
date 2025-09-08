import argparse

import pandas as pd
import json
import numpy as np

import chromadb
from chromadb.utils import embedding_functions

from page_detection_llm_alternative_prompts import PageDetectionBenchmarkLLM, BinaryStringClassifier, FiveClassStringClassifier

import os
from huggingface_hub import login
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, AutoConfig

def main(model_name, classifier_type, test_run, n_loops, verbose):
    # loading embeddings and entries
    embeddings = np.load("/pvc/thesis_benchmarks/embeddings.npy")

    with open("/pvc/thesis_benchmarks/entries.json", "r", encoding="utf-8") as f:
        entries = json.load(f)    

    for i, entry in enumerate(entries):
        entry['embedding'] = embeddings[i]  

    # loading ChromaDB client and collection
    embedding_model_name = "BAAI/bge-m3"
    sentence_transformer_ef = embedding_functions.SentenceTransformerEmbeddingFunction(
        model_name= embedding_model_name
    )

    client = chromadb.PersistentClient(path="/pvc/thesis_benchmarks/chroma_db")
    collection = client.get_or_create_collection("pages", embedding_function=sentence_transformer_ef)

    login(token=os.environ["HUGGING_FACE_HUB_TOKEN"])

    # Use all available GPUs for model parallelism
    device_map = "auto"
    model = AutoModelForCausalLM.from_pretrained(
        model_name, torch_dtype=torch.float32, device_map=device_map
    )

    classifier = FiveClassStringClassifier(model, model_name) if classifier_type == "five_classes" else \
        BinaryStringClassifier(model, model_name)
    benchmark = PageDetectionBenchmarkLLM(classifier=classifier, classifier_type=classifier_type, verbose=verbose)

    if test_run:
        sample = [entry for entry in entries if entry.get("filepath") == "../Geschaeftsberichte/IBB/ibb_geschaeftsbericht_2012.pdf"]
    else:
        sample = entries

    for i in range(n_loops):
        print(f"Running loop {i+1}/{n_loops} for model {model_name} with classifier {classifier_type}")
        benchmark.classify_pages(sample, result_dir="/pvc/benchmark_results/table_detection/llm/" + model_name.replace("/", "_") + f"_alt_prompts__benchmark_{classifier_type}"+("_test" if test_run else "")+f"__zero_shot__loop_{i}")
        benchmark.classify_pages(sample, law_context=True, result_dir="/pvc/benchmark_results/table_detection/llm/" + model_name.replace("/", "_") + f"_alt_prompts__benchmark_{classifier_type}"+("_test" if test_run else "")+f"__law_context__loop_{i}")
        benchmark.classify_pages(sample, random_examples=True, all_entries=entries, result_dir="/pvc/benchmark_results/table_detection/llm/" + model_name.replace("/", "_") + f"_alt_prompts__benchmark_{classifier_type}"+("_test" if test_run else "")+f"__random_examples__loop_{i}")
        benchmark.classify_pages(sample, rag_examples=True, collection=collection, result_dir="/pvc/benchmark_results/table_detection/llm/" + model_name.replace("/", "_") + f"_alt_prompts__benchmark_{classifier_type}"+("_test" if test_run else "")+f"__rag_examples__loop_{i}")
        benchmark.classify_pages(sample, top_n_rag_examples=True, collection=collection, result_dir="/pvc/benchmark_results/table_detection/llm/" + model_name.replace("/", "_") + f"_alt_prompts__benchmark_{classifier_type}"+("_test" if test_run else "")+f"__top_n_rag_examples__loop_{i}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--model_name", type=str, default="Qwen/Qwen2.5-0.5B-Instruct")
    parser.add_argument("--classifier", type=str, default="five_classes", choices=["binary", "five_classes"],)
    parser.add_argument("--test_run", action="store_true", help="Set this flag to run a test run")
    parser.add_argument("--n_loops", type=int, default=5)
    parser.add_argument("--verbose", action="store_true", help="Set this flag to enable verbose output")
    args = parser.parse_args()
    print(f"Running benchmark with model: {args.model_name}, classifier: {args.classifier}, test_run: {args.test_run}, n_loops: {args.n_loops}, verbose: {args.verbose}")
    main(args.model_name, args.classifier, args.test_run, args.n_loops, args.verbose)