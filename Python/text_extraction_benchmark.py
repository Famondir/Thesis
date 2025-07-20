import os
from pypdf import PdfReader
import fitz
import pandas as pd
from abc import ABC, abstractmethod
import time
from pdfminer.high_level import extract_text
from pdfminer.pdfpage import PDFPage
import pypdfium2 as pdfium
from docling_parse.pdf_parser import DoclingPdfParser, PdfDocument
from docling_core.types.doc.page import TextCellUnit
from pdfplumber import open as pdfplumber_open
import sys
import io

class TextExtractor(ABC):
    def __init__(self, base_dir, verbose=False):
        self.base_dir = base_dir
        self.verbose = verbose
        self.runtime = 0
        
    def walk_dir(self):
        start_time = time.time()
        counter = 0

        for root, _, files in os.walk(self.base_dir):
            total_files = sum(len(files) for _, _, files in os.walk(self.base_dir))
            for file in files:
                counter+=1
                print(f'{counter}/{total_files}', end="\r")
                if file.endswith(".pdf"):
                    filepath = os.path.join(root, file)
                    if self.verbose:
                        print(filepath)
                    
                    try:
                        self.extract_text(filepath)
                    except Exception as e:
                        print(f"Error reading {filepath}: {e}")

        end_time = time.time()
        self.runtime = end_time - start_time
        print(f"\nTotal runtime: {self.runtime:.2f} seconds")
    
    @abstractmethod
    def extract_text(self, filepath):
        pass

class PageTextExtractor(TextExtractor):
    def __init__(self, base_dir, verbose=False, ocr=False, pdfbackend='pdfium'):
        super().__init__(base_dir, verbose)
        self.ocr = ocr
        self.pdfbackend = pdfbackend

    def extract_text(self, filepath):
        if self.pdfbackend == 'pypdf':
            reader = PdfReader(filepath)
            for page_num, page in enumerate(reader.pages):
                text = page.extract_text()

        elif self.pdfbackend == 'pymupdf':
            doc = fitz.open(filepath)
            for page_num, page in enumerate(doc):
                text = page.get_text()

        elif self.pdfbackend == 'pdfminer':
            with open(filepath, 'rb') as file:
                stderr = sys.stderr
                sys.stderr = io.StringIO()  # Redirect stderr to suppress pdfminer prints
                try:
                    for page_num, page in enumerate(PDFPage.get_pages(file)):
                        text = extract_text(file, page_numbers=[page_num])
                finally:
                    sys.stderr = stderr  # Restore stderr

        elif self.pdfbackend == 'pdfium':
            pdf = pdfium.PdfDocument(filepath)
            for page_num in range(len(pdf)):
                page = pdf[page_num]
                text = page.get_textpage().get_text_range()

        elif self.pdfbackend == 'docling-parse':
            parser = DoclingPdfParser()
            pdf_doc: PdfDocument = parser.load(
                path_or_stream=filepath
            )

            # PdfDocument.iterate_pages() will automatically populate pages as they are yielded.
            for page_num, pred_page in pdf_doc.iterate_pages():
                text = '\n'.join([line.text for line in pred_page.iterate_cells(unit_type=TextCellUnit.LINE)])

        elif self.pdfbackend == 'pdfplumber':
            with pdfplumber_open(filepath) as pdf:
                for page_num, page in enumerate(pdf.pages):
                    text = page.extract_text()

        else:
            raise ValueError(f"Unknown pdfbackend: {self.pdfbackend}")

def main():
    print("Starting text extraction benchmark...")
    extraction_times = []

    for pdfbackend in ['pdfium', 'pymupdf', 'pypdf', 'pdfplumber', 'pdfminer', 'docling-parse']:
        print(f"Running extraction with backend: {pdfbackend}")
        
        page_extractor = PageTextExtractor(
            base_dir = "/home/simon/Documents/data_science/Thesis/Geschaeftsberichte/",
            verbose = False,
            pdfbackend=pdfbackend
        )

        page_extractor.walk_dir()
        extraction_times.append({ 'pdfbackend': pdfbackend, 'runtime': page_extractor.runtime })

    df = pd.DataFrame(extraction_times)
    df.to_csv('/home/simon/Documents/data_science/Thesis/benchmark_results/text_extraction_benchmark_results.csv', index=False)
    print("Benchmark completed. Results saved to text_extraction_benchmark_results.csv")

if __name__ == "__main__":
   main()