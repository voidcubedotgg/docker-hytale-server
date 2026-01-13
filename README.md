# Hytale Server Docker

Docker image for the Hytale server application.

## Usage

```bash
docker run -it -p "5520:5520/udp" -v hytale-data:/data voidcube/hytale-server

```

## Building

```bash
docker build -t voidcube/hytale-server .
```

## License

MIT