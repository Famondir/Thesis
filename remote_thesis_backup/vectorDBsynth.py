def replace_special_characters(text):
    # Replace German special characters in the input text
    return (
        text.replace("ä", "ae")
        .replace("ö", "oe")
        .replace("ü", "ue")
        .replace("Ä", "Ae")
        .replace("Ö", "Oe")
        .replace("Ü", "Ue")
        .replace("ß", "ss")
    )
import os
import pypdfium2 as pdfium
import pandas as pd

base_dir = "/pvc/benchmark_truth/synthetic_tables/separate_files/final/"
pdf_texts = {}

unit_list = {
    'EUR': 1, 
    '€': 1, 
    'Tsd. EUR': 1000, 
    'Mio. EUR': 1000000, 
    'TEUR': 1000, 
    'T€': 1000, 
    'Tsd. €': 1000, 
    'Mio. €': 1000000
}

for root, dirs, files in os.walk(base_dir):
    for f in files:
        if f.lower().endswith(".html"):
            html_path = os.path.join(root, f)
            with open(html_path, "r", encoding="utf-8") as html_file:
                html_content = html_file.read()
            pdf_texts[html_path] = html_content
pdf_texts
import json

with open("html_texts_synthetic_tables_final.json", "w", encoding="utf-8") as f:
    json.dump(pdf_texts, f, ensure_ascii=False, indent=2)
### classify texts
import json

with open("html_texts_synthetic_tables_final.json", "r", encoding="utf-8") as f:
    pdf_texts = json.load(f)
### embedd texts
import os
from huggingface_hub import login

login(token=os.environ["HUGGING_FACE_HUB_TOKEN"])
# embedding_model_name = "Alibaba-NLP/gte-Qwen2-7B-instruct"
# embedding_model_name = "Linq-AI-Research/Linq-Embed-Mistral"
embedding_model_name = "BAAI/bge-m3"
from sentence_transformers import SentenceTransformer

# model = SentenceTransformer("Alibaba-NLP/gte-Qwen2-7B-instruct", trust_remote_code=True) # needs h200!
# model = SentenceTransformer("Linq-AI-Research/Linq-Embed-Mistral")
model = SentenceTransformer(embedding_model_name)
import re
# page_texts = [re.sub(r'\s+', ' ', re.sub(r'-{3,}', '---', value)) for key, value in pdf_texts.items()]
page_texts = [value for key, value in pdf_texts.items()]
# page_texts
from transformers import AutoTokenizer

tokenizer = AutoTokenizer.from_pretrained("BAAI/bge-m3")
token_lengths = [len(tokenizer(text)['input_ids']) for text in page_texts]

import matplotlib.pyplot as plt

plt.hist(token_lengths, bins=50)
plt.xlabel("Token Length")
plt.ylabel("Number of Pages")
plt.title("Token Length Distribution for BAAI/bge-m3")
plt.show()
embeddings = model.encode(page_texts, show_progress_bar=True) # needs 24 minutes (bge-m3)
import numpy as np

np.save("embeddings_synthetic_tables_final_html.npy", embeddings)
### Create vector DB
import numpy as np

embeddings = np.load("embeddings_synthetic_tables_final_html.npy")
import chromadb
from chromadb.config import Settings
from chromadb.utils import embedding_functions

sentence_transformer_ef = embedding_functions.SentenceTransformerEmbeddingFunction(
    model_name= embedding_model_name
)

# Create or load a ChromaDB collection
client = chromadb.PersistentClient(path="./chroma_db")  # Directory to store the database
collection = client.get_or_create_collection("synthetic_tables_final_html", embedding_function=sentence_transformer_ef)
# client.delete_collection("synthetic_tables_final_html")  # Delete the collection if it exists

# Prepare data for insertion
# page_texts is the list of texts, embeddings is the numpy array of embeddings
ids = ['Aktiva'+str(i) for i, entry in enumerate(pdf_texts)]
# metadatas = [{"filepath": pdf_texts['filepath'], "page": entry['page'], "type": entry['type'], "company": entry['company']} for entry in entries]
metadatas = [{"filepath": key, "type": "Aktiva"} for key, value in pdf_texts.items()]

# collection.add(
#     embeddings=embeddings.tolist(),
#     documents=page_texts,
#     metadatas=metadatas,
#     ids=ids
# )
# Function to split data into batches
def batch_data(data, batch_size):
    for i in range(0, len(data), batch_size):
        yield data[i:i + batch_size]

# Define the batch size
max_batch_size = 5000  # Adjust this to be less than 5461

# Split data into batches
batched_embeddings = list(batch_data(embeddings.tolist(), max_batch_size))
batched_documents = list(batch_data(page_texts, max_batch_size))
batched_metadatas = list(batch_data(metadatas, max_batch_size))
batched_ids = list(batch_data(ids, max_batch_size))

