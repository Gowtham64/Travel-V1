# VoyPlan AI Engineering Sandbox Container
FROM node:20-bookworm-slim

# Install system dependencies, Git, Python3, and Playwright system requirements
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    ca-certificates \
    libnss3 \
    libatk-bridge2.0-0 \
    libgtk-3-0 \
    libx11-xcb1 \
    libasound2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Install python dependencies for orchestrator and agents
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt --break-system-packages

# Security: Non-root user for isolated execution
RUN groupadd -r voyagent && useradd -r -g voyagent -d /workspace -s /bin/bash voyagent
RUN chown -R voyagent:voyagent /workspace

USER voyagent

ENTRYPOINT ["python3", "voyplan-ai-engineering/orchestrator.py"]
CMD ["--help"]
