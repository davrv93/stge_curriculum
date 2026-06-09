FROM python:3.11-slim-bookworm

WORKDIR /app

ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app
ENV PIP_NO_CACHE_DIR=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1

RUN rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
    && apt-get clean \
    && apt-get update -o Acquire::Retries=5 \
    && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

COPY requirements.txt /app/requirements.txt

RUN python -m pip install --upgrade pip setuptools wheel \
    && pip install --no-cache-dir -r /app/requirements.txt

COPY . /app

EXPOSE 8090

CMD ["uvicorn", "app:api", "--host", "0.0.0.0", "--port", "8090"]
