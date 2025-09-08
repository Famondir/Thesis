import argparse

import pandas as pd
import json
import numpy as np

import chromadb
from chromadb.utils import embedding_functions

from final_page_identification_vllm import PageIdentificationBenchmarkLLM, BinaryStringClassifier, FourClassStringClassifier

import os
from huggingface_hub import login
import torch
# from transformers import AutoModelForCausalLM, AutoTokenizer, AutoConfig
from vllm import LLM, SamplingParams
import accelerate
import random
import time


def main(model_name, classifier_type, test_run, n_loops, verbose, combine_system_prompts, no_think, tensor_parallel_size, batched, enforce_eager):
    global_start_time = time.time()
    
    # os.environ["VLLM_ALLOW_LONG_MAX_MODEL_LEN"] = "1"
    
    # loading embeddings and entries
    embeddings = np.load("/pvc/thesis_benchmarks/embeddings_all_pages.npy")

    with open("/pvc/thesis_benchmarks/all_pages_classified.json", "r", encoding="utf-8") as f:
        entries = json.load(f)

    if test_run:
        all_types = set([entry['type'] for entry in entries])
        random.seed(42)
        sample = []
        for t in all_types:
            entries_of_type = [entry for entry in entries if entry['type'] == t]
            sample.extend(random.sample(entries_of_type, 3))
        print([s['type'] for s in sample])
    else:
        sample = entries

    for i, entry in enumerate(entries):
        entry['embedding'] = embeddings[i]  

    # loading ChromaDB client and collection
    embedding_model_name = "BAAI/bge-m3"
    sentence_transformer_ef = embedding_functions.SentenceTransformerEmbeddingFunction(
        model_name= embedding_model_name
    )

    client = chromadb.PersistentClient(path="/pvc/thesis_benchmarks/chroma_db")
    collection = client.get_or_create_collection("all_pages", embedding_function=sentence_transformer_ef)

    login(token=os.environ["HUGGING_FACE_HUB_TOKEN"])

    # Use all available GPUs for model parallelism
    # device_map = "auto"
    # model = AutoModelForCausalLM.from_pretrained(
    #     model_name, torch_dtype=torch.float32, device_map=device_map
    # )
    # llm = LLM(
    #         model=model_name, 
    #         tensor_parallel_size=tensor_parallel_size,
    #         max_model_len=32768
    #         # trust_remote_code=True,
    #         # tokenizer_mode="mistral", config_format="mistral", load_format="mistral"
    #     )
    if model_name not in ["mistralai/Mistral-Small-3.2-24B-Instruct-2506", "mistralai/Mistral-Small-3.1-24B-Instruct-2503"]:
        llm = LLM(
            model=model_name, 
            tensor_parallel_size=tensor_parallel_size,
            # max_model_len=16384,
            max_model_len=32768,
            enforce_eager=enforce_eager,
            # task="classify",
            # dtype="bfloat16",
            # tokenizer_mode="auto"
            # trust_remote_code=True,
            # tokenizer_mode="mistral", config_format="mistral", load_format="mistral"
        )
    else:
        llm = LLM(
            model=model_name, 
            enforce_eager=enforce_eager,
            tensor_parallel_size=tensor_parallel_size,
            tokenizer_mode="mistral", config_format="mistral", load_format="mistral",
        )

    classifier = FourClassStringClassifier(llm, model_name) if classifier_type == "four_classes" else \
        BinaryStringClassifier(llm, model_name)
    benchmark = PageIdentificationBenchmarkLLM(classifier=classifier, classifier_type=classifier_type, verbose=verbose, combine_system_prompts=combine_system_prompts)

    classifying_function = benchmark.classify_pages if not batched else benchmark.classify_pages_batched

    setup_time = time.time()
    setup_duration = setup_time - global_start_time
    print(f"Total setup time: {setup_duration:.2f} seconds")

    for i in range(n_loops):
        print(f"Running loop {i+1}/{n_loops} for model {model_name} with classifier {classifier_type}")
        if classifier_type == "four_classes":
            # classifying_function(sample, result_dir="/pvc/benchmark_results/page_identification/final/llm/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{classifier_type}"+("_test" if test_run else "")+f"__zero_shot__loop_{i}", no_think=no_think)
            # classifying_function(sample, law_context=True, result_dir="/pvc/benchmark_results/page_identification/final/llm/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{classifier_type}"+("_test" if test_run else "")+f"__law_context__loop_{i}", no_think=no_think)
            for n_examples in [
                # 1, 
                # 2, 
                3, 
                # 5,
                # 7, 9, 11, 13
                ]:
                print(f"Running classification with {n_examples} examples")
                classifying_function(sample, random_examples=True, n_examples=n_examples, all_entries=entries, result_dir="/pvc/benchmark_results/page_identification/final/llm/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{classifier_type}"+("_test" if test_run else "")+f"__{n_examples}_random_examples__loop_{i}", no_think=no_think)
                for out_of_sample in [True, False]:
                    print(f"Running classification with {n_examples} examples and out_of_sample={out_of_sample}")
                    classifying_function(sample, rag_examples=True, n_examples=n_examples, collection=collection, out_of_sample=out_of_sample, result_dir="/pvc/benchmark_results/page_identification/final/llm/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{classifier_type}"+("_test" if test_run else "")+f"__{n_examples}_rag_examples"+("_out_of_company" if out_of_sample else "")+f"__loop_{i}", no_think=no_think)
                    classifying_function(sample, top_n_rag_examples=True, n_examples=n_examples, collection=collection, out_of_sample=out_of_sample, result_dir="/pvc/benchmark_results/page_identification/final/llm/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{classifier_type}"+("_test" if test_run else "")+f"__top_{n_examples}_rag_examples"+("_out_of_company" if out_of_sample else "")+f"__loop_{i}", no_think=no_think)
        else:
            chosen_classes = [
                "Aktiva", 
                "Passiva", 
                "GuV"
            ]
            for classification_type in chosen_classes:
                print(f"Running classification for {classification_type}")
                # classifying_function(sample, classification_type=classification_type, result_dir="/pvc/benchmark_results/page_identification/final/llm/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{classifier_type}_{classification_type}"+("_test" if test_run else "")+f"__zero_shot__loop_{i}", no_think=no_think)
                # classifying_function(sample, classification_type=classification_type, law_context=True, result_dir="/pvc/benchmark_results/page_identification/final/llm/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{classifier_type}_{classification_type}"+("_test" if test_run else "")+f"__law_context__loop_{i}", no_think=no_think)
                for n_examples in [
                    # 1, 
                    # 2, 
                    3, 
                    # 5, 
                    # 7, 9,
                    # 11, 13
                    ]:
                    print(f"Running classification for {classification_type} with {n_examples} examples")
                    classifying_function(sample, classification_type=classification_type, random_examples=True, n_examples=n_examples, all_entries=entries, result_dir="/pvc/benchmark_results/page_identification/final/llm/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{classifier_type}_{classification_type}"+("_test" if test_run else "")+f"__{n_examples}_random_examples__loop_{i}", no_think=no_think)
                    for out_of_sample in [True, False]:
                        print(f"Running classification for {classification_type} with {n_examples} examples and out_of_sample={out_of_sample}")
                        classifying_function(sample, classification_type=classification_type, rag_examples=True, n_examples=n_examples, collection=collection, out_of_sample=out_of_sample, result_dir="/pvc/benchmark_results/page_identification/final/llm/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{classifier_type}_{classification_type}"+("_test" if test_run else "")+f"__{n_examples}_rag_examples"+("_out_of_company" if out_of_sample else "")+f"__loop_{i}", no_think=no_think)
                        classifying_function(sample, classification_type=classification_type, top_n_rag_examples=True, n_examples=n_examples, collection=collection, out_of_sample=out_of_sample, result_dir="/pvc/benchmark_results/page_identification/final/llm/" + model_name.replace("/", "_") +"_vllm"+ f"__benchmark_{classifier_type}_{classification_type}"+("_test" if test_run else "")+f"__top_{n_examples}_rag_examples"+("_out_of_company" if out_of_sample else "")+f"__loop_{i}", no_think=no_think)

    global_end_time = time.time()
    classification_time = global_end_time - setup_time
    print(f"Total classification time: {classification_time:.2f} seconds")
    print(f"Total time for benchmark: {global_end_time - global_start_time:.2f} seconds")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--model_name", type=str, default="Qwen/Qwen2.5-0.5B-Instruct")
    parser.add_argument("--classifier", type=str, default="binary", choices=["binary", "four_classes"],)
    parser.add_argument("--test_run", action="store_true", help="Set this flag to run a test run")
    parser.add_argument("--combine_system_prompts", action="store_true", help="Set this flag to run a test run")
    parser.add_argument("--n_loops", type=int, default=5)
    parser.add_argument("--verbose", action="store_true", help="Set this flag to enable verbose output")
    parser.add_argument("--no_think", action="store_true", help="Set this flag to enable no_think mode")
    parser.add_argument("--batched", action="store_true", help="Set this flag to enable batch mode")
    parser.add_argument("--tensor_parallel_size", type=int, default=1, help="Number of GPUs to use for tensor parallelism")
    parser.add_argument("--enforce_eager", action="store_true", help="Set this flag to enable debugging")
    args = parser.parse_args()
    print(f"Running benchmark with model: {args.model_name}, classifier: {args.classifier}, test_run: {args.test_run}, n_loops: {args.n_loops}, verbose: {args.verbose}, combine_system_prompts: {args.combine_system_prompts}, no_think: {args.no_think}, tensor_parallel_size: {args.tensor_parallel_size}, batched: {args.batched}, enforce_eager: {args.enforce_eager}")
    main(args.model_name, args.classifier, args.test_run, args.n_loops, args.verbose, args.combine_system_prompts, args.no_think, args.tensor_parallel_size, args.batched, args.enforce_eager)