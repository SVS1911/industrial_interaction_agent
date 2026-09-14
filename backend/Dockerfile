# ============================================
# Stage 1 - Build React frontend
# ============================================

FROM node:20-slim AS frontend-builder

WORKDIR /frontend

COPY frontend/package*.json ./

RUN npm install

COPY frontend/ ./

RUN npm run build


# ============================================
# Stage 2 - FastAPI production container
# ============================================

FROM python:3.12-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Install PostgreSQL client utilities
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY backend/requirements.txt ./requirements.txt

RUN pip install --no-cache-dir -r requirements.txt

# Copy backend
COPY backend/app ./app
COPY backend/database ./database
COPY backend/scripts ./scripts

# Copy React production build
COPY --from=frontend-builder /frontend/dist ./frontend_dist

# Render supplies PORT automatically
EXPOSE 8000

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]