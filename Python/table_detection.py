import os
from abc import ABC, abstractmethod
import pandas as pd
from pprint import pprint
import re

MARKDOWN_TABLE_REGEX = r'(?:\|(?:[^\r\n|]*\|)+\r?\n(?:\|[-:]+)+\|(?:\r?\n\|(?:[^\r\n|]*\|)+)+)'
HTML_TABLE_REGEX = r'<table.*?>(([\s*].*(\s*))+)?<\/table>'

class TableExtractor(ABC):
    def __init__(self, pdf_path):
        self.pdf_path = pdf_path
        self.tables_df = pd.DataFrame(columns=["Page Number", "Table Content"])

    @abstractmethod
    def detect_tables(self):
        """
        Abstract method to parse the PDF file page by page and detect tables.
        """
        pass

    @abstractmethod
    def extract_tables(self, page):
        """
        Abstract method to extract table content from a given page.
        """
        pass

    def get_tables(self):
        """
        Returns the DataFrame containing detected tables.
        """
        return self.tables_df

class TableExtractor_PyMuPDF(TableExtractor):
    import fitz  # PyMuPDF

    def detect_tables(self, page):
        """
        Parses the PDF file page by page, detects tables, and stores the results in a DataFrame.
        """        
        tables = page.find_tables()
        print(f"{len(tables.tables)} table(s) on {page}")
        return tables
        

    def extract_tables(self):
        """
        Extracts tables from the detected tables on the page.
        """
        with self.fitz.open(self.pdf_path) as pdf:
            for page_number, page in enumerate(pdf, start=1):
                tabs = self.detect_tables(page)

                for table in tabs.tables:
                    # Process each table and extract its content
                    table_content = table.extract()
                    self.tables_df = pd.concat(
                        [
                            self.tables_df,
                            pd.DataFrame(
                                {"Page Number": [page_number], "Table Content": [table_content]}
                            ),
                        ],
                        ignore_index=True,
                    )
    
class TableExtractor_PyMuPDF4llm(TableExtractor):
    import pymupdf4llm
    
    def detect_tables(self, page):
        """
        Parses the PDF file page by page, detects tables, and stores the results in a DataFrame.
        """
        tables = re.findall(MARKDOWN_TABLE_REGEX, page['text'])
        return tables

    def extract_tables(self):
        """
        Extracts tables from the detected tables on the page.
        """
        extract = self.pymupdf4llm.to_markdown(self.pdf_path, page_chunks=True)
        for page_number, page in enumerate(extract, start=1):
            # Process each page and extract its content
            
            tabs = self.detect_tables(page)

            for table in tabs:
                # Process each table and extract its content
                table_content = table#.extract()
                self.tables_df = pd.concat(
                    [
                        self.tables_df,
                        pd.DataFrame(
                            {"Page Number": [page_number], "Table Content": [table_content]}
                        ),
                    ],
                    ignore_index=True,
                )

class TableExtractor_PdfPlumber(TableExtractor):
    import pdfplumber

    def detect_tables(self, page):
        """
        Parses the PDF file page by page, detects tables, and stores the results in a DataFrame.
        """
        tables = page.extract_tables()
        # Filter out empty tables
        non_empty_tables = [table for table in tables if any(any(cell.strip() for cell in row) for row in table)]
        return non_empty_tables

    def extract_tables(self):
        """
        Extracts tables from the detected tables on the page.
        """
        with self.pdfplumber.open(self.pdf_path) as pdf:
            for page_number, page in enumerate(pdf.pages, start=1):
                tabs = self.detect_tables(page)

                for table in tabs:
                    # Process each table and extract its content
                    table_content = table
                    self.tables_df = pd.concat(
                        [
                            self.tables_df,
                            pd.DataFrame(
                                {"Page Number": [page_number], "Table Content": [table_content]}
                            ),
                        ],
                        ignore_index=True,
                    )

class TableExtractor_Camelot(TableExtractor):
    import camelot

    def detect_tables(self, page):
        """
        Parses the PDF file page by page, detects tables, and stores the results in a DataFrame.
        """
        tables = self.camelot.read_pdf(page)
        return tables

    def extract_tables(self):
        """
        Extracts tables from the detected tables on the page.
        """

        # Open the PDF file in binary mode
        with open(self.pdf_path, "rb") as pdf_file:
            # Iterate through each page of the PDF
            for page_number in range(1, get_page_count(self.pdf_path) + 1):
                # Extract the specific page as a binary stream
                page_stream = extract_page_as_stream(pdf_file, page_number)        

                tabs = self.detect_tables(page_stream)
                for table in tabs:
                    # Process each table and extract its content
                    # page_number = table.parsing_report['page']
                    table_content = table.df.to_string(index=False, header=False)
                    self.tables_df = pd.concat(
                        [
                            self.tables_df,
                            pd.DataFrame(
                                {"Page Number": [page_number], "Table Content": [table_content]}
                            ),
                        ],
                        ignore_index=True,
                    )

