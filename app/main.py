from fastapi import FastAPI
from postal.expand import expand_address
from postal.parser import parse_address

app = FastAPI()


# Sync, not async: parse_address/expand_address are blocking C calls that hold the GIL, so
# running them on the event loop stalls every other request — including the empty-query
# health check. FastAPI runs sync endpoints in a threadpool instead.
@app.get("/parse")
def parse(query: str | None = None):
    if not query:
        return []
    return [{"label": label, "value": value} for value, label in parse_address(query)]


@app.get("/expand")
def expand(query: str | None = None):
    if not query:
        return []
    return expand_address(query)
