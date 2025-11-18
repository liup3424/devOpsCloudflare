#!/usr/bin/env bash
# Setup script to create virtual environment and build FAISS index

set -euo pipefail

VENV_DIR=".venv"

echo "🔧 Setting up Python virtual environment in .venv ..."

# Choose Python binary (prefer python3.11, fall back to python3)
if command -v python3.11 >/dev/null 2>&1; then
  PYTHON_BIN="python3.11"
else
  PYTHON_BIN="python3"
fi

# Create venv if not existing
if [ ! -d "$VENV_DIR" ]; then
  echo "Creating virtual environment with $PYTHON_BIN ..."
  $PYTHON_BIN -m venv "$VENV_DIR"
else
  echo "Virtual environment $VENV_DIR already exists, reusing it."
fi

# Activate virtual environment
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip

# Install dependencies
echo "Installing dependencies from requirements.txt ..."
pip install -r requirements.txt

# Check for OpenAI API key
if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "⚠️  Warning: OPENAI_API_KEY environment variable is not set."
  echo "    Please set it before running ingest.py, e.g.:"
  echo "      export OPENAI_API_KEY='your-api-key'"
  echo ""
fi

# Build FAISS index
echo "📚 Building FAISS index with ingest.py ..."
python ingest.py

echo ""
echo "✅ Setup complete! FAISS index has been built in ./faiss_index/"
echo ""
echo "To activate the virtual environment later, run:"
echo "  source .venv/bin/activate"