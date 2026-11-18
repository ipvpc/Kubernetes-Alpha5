FROM python:3.12-alpine

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py checks.py config_store.py database.py ./
COPY static ./static

ENV HOST=0.0.0.0
ENV PORT=3000
EXPOSE 3000

USER nobody
CMD ["python", "-u", "server.py"]
