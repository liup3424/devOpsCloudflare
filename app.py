"""
FastAPI application for LangChain RAG Q&A.
"""
import os
from pathlib import Path
from typing import Dict

from fastapi import FastAPI, HTTPException
from langchain_community.vectorstores import FAISS
from langchain_openai import ChatOpenAI, OpenAIEmbeddings
from langchain.chains import RetrievalQA
from langchain.prompts import PromptTemplate
from pydantic import BaseModel


# Initialize FastAPI app
app = FastAPI(title="RAG Q&A API", version="1.0.0")


class ChatRequest(BaseModel):
    """Request model for chat endpoint."""
    question: str


class ChatResponse(BaseModel):
    """Response model for chat endpoint."""
    answer: str


def load_vectorstore() -> FAISS:
    """Load the FAISS vector store from disk."""
    index_path = Path(__file__).parent / "faiss_index"
    
    if not index_path.exists():
        raise FileNotFoundError(
            f"FAISS index not found at {index_path}. "
            "Please run ingest.py first to build the index."
        )
    
    # Load embeddings (must match the model used during ingestion)
    embedding_model = os.getenv("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small")
    embeddings = OpenAIEmbeddings(model=embedding_model)
    
    # Load vector store
    vectorstore = FAISS.load_local(str(index_path), embeddings, allow_dangerous_deserialization=True)
    return vectorstore


def create_qa_chain(vectorstore: FAISS) -> RetrievalQA:
    """Create a RetrievalQA chain."""
    # Create LLM
    llm = ChatOpenAI(
        model_name=os.getenv("OPENAI_MODEL", "gpt-3.5-turbo"),
        temperature=0,
    )
    
    # Create prompt template
    prompt_template = """Use the following pieces of context to answer the question at the end. 
If you don't know the answer, just say that you don't know, don't try to make up an answer.

Context: {context}

Question: {question}

Answer:"""
    
    PROMPT = PromptTemplate(
        template=prompt_template,
        input_variables=["context", "question"]
    )
    
    # Create QA chain
    qa_chain = RetrievalQA.from_chain_type(
        llm=llm,
        chain_type="stuff",
        retriever=vectorstore.as_retriever(search_kwargs={"k": 3}),
        chain_type_kwargs={"prompt": PROMPT},
        return_source_documents=False,
    )
    
    return qa_chain


# Initialize vector store and QA chain at startup
vectorstore: FAISS = None
qa_chain: RetrievalQA = None


@app.on_event("startup")
def startup_event() -> None:
    """Initialize vector store and QA chain on startup."""
    global vectorstore, qa_chain
    try:
        vectorstore = load_vectorstore()
        qa_chain = create_qa_chain(vectorstore)
        print("Vector store and QA chain initialized successfully")
    except Exception as e:
        print(f"Error initializing vector store: {e}")
        raise


@app.get("/")
def root() -> Dict[str, str]:
    """Root endpoint."""
    import os
    is_docker = os.path.exists("/.dockerenv")
    return {
        "message": "RAG Q&A API is running",
        "environment": "Docker" if is_docker else "Local"
    }


@app.get("/health")
def health() -> Dict[str, str]:
    """Health check endpoint."""
    return {"status": "healthy"}


@app.post("/chat", response_model=ChatResponse)
def chat(request: ChatRequest) -> ChatResponse:
    """
    Chat endpoint that answers questions using RAG.
    
    Args:
        request: Chat request containing the question
        
    Returns:
        Chat response containing the answer
    """
    if qa_chain is None:
        raise HTTPException(status_code=503, detail="QA chain not initialized")
    
    if not request.question or not request.question.strip():
        raise HTTPException(status_code=400, detail="Question cannot be empty")
    
    try:
        # Get answer from QA chain
        result = qa_chain.invoke({"query": request.question})
        answer = result.get("result", "I couldn't generate an answer.")
        
        # Format answer with prefix
        formatted_answer = f"Helpful Answer: V2 {answer}"
        
        return ChatResponse(answer=formatted_answer)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error processing question: {str(e)}")

