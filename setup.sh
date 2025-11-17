#!/bin/bash
# Setup script to create virtual environment and build FAISS index

set -e

echo "Setting up Python virtual environment..."

# Remove existing venv if it exists to ensure clean setup
if [ -d "ragEnv" ]; then
    echo "Removing existing virtual environment..."
    rm -rf ragEnv
fi

# Create virtual environment with Python 3.11
python3.11 -m venv ragEnv

# Activate virtual environment
source ragEnv/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install dependencies
echo "Installing dependencies..."
pip install -r requirements.txt

# Check for OpenAI API key
if [ -z "$OPENAI_API_KEY" ]; then
    echo "Warning: OPENAI_API_KEY environment variable is not set."
    echo "Please set it before running ingest.py:"
    echo "  export OPENAI_API_KEY='your-api-key'"
    echo ""
fi

# Build FAISS index
echo "Building FAISS index..."
ragEnv/bin/python ingest.py

echo ""
echo "Setup complete! FAISS index has been built in ./faiss_index/"
echo ""
echo "To activate the virtual environment in the future, run:"
echo "  source ragEnv/bin/activate"
