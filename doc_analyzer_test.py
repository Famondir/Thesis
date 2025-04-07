#%%

from IPython.display import Markdown

temp_pdf_path = "tmp/pdf_split/page.pdf"

#%% Extract a single page with a table for testing

from pypdf import PdfWriter, PdfReader

writer = PdfWriter()
writer.append("Geschaeftsberichte/degewo AG/240618-degewo-konzernlagerbericht-konzernabschluss-2023.pdf", (7, 8)) # extracts page 8
writer.write(temp_pdf_path)
writer.close()

reader = PdfReader(temp_pdf_path)
page = reader.pages[0]
print(page.extract_text())

#%% Test pdf extraction with Azure

# import libraries
import os
from azure.core.credentials import AzureKeyCredential
from azure.ai.documentintelligence import DocumentIntelligenceClient

# set `<your-endpoint>` and `<your-key>` variables with the values from the Azure portal
endpoint = os.getenv("DOC_ANALYZER_ENDPOINT")
key = os.getenv("DOC_ANALYZER_API_KEY")

# Analyze the local PDF file
def analyze_local_pdf(file_path):
    # Initialize the Document Intelligence client
    document_intelligence_client = DocumentIntelligenceClient(
        endpoint=endpoint, credential=AzureKeyCredential(key)
    )

    # Open the PDF file in binary mode
    with open(file_path, "rb") as pdf_file:
        # Start the analysis process
        poller = document_intelligence_client.begin_analyze_document(
            model_id="prebuilt-layout", body=pdf_file,
            output_content_format="markdown"
        )
        return(poller.result())

# Call the function with the local PDF file path
result = analyze_local_pdf(temp_pdf_path)

# %% Print result as text

def print_analysis_result(result):
    # Process and print the analysis results
    """ for page in result.pages:
        print(f"----Analyzing layout from page #{page.page_number}----")
        print(
            f"Page has width: {page.width} and height: {page.height}, measured with unit: {page.unit}"
        )

        if page.lines:
            for line_idx, line in enumerate(page.lines):
                print(
                    f"...Line # {line_idx} has text '{line.content}' "
                    f"within bounding polygon '{line.polygon}'"
                )

        if page.selection_marks:
            for selection_mark in page.selection_marks:
                print(
                    f"Selection mark is '{selection_mark.state}' within bounding polygon "
                    f"{selection_mark.confidence}"
                ) """

    if result.tables:
        for table_idx, table in enumerate(result.tables):
            print(
                f"Table # {table_idx} has {table.row_count} rows and "
                f"{table.column_count} columns"
            )
            for cell in table.cells:
                print(
                    f"...Cell[{cell.row_index}][{cell.column_index}] has text '{cell.content}'"
                )

print_analysis_result(result)

# %% Present result as Markdown

Markdown(result.content)

# %%

print(result.content)

# %% Fehler mit 'init_empty_weights'

from marker.converters.pdf import PdfConverter
from marker.models import create_model_dict
from marker.output import text_from_rendered

converter = PdfConverter(
    artifact_dict=create_model_dict(),
)
rendered = converter(temp_pdf_path)
text, _, images = text_from_rendered(rendered)

#%%
Markdown(text)

# %%

import pymupdf4llm

md_text = pymupdf4llm.to_markdown(temp_pdf_path)
Markdown(md_text)

# %% Docling

from docling.document_converter import DocumentConverter

converter = DocumentConverter()
result = converter.convert(temp_pdf_path)
Markdown(result.document.export_to_markdown())

# %%

from markitdown import MarkItDown

md = MarkItDown(enable_plugins=False) # Set to True to enable plugins
result = md.convert(temp_pdf_path)
print(result.text_content)

# %% Nougat