class TableExtractor_TabulaPy(TableExtractor):
    import tabula

    def detect_tables(self, page):
        """
        Parses the PDF file page by page, detects tables, and stores the results in a DataFrame.
        """
        tables = self.tabula.read_pdf(page)
        return tables

    def extract_tables(self):
        """
        Extracts tables from the detected tables on the page.
        """
        # Open the PDF file in binary mode
        with open(self.pdf_path, "rb") as pdf_file:
            # Iterate through each page of the PDF
            for page_number in range(1, get_page_count(self.pdf_path) + 1):
                # Extract the specific page as a binary stream
                page_stream = extract_page_as_stream(pdf_file, page_number)        

                tabs = self.detect_tables(page_stream)

                for table in tabs:
                    # Process each table and extract its content
                    table_content = table
                    self.tables_df = pd.concat(
                        [
                            self.tables_df,
                            pd.DataFrame(
                                {"Page Number": [page_number], "Table Content": [table_content]}
                            ),
                        ],
                        ignore_index=True,
                    )

class TableExtractor_Azure(TableExtractor):
    from azure.core.credentials import AzureKeyCredential
    from azure.ai.documentintelligence import DocumentIntelligenceClient
    
    def __init__(self, pdf_path):
        self.pdf_path = pdf_path
        self.tables_df = pd.DataFrame(columns=["Page Number", "Table Content"])

        # Set `<your-endpoint>` and `<your-key>` variables with the values from the Azure portal
        self.endpoint = os.getenv("DOC_ANALYZER_ENDPOINT")
        self.key = os.getenv("DOC_ANALYZER_API_KEY")

        # Initialize the Document Intelligence client
        self.document_intelligence_client = self.DocumentIntelligenceClient(
            endpoint=self.endpoint, credential = self.AzureKeyCredential(self.key)
        )

    def detect_tables(self, page):
        """
        Placeholder for Azure Form Recognizer table detection on a single page.
        """
        # Start the analysis process for the current page
        poller = self.document_intelligence_client.begin_analyze_document(
            model_id="prebuilt-layout", body=page,
            output_content_format="markdown"
        )
        result = poller.result()
        tables = re.findall(HTML_TABLE_REGEX, result.content)
        return tables

    def extract_tables(self):
        """
        Extracts tables from each page of the PDF using Azure Form Recognizer.
        """

        # Open the PDF file in binary mode
        with open(self.pdf_path, "rb") as pdf_file:
            # Iterate through each page of the PDF
            for page_number in range(1, get_page_count(self.pdf_path) + 1):
                # Extract the specific page as a binary stream
                page_stream = extract_page_as_stream(pdf_file, page_number)

                tabs = self.detect_tables(page_stream)

                # Process the tables from the result
                for table in tabs:
                    self.tables_df = pd.concat(
                        [
                            self.tables_df,
                            pd.DataFrame(
                                {"Page Number": [page_number], "Table Content": [table]}
                            ),
                        ],
                        ignore_index=True,
                    )

