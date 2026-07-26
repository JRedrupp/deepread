FROM python:3.12-slim

WORKDIR /app

COPY pyproject.toml ./
COPY deepread_worker ./deepread_worker

RUN pip install --no-cache-dir .

# Installs both the chromium binary and its OS-level dependencies, always
# matching whatever playwright version pip just resolved above.
RUN playwright install --with-deps chromium

CMD ["python", "-m", "deepread_worker.main"]
