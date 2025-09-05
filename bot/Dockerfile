# Use a minimal Python base image
FROM python:3.12-slim

# Do not write .pyc files and flush stdout/stderr immediately
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Create a non-root user to run the bot
RUN useradd -m appuser
WORKDIR /app

# Install system dependencies needed by watchdog (inotify) and healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends gcc curl \
 && rm -rf /var/lib/apt/lists/*

# Install Python dependencies first to leverage Docker cache
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the bot code
COPY bot.py .

# Basic healthcheck: ensure a Discord token is present
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s CMD python -c "import os, sys; sys.exit(0 if os.getenv('DISCORD_TOKEN') else 1)"

# Switch to the non-root user
USER appuser

# Default scoreboard path inside the container (can be overridden via env)
ENV SCOREBOARD_PATH=/data/scoreboard.json

# Run the bot
CMD ["python", "bot.py"]
