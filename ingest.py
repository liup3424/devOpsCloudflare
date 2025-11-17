"""
Script to ingest data from data/data.txt and build a FAISS vector store.
"""
import os
from pathlib import Path
from typing import List

from langchain_community.document_loaders import TextLoader
from langchain_community.vectorstores import FAISS
from langchain_openai import OpenAIEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter


def load_documents(data_path: str) -> List:
    """Load documents from the data file."""
    loader = TextLoader(data_path, encoding="utf-8")
    documents = loader.load()
    return documents


def split_documents(documents: List, chunk_size: int = 1000, chunk_overlap: int = 200) -> List:
    """Split documents into smaller chunks."""
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
        length_function=len,
    )
    splits = text_splitter.split_documents(documents)
    return splits


def build_faiss_index(
    data_path: str,
    index_path: str,
    embedding_model: str = "text-embedding-3-small",
) -> None:
    """Build and persist FAISS index from data file."""
    # Load documents
    print(f"Loading documents from {data_path}...")
    documents = load_documents(data_path)
    
    # Split documents
    print("Splitting documents into chunks...")
    splits = split_documents(documents)
    print(f"Created {len(splits)} document chunks")
    
    # Create embeddings and vector store
    print("Creating embeddings and building FAISS index...")
    embeddings = OpenAIEmbeddings(model=embedding_model)
    vectorstore = FAISS.from_documents(splits, embeddings)
    
    # Persist index
    print(f"Saving FAISS index to {index_path}...")
    os.makedirs(index_path, exist_ok=True)
    vectorstore.save_local(index_path)
    print(f"FAISS index saved successfully to {index_path}")


def main() -> None:
    """Main function to run the ingestion process."""
    # Get paths
    project_root = Path(__file__).parent
    data_path = project_root / "data" / "data.txt"
    index_path = project_root / "faiss_index"
    
    # Check if data file exists
    if not data_path.exists():
        raise FileNotFoundError(f"Data file not found: {data_path}")
    
    # Build index
    build_faiss_index(str(data_path), str(index_path))


if __name__ == "__main__":
    main()

