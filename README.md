# Hytale Server Docker

Docker image for the Hytale server application.

## Usage

```bash
docker run -it -d -p "5520:5520/udp" -v hytale-data:/data voidcube/hytale-server

```

## Building

```bash
docker build -t voidcube/hytale-server .
```

### Credits

This project incorporates code from **NATroutter/egg-hytale**  
(https://github.com/NATroutter/egg-hytale), licensed under the MIT License.


## License

MIT