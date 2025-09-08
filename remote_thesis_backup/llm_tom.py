from rewards import answer_reward_func
from rewards_verl import batched_compute_score_multiple_think_traces_and_length
from transformers import AutoTokenizer, AutoModelForCausalLM, default_data_collator
from argparse import ArgumentParser
import pandas as pd
from datasets import Dataset
from torch.utils.data import DataLoader
import torch
import logging
import numpy as np
import wandb
from pathlib import Path
from tqdm import tqdm
import os
########################
# Setup logging
########################
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
handler = logging.StreamHandler()
handler.setFormatter(
    logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
)
logger.addHandler(handler)


def collate_fn(example):
    prompts = [tokenizer.apply_chat_template(x["prompt"], tokenize=False, continue_final_message=True) for x in example]
    targets = [x["reward_model"]["ground_truth"] for x in example]
    tokenized = tokenizer(
    prompts,
    padding="max_length",         # or "longest" for dynamic batching
    truncation=True,
    max_length=2048,
    return_tensors="pt"            # adjust for your model
    )
    return {"input_ids":tokenized["input_ids"], "attention_mask":tokenized["attention_mask"], "targets":targets}

def generate_r1_prompt(note, target):
        r1_prefix = [{
            "role": "system",
            "content": "You are a helpful assistant. You first thinks about the reasoning process in the mind and then provides the user with the answer."
        },
            {
                "role": "user",
                "content": f"Using the following admission note {note}, create a list of probable diagnoses either in form of ICD codes or short descriptions that would fit the patient description. Show your work in <think> </think> tags. Return the final list of possible diagnoses in <diagnosis> </diagnosis> tags, for example <diagnosis> Measles </diagnosis>. Think step by step inside <think> tags."
            },
            {
                "role": "assistant",
                "content": "Let me solve this step by step.\n<think>"
            }]
        return {"prompt": tokenizer.apply_chat_template(r1_prefix, tokenize=False, continue_final_message=True), "target": target, "note": note}

if __name__ == "__main__":
    parser = ArgumentParser()
    parser.add_argument("--model_name", type=str, default="DATEXIS/Clinical-R1-Zero-3B")
    parser.add_argument("--tokenizer_name", type=str, default="Qwen/Qwen2.5-3B-Instruct")
    parser.add_argument("--test_data_path", type=str, default="/pvc/workspace/Clinical-R1-Zero/data/test.parquet")
    parser.add_argument("--output_path", type=str, default="/pvc/experiments")
    parser.add_argument("--hf_token_dir", type=str, default="/etc/hf-read-token/hf-read-token")
    parser.add_argument("--wandb_api_key_dir", type=str, default="/etc/wandb-api-key/api-key")
    parser.add_argument("--hf_cache", type=str, default="/pvc/hf_cache")
    parser.add_argument("--wandb_project", type=str, default="clinical-r1-zero-evaluation")
    parser.add_argument("--batch_size", type=int, default=2)

    args = parser.parse_args()
    if args.hf_token_dir != "":
        with open(args.hf_token_dir, 'r') as f:
            hf_token = f.read().strip()

    if args.wandb_api_key_dir != "" and "WANDB_API_KEY" not in os.environ:
        with open(args.wandb_api_key_dir, 'r') as f:
            os.environ["WANDB_API_KEY"] = f.read().strip()

    Path(args.output_path).mkdir(parents=True, exist_ok=True)
    experiment_name = args.model_name.split("/")[1].lower()
    
    logger.info(f"Initialie WANDB logging\nProject: {args.wandb_project}\nExperiment Name: {experiment_name}")
    wandb.init(project=args.wandb_project, entity="datexis-phd", name=experiment_name)
    logger.info(f"Load data from: {args.test_data_path}")
    dataset = pd.read_parquet(args.test_data_path)
    test_dataset = Dataset.from_pandas(dataset)
    test_dataset = test_dataset.select_columns(["prompt", "TEXT", "reward_model"])
    test_dataset = test_dataset.select(range(2))

    
    logger.info(f"Load tokenizer: {args.tokenizer_name}")
    tokenizer = AutoTokenizer.from_pretrained(
        (
            args.tokenizer_name
            if args.tokenizer_name
            else args.model_name
        ),
        remote_code=True,
        cache_dir=args.hf_cache
    )
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
    tokenizer.padding_side = "left"

    

    logger.info(f"Tokenizing data and initializing dataloader")
    dataloader = DataLoader(test_dataset, batch_size=args.batch_size, shuffle=True, collate_fn=collate_fn)

    logger.info(f"Load model: {args.model_name}")
    model = AutoModelForCausalLM.from_pretrained(args.model_name, 
                                                 token="hf_"+hf_token, 
                                                 cache_dir=args.hf_cache,
                                                 device_map="auto")
    model.eval()
    logger.info("Start evaluation")
    outputs = {"completions":[], "targets":[]}
    with torch.no_grad():
         for batch in tqdm(dataloader):
            input_ids = batch["input_ids"].to("cuda")
            attention_mask = batch["attention_mask"].to("cuda")

            completions = model.generate(input_ids=input_ids, attention_mask=attention_mask, temperature=0.9, max_new_tokens=1024, do_sample=True)
            outputs["completions"].append(tokenizer.batch_decode(completions))
            for targets_ in batch["targets"]:
                outputs["targets"].append(np.array(targets_))
    logger.info("Generations done")

    logger.info("Calculating rewards")
    outputs["completions"] = [x.replace(tokenizer.pad_token, "") for xs in outputs["completions"] for x in xs]
    outputs["rewards"] = batched_compute_score_multiple_think_traces_and_length(outputs["completions"], outputs["targets"])
    logger.info("Rewards done")

    output_df = pd.DataFrame.from_dict(outputs)
    wandb.log({"eval_table":output_df[["completions", "rewards"]]})
    wandb.log({"average_reward":output_df["rewards"].mean(),
               "max_reward":output_df["rewards"].max(),
               "max_reward_id":output_df["rewards"].idxmax(),
               "min_reward":output_df["rewards"].min(),
               "min_reward_id":output_df["rewards"].idxmin()})
    final_output_path = f"{args.output_path}/{experiment_name}-test-rewards.json"
    logger.info(f"Saving outputs to {final_output_path}")
    output_df.to_json(final_output_path, index=False)

 