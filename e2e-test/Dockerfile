# ==============================================================================
# Playwright E2E Test Runner for CI/CD and Containerized Execution
# ==============================================================================
FROM mcr.microsoft.com/playwright:v1.50.0-noble

WORKDIR /app

# Copy package descriptors
COPY package*.json ./

# Install dependencies (browsers are already bundled in the base image)
RUN npm ci

# Copy test source code and configuration
COPY . .

# Default command: run tests headlessly
CMD ["npm", "test"]
