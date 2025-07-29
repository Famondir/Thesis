# -*- coding: utf-8 -*-
"""
Created on Fri Mar 28 13:59:56 2025

@author: FBerbig
@editor: SSchafer
"""

#%% Check Azure environment variable
import os
print(os.environ)

#%% Test azure LLM
from openai import AzureOpenAI
import time

start = time.time()
print("Start")


client = AzureOpenAI(
  azure_endpoint =os.getenv("AZURE_OPENAI_ENDPOINT") ,
  api_key = os.getenv("OPENAI_API_KEY"),  
  api_version=os.getenv("OPENAI_API_VERSION")
)

response = client.chat.completions.create(
    model="gpt-4.1-nano", # model = "deployment_name".
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Does Azure OpenAI support customer managed keys?"},
        {"role": "assistant", "content": "Yes, customer managed keys are supported by Azure OpenAI."},
        {"role": "user", "content": "Do other Azure AI services support this too?"}
    ]
)

print(response.choices[0].message.content)
end = time.time()
print(end - start)

#%% Test Azure embedding
import os
from openai import AzureOpenAI
import time

start = time.time()
print("Start")

client = AzureOpenAI(
  api_key = os.getenv("OPENAI_API_KEY"),  
  api_version=os.getenv("OPENAI_API_VERSION"),
  azure_endpoint =os.getenv("AZURE_OPENAI_ENDPOINT") 
)

response = client.embeddings.create(
    input = "Your text string goes here",
    model= "text-embedding-3-small"
)

print(response.model_dump_json(indent=2))
end = time.time()
print(end - start)
