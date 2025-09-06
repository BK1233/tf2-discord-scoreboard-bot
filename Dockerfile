# ---- Base image ----
FROM python:3.12-slim

# Faster Python, cleaner logs
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Workdir inside the container
WORKDIR /app

# Install system deps only if you need them (uncomment as required)
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     curl build-essential git && \
#     rm -rf /var/lib/apt/lists/*

# Copy dependency list first to leverage Docker layer caching
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of your bot code
COPY . .

# (Optional) OCI metadata
LABEL org.opencontainers.image.title="tf2-discord-scoreboard-bot" \
      org.opencontainers.image.source="https://github.com/<your-username>/tf2-discord-scoreboard-bot"

# Expose nothing (Discord bots usually don’t need inbound ports)
# EXPOSE 8000

# ---- Runtime ----
# If your main file isn't bot.py, change it here (e.g., "main.py")
CMD ["python", "bot.py"]
