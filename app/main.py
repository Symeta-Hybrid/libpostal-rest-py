from fastapi import FastAPI
from postal.expand import expand_address
from postal.parser import parse_address
from typing import Optional

app = FastAPI()


@app.get("/parse")
async def parse(query: Optional[str] = None):
    if not query:
        return []
    return [{"label": label, "value": value} for value, label in parse_address(query)]


@app.get("/expand")
async def expand(query: Optional[str] = None):
    if not query:
        return []
    return expand_address(query)
