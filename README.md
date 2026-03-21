# Hytale Server Docker

Docker image for the Hytale server application.

## Usage

```bash
docker run -it -d -p "5520:5520/udp" -v ./hytale-data:/data voidcube/hytale-server

```

## Automatic Updates

Automatic updates are disabled by default (`HYTALE_DISABLE_UPDATES=1`). Updates are downloaded on container start when a new version is available. This approach aligns with the game's EULA and maintains Docker best practices for container lifecycle management.

## Building

```bash
docker build -t voidcube/hytale-server .
```

## Docker Compose

```bash
services:
  hytale-server:
    image: voidcube/hytale-server
    container_name: hytale-server
    restart: unless-stopped
    ports:
      - "5520:5520/udp"
    volumes:
      - ./hytale-data:/data
    stdin_open: true
    tty: true
```
Start server

```bash
docker-compose up -d
```

### Credits

This project incorporates code from **NATroutter/egg-hytale**  
(https://github.com/NATroutter/egg-hytale), licensed under the MIT License.


## License

MIT
