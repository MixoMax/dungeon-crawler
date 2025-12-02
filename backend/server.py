from fastapi import FastAPI
from fastapi.websockets import WebSocket
import json
from pydantic import BaseModel
import uvicorn
import sys
import random

app = FastAPI()