class TableExtractor_Docling(TableExtractor):
    from docling.datamodel.base_models import DocumentStream
    from docling.datamodel.base_models import InputFormat
    from docling.document_converter import DocumentConverter, PdfFormatOption
    from docling.datamodel.pipeline_options import PdfPipelineOptions, TableFormerMode

    def __init__(self, pdf_path, mode = 'FAST'):
        self.pdf_path = pdf_path
        self.tables_df = pd.DataFrame(columns=["Page Number", "Table Content"])

        self.pipeline_options = self.PdfPipelineOptions(do_table_structure=True)
        if mode == 'FAST':
            self.pipeline_options.table_structure_options.mode = self.TableFormerMode.FAST
        elif mode == 'ACCURATE':
            self.pipeline_options.table_structure_options.mode = self.TableFormerMode.ACCURATE


    def detect_tables(self, page):
        """
        Placeholder for Azure Form Recognizer table detection on a single page.
        """

        buf = page # BytesIO(your_binary_stream)
        source = self.DocumentStream(name=self.pdf_path.split("/")[-1], stream=buf)

        converter = self.DocumentConverter(
            format_options={
                self.InputFormat.PDF: self.PdfFormatOption(pipeline_options=self.pipeline_options)
            }
        )

        result = converter.convert(source)
        return [table.export_to_dataframe() for table in result.document.tables]

    def extract_tables(self):
        """
        Extracts tables from each page of the PDF using Azure Form Recognizer.
        """
        
        # Open the PDF file in binary mode
        with open(self.pdf_path, "rb") as pdf_file:
            # Iterate through each page of the PDF
            for page_number in range(1, get_page_count(self.pdf_path) + 1):
                # Extract the specific page as a binary stream
                page_stream = extract_page_as_stream(pdf_file, page_number)

                tabs = self.detect_tables(page_stream)

                # Process the tables from the result
                for table in tabs:
                    self.tables_df = pd.concat(
                        [
                            self.tables_df,
                            pd.DataFrame(
                                {"Page Number": [page_number], "Table Content": [table]}
                            ),
                        ],
                        ignore_index=True,
                    )

from marker.converters.table import TableConverter
from marker.models import create_model_dict
from marker.output import text_from_rendered
from marker.config.parser import ConfigParser

class TableExtractor_Marker(TableExtractor):

    def detect_tables(self, page):
        tables = re.findall(MARKDOWN_TABLE_REGEX, page)
        return tables

    def extract_tables(self):
        config = {
                "paginate_output": True
                }
        config_parser = ConfigParser(config)

        converter = TableConverter(
            config=config_parser.generate_config_dict(),
            artifact_dict=create_model_dict(),
        )
        rendered = converter(self.pdf_path)
        text, _, images = text_from_rendered(rendered)
        pages = re.split(r'\{\d+\}-*\n+', text)
        for page_number, page in enumerate(pages[1:], start=1):
            tabs = self.detect_tables(page)

            # Process the tables from the result
            for table in tabs:
                self.tables_df = pd.concat(
                    [
                        self.tables_df,
                        pd.DataFrame(
                            {"Page Number": [page_number], "Table Content": [table]}
                        ),
                    ],
                    ignore_index=True,
                )

def get_page_count(pdf_path):
    """
    Returns the total number of pages in the PDF.
    """
    from pypdf import PdfReader
    reader = PdfReader(pdf_path)
    return len(reader.pages)

def extract_page_as_stream(pdf_file, page_number):
    """
    Extracts a specific page from the PDF as a binary stream.
    """
    from pypdf import PdfReader, PdfWriter
    reader = PdfReader(pdf_file)
    writer = PdfWriter()
    writer.add_page(reader.pages[page_number - 1])

    # Write the single page to a binary stream
    from io import BytesIO
    page_stream = BytesIO()
    writer.write(page_stream)
    page_stream.seek(0)
    return page_stream

def benchmark(class_name, pdf_path):
    """
    Benchmark the table extraction process.
    """
    print(f"Benchmarking {class_name.__name__} on {pdf_path}")
    extractor = class_name(pdf_path)
    extractor.extract_tables()
    tables = extractor.get_tables()
    print(tables)
    print('\n')
    return tables

# Example usage:
if __name__ == "__main__":
    easy_table = "benchmark_tables/easy_table_german_finance_v2.pdf"
    real_table = "tmp/pdf_split/page.pdf"

    
    benchmark(TableExtractor_PyMuPDF, easy_table)
    benchmark(TableExtractor_PyMuPDF, real_table)
    """
    benchmark(TableExtractor_PyMuPDF4llm, easy_table)
    benchmark(TableExtractor_PyMuPDF4llm, real_table)
    
    benchmark(TableExtractor_PdfPlumber, easy_table)
    benchmark(TableExtractor_PdfPlumber, real_table)
    
    benchmark(TableExtractor_Camelot, easy_table)
    benchmark(TableExtractor_Camelot, real_table)
    
    benchmark(TableExtractor_TabulaPy, easy_table)
    tabs = benchmark(TableExtractor_TabulaPy, real_table)
    print(tabs.loc[0, "Table Content"])
    print(tabs.loc[1, "Table Content"])
    
    benchmark(TableExtractor_Azure, easy_table)
    benchmark(TableExtractor_Azure, real_table)
    
    benchmark(TableExtractor_Docling, easy_table)
    benchmark(TableExtractor_Docling, real_table)
    
    benchmark(TableExtractor_Marker, easy_table)
    benchmark(TableExtractor_Marker, real_table)
    """