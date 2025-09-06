# syntax=docker/dockerfile:1
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Copy entire repo (avoids missing-file errors)
COPY . .

# Install deps only if requirements.txt actually has content
RUN if [ -s requirements.txt ]; then \
      pip install --no-cache-dir -r requirements.txt; \
    else \
      echo "No (or empty) requirements.txt; skipping pip install"; \
    fi

# Update this if your entry file is not bot.py
CMD ["python", "bot.py"]