# Add data to the collection in batches
for i in range(len(batched_embeddings)):
    collection.add(
        embeddings=batched_embeddings[i],
        documents=batched_documents[i],
        metadatas=batched_metadatas[i],
        ids=batched_ids[i]
    )
## markdown
def replace_special_characters(text):
    # Replace German special characters in the input text
    return (
        text.replace("ä", "ae")
        .replace("ö", "oe")
        .replace("ü", "ue")
        .replace("Ä", "Ae")
        .replace("Ö", "Oe")
        .replace("Ü", "Ue")
        .replace("ß", "ss")
    )
import os
import pypdfium2 as pdfium
import pandas as pd

base_dir = "/pvc/benchmark_truth/synthetic_tables/separate_files/final/"
pdf_texts = {}

unit_list = {
    'EUR': 1, 
    '€': 1, 
    'Tsd. EUR': 1000, 
    'Mio. EUR': 1000000, 
    'TEUR': 1000, 
    'T€': 1000, 
    'Tsd. €': 1000, 
    'Mio. €': 1000000
}

for root, dirs, files in os.walk(base_dir):
    for f in files:
        if f.lower().endswith(".md"):
            md_path = os.path.join(root, f)
            with open(md_path, "r", encoding="utf-8") as md_file:
                markdown = md_file.read()
            pdf_texts[md_path] = markdown
pdf_texts
import json

with open("markdown_texts_synthetic_tables_final.json", "w", encoding="utf-8") as f:
    json.dump(pdf_texts, f, ensure_ascii=False, indent=2)
### classify texts
import json

with open("markdown_texts_synthetic_tables_final.json", "r", encoding="utf-8") as f:
    pdf_texts = json.load(f)
### embedd texts
import os
from huggingface_hub import login

login(token=os.environ["HUGGING_FACE_HUB_TOKEN"])
# embedding_model_name = "Alibaba-NLP/gte-Qwen2-7B-instruct"
# embedding_model_name = "Linq-AI-Research/Linq-Embed-Mistral"
embedding_model_name = "BAAI/bge-m3"
from sentence_transformers import SentenceTransformer

# model = SentenceTransformer("Alibaba-NLP/gte-Qwen2-7B-instruct", trust_remote_code=True) # needs h200!
# model = SentenceTransformer("Linq-AI-Research/Linq-Embed-Mistral")
# model = SentenceTransformer(embedding_model_name)
import re
# page_texts = [re.sub(r'\s+', ' ', re.sub(r'-{3,}', '---', value)) for key, value in pdf_texts.items()]
page_texts = [value for key, value in pdf_texts.items()]
# page_texts
from transformers import AutoTokenizer

tokenizer = AutoTokenizer.from_pretrained("BAAI/bge-m3")
token_lengths = [len(tokenizer(text)['input_ids']) for text in page_texts]

import matplotlib.pyplot as plt

plt.hist(token_lengths, bins=50)
plt.xlabel("Token Length")
plt.ylabel("Number of Pages")
plt.title("Token Length Distribution for BAAI/bge-m3")
plt.show()
embeddings = model.encode(page_texts, show_progress_bar=True) # needs 5 minutes (bge-m3) with h200
import numpy as np

np.save("embeddings_synthetic_tables_final_markdown.npy", embeddings)
### Create vector DB
import numpy as np

embeddings = np.load("embeddings_synthetic_tables_final_markdown.npy")
import chromadb
from chromadb.config import Settings
from chromadb.utils import embedding_functions

sentence_transformer_ef = embedding_functions.SentenceTransformerEmbeddingFunction(
    model_name= embedding_model_name
)

# Create or load a ChromaDB collection
client = chromadb.PersistentClient(path="./chroma_db")  # Directory to store the database
collection = client.get_or_create_collection("synthetic_tables_final_markdown", embedding_function=sentence_transformer_ef)
# client.delete_collection("synthetic_tables_final_markdown")  # Delete the collection if it exists

# Prepare data for insertion
# page_texts is the list of texts, embeddings is the numpy array of embeddings
ids = ['Aktiva'+str(i) for i, entry in enumerate(pdf_texts)]
# metadatas = [{"filepath": pdf_texts['filepath'], "page": entry['page'], "type": entry['type'], "company": entry['company']} for entry in entries]
metadatas = [{"filepath": key, "type": "Aktiva"} for key, value in pdf_texts.items()]

# collection.add(
#     embeddings=embeddings.tolist(),
#     documents=page_texts,
#     metadatas=metadatas,
#     ids=ids
# )
# Function to split data into batches
def batch_data(data, batch_size):
    for i in range(0, len(data), batch_size):
        yield data[i:i + batch_size]

# Define the batch size
max_batch_size = 5000  # Adjust this to be less than 5461

