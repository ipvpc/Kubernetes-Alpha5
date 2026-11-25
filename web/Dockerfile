FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN python -m pip install --no-cache-dir -r requirements.txt

COPY *.py .
COPY static ./static

ENV HOST=0.0.0.0
ENV PORT=3000
ENV ALPHA5_DATA_DIR=/var/lib/alpha5
RUN install -d -m 0700 -o nobody -g nogroup /var/lib/alpha5
EXPOSE 3000

USER nobody
CMD ["python", "-u", "server.py"]
