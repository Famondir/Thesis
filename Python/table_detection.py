import os
from abc import ABC, abstractmethod
import pandas as pd
from pprint import pprint
import re

MARKDOWN_TABLE_REGEX = r'(?:\|(?:[^\r\n|]*\|)+\r?\n(?:\|[-:]+)+\|(?:\r?\n\|(?:[^\r\n|]*\|)+)+)'

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

class TableExtractor_PypdfTableExtraction(TableExtractor):
    import pypdf_table_extraction

    def detect_tables(self, page):
        """
        Parses the PDF file page by page, detects tables, and stores the results in a DataFrame.
        """
        tables = self.pypdf_table_extraction.read_pdf(page)
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

    def detect_tables(self, page):
        """
        Placeholder for Azure Form Recognizer table detection on a single page.
        """
        # This method can be implemented if specific page-level detection is needed.
        pass

    def extract_tables(self):
        """
        Extracts tables from each page of the PDF using Azure Form Recognizer.
        """
        # Set `<your-endpoint>` and `<your-key>` variables with the values from the Azure portal
        endpoint = os.getenv("DOC_ANALYZER_ENDPOINT")
        key = os.getenv("DOC_ANALYZER_API_KEY")

        # Initialize the Document Intelligence client
        document_intelligence_client = self.DocumentIntelligenceClient(
            endpoint=endpoint, credential = self.AzureKeyCredential(key)
        )

        # Open the PDF file in binary mode
        with open(self.pdf_path, "rb") as pdf_file:
            # Iterate through each page of the PDF
            for page_number in range(1, get_page_count() + 1):
                # Extract the specific page as a binary stream
                page_stream = extract_page_as_stream(pdf_file, page_number)

                # Start the analysis process for the current page
                poller = document_intelligence_client.begin_analyze_document(
                    model_id="prebuilt-layout", body=page_stream,
                    output_content_format="markdown"
                )
                result = poller.result()

                # Process the tables from the result
                for table in result.tables:
                    table_content = format_table_as_markdown(table)
                    self.tables_df = pd.concat(
                        [
                            self.tables_df,
                            pd.DataFrame(
                                {"Page Number": [page_number], "Table Content": [table_content]}
                            ),
                        ],
                        ignore_index=True,
                    )


def format_table_as_markdown(table):
    """
    Formats the table content as Markdown.
    """
    rows = []
    for cell in table.cells:
        rows.append(cell.content)
    return "\n".join(rows)

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
    easy_table = "benchmark_tables/easy_table_german_finance.pdf"
    real_table = "tmp/pdf_split/page.pdf"

    """
    benchmark(TableExtractor_PyMuPDF, easy_table)
    benchmark(TableExtractor_PyMuPDF, real_table)

    benchmark(TableExtractor_PyMuPDF4llm, easy_table)
    benchmark(TableExtractor_PyMuPDF4llm, real_table)
    
    benchmark(TableExtractor_PdfPlumber, easy_table)
    benchmark(TableExtractor_PdfPlumber, real_table)
    
    benchmark(TableExtractor_PypdfTableExtraction, easy_table)
    benchmark(TableExtractor_PypdfTableExtraction, real_table)
    
    benchmark(TableExtractor_TabulaPy, easy_table)
    tabs = benchmark(TableExtractor_TabulaPy, real_table)
    print(tabs.loc[0, "Table Content"])
    print(tabs.loc[1, "Table Content"])
    """
    benchmark(TableExtractor_Azure, easy_table)
    benchmark(TableExtractor_Azure, real_table)
    