FROM python:3.12-alpine

WORKDIR /app
COPY *.py .
COPY static ./static

ENV HOST=0.0.0.0
ENV PORT=3000
EXPOSE 3000

USER nobody
CMD ["python", "-u", "server.py"]