# Split data into batches
batched_embeddings = list(batch_data(embeddings.tolist(), max_batch_size))
batched_documents = list(batch_data(page_texts, max_batch_size))
batched_metadatas = list(batch_data(metadatas, max_batch_size))
batched_ids = list(batch_data(ids, max_batch_size))

# Add data to the collection in batches
for i in range(len(batched_embeddings)):
    collection.add(
        embeddings=batched_embeddings[i],
        documents=batched_documents[i],
        metadatas=batched_metadatas[i],
        ids=batched_ids[i]
    )
## texts from pdf
import os
import pypdfium2 as pdfium

base_dir = "/pvc/benchmark_truth/synthetic_tables/separate_files/final/"
pdf_texts = {}

for root, dirs, files in os.walk(base_dir):
    for f in files:
        if f.lower().endswith(".pdf"):
            pdf_path = os.path.join(root, f)
            pdf = pdfium.PdfDocument(pdf_path)
            pages_text = []
            for i in range(len(pdf)):
                page = pdf[i]
                text = page.get_textpage().get_text_range()
                pages_text.append(text)
            pdf_texts[pdf_path] = pages_text
pdf_texts
import json

with open("pdf_texts_synthetic_tables_final.json", "w", encoding="utf-8") as f:
    json.dump(pdf_texts, f, ensure_ascii=False, indent=2)
### classify texts
import json

with open("pdf_texts_synthetic_tables_final.json", "r", encoding="utf-8") as f:
    pdf_texts = json.load(f)
### embedd texts
import os
from huggingface_hub import login

login(token=os.environ["HUGGING_FACE_HUB_TOKEN"])
# embedding_model_name = "Alibaba-NLP/gte-Qwen2-7B-instruct"
# embedding_model_name = "Linq-AI-Research/Linq-Embed-Mistral"
embedding_model_name = "BAAI/bge-m3"
from sentence_transformers import SentenceTransformer

# model = SentenceTransformer("Alibaba-NLP/gte-Qwen2-7B-instruct", trust_remote_code=True) # needs h200!
# model = SentenceTransformer("Linq-AI-Research/Linq-Embed-Mistral")
# model = SentenceTransformer(embedding_model_name)
page_texts = [value[0] for key, value in pdf_texts.items()]
from transformers import AutoTokenizer

tokenizer = AutoTokenizer.from_pretrained("BAAI/bge-m3")
token_lengths = [len(tokenizer(text)['input_ids']) for text in page_texts]

import matplotlib.pyplot as plt

plt.hist(token_lengths, bins=50)
plt.xlabel("Token Length")
plt.ylabel("Number of Pages")
plt.title("Token Length Distribution for BAAI/bge-m3")
plt.show()
embeddings = model.encode(page_texts, show_progress_bar=True) # needs 5 minutes (bge-m3)
import numpy as np

np.save("embeddings_synthetic_tables_final.npy", embeddings)
### Create vector DB
import numpy as np

embeddings = np.load("embeddings_synthetic_tables_final.npy")
import chromadb
from chromadb.config import Settings
from chromadb.utils import embedding_functions

sentence_transformer_ef = embedding_functions.SentenceTransformerEmbeddingFunction(
    model_name= embedding_model_name
)

# Create or load a ChromaDB collection
client = chromadb.PersistentClient(path="./chroma_db")  # Directory to store the database
collection = client.get_or_create_collection("synthetic_tables_final", embedding_function=sentence_transformer_ef)
# client.delete_collection("synthetic_tables_final")  # Delete the collection if it exists

# Prepare data for insertion
# page_texts is the list of texts, embeddings is the numpy array of embeddings
ids = ['Aktiva'+str(i) for i, entry in enumerate(pdf_texts)]
# metadatas = [{"filepath": pdf_texts['filepath'], "page": entry['page'], "type": entry['type'], "company": entry['company']} for entry in entries]
metadatas = [{"filepath": key, "type": "Aktiva"} for key, value in pdf_texts.items()]

# collection.add(
#     embeddings=embeddings.tolist(),
#     documents=page_texts,
#     metadatas=metadatas,
#     ids=ids
# )
# Function to split data into batches
def batch_data(data, batch_size):
    for i in range(0, len(data), batch_size):
        yield data[i:i + batch_size]

# Define the batch size
max_batch_size = 5000  # Adjust this to be less than 5461

# Split data into batches
batched_embeddings = list(batch_data(embeddings.tolist(), max_batch_size))
batched_documents = list(batch_data(page_texts, max_batch_size))
batched_metadatas = list(batch_data(metadatas, max_batch_size))
batched_ids = list(batch_data(ids, max_batch_size))

# Add data to the collection in batches
for i in range(len(batched_embeddings)):
    collection.add(
        embeddings=batched_embeddings[i],
        documents=batched_documents[i],
        metadatas=batched_metadatas[i],
        ids=batched_ids[i]
    )