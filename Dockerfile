# syntax=docker/dockerfile:1
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Copy everything first (so build doesn't fail if requirements.txt is absent)
COPY . .

# If requirements.txt exists, install; otherwise skip
RUN if [ -f requirements.txt ]; then \
      pip install --no-cache-dir -r requirements.txt; \
    else \
      echo "No requirements.txt found; skipping pip install"; \
    fi

# Change "bot.py" to your actual entry script if different
CMD ["python", "bot.py"]
