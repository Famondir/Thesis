# -*- coding: utf-8 -*-
"""
Created on Fri Mar 28 13:59:56 2025

@author: FBerbig
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
    model="gpt-4o-mini", # model = "deployment_name".
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


#%% Llamaindex: embedding
from llama_index.embeddings.azure_openai import AzureOpenAIEmbedding
from llama_index.core.schema import TextNode

embed_model = AzureOpenAIEmbedding(
    model="text-embedding-3-small",
    azure_endpoint = os.getenv("AZURE_OPENAI_ENDPOINT"),
    deployment_name = "text-embedding-3-small",
    api_key = os.getenv("OPENAI_API_KEY"),
    api_version=os.getenv("OPENAI_API_VERSION"),
    
)

nodes = [
    TextNode(
        text="Before college the two main things I worked on, "
        "outside of school, were writing and programming."
    )
]
response = embed_model(nodes=nodes)
print(response[0].embedding)



#%% Llamaindex: llm 
from llama_index.llms.azure_openai import AzureOpenAI
llm = AzureOpenAI(
    model="gpt-4o-mini",
    deployment_name = "gpt-4o-mini",
    azure_endpoint=os.getenv("AZURE_OPENAI_ENDPOINT"),
    api_key=os.getenv("OPENAI_API_KEY"),
    api_version=os.getenv("OPENAI_API_VERSION"),
)
     

response = llm.complete("William Shakespeare is ")
print(response)