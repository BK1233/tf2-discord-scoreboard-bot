# syntax=docker/dockerfile:1
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Copy the whole repo (so build won't fail if requirements.txt is missing)
COPY . .

# Install deps only if requirements.txt exists
RUN if [ -f requirements.txt ]; then \
      pip install --no-cache-dir -r requirements.txt; \
    else \
      echo "No requirements.txt found; skipping pip install"; \
    fi

# Change "bot.py" if your entry script has a different name
CMD ["python", "bot.py"]
