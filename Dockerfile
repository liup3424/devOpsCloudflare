FROM python:3.11-slim

WORKDIR /app

# Flag to indicate the app is running in Docker
ENV RUNNING_IN_DOCKER=1 

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy all application code and data
COPY . .

# Expose port
EXPOSE 8000

# Run FastAPI with Uvicorn
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]

