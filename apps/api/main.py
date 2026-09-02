from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.database import SessionLocal
from app.logging_config import setup_logging
from app.routers import admin, auth, cart, credits, health, membership, orders, products, seller
from seed import ensure_admin_user, ensure_catalog_seed

_settings = get_settings()
_cors_origins = [o.strip() for o in _settings.cors_origins.split(",") if o.strip()]


@asynccontextmanager
async def lifespan(_: FastAPI):
    setup_logging(_settings)
    db = SessionLocal()
    try:
        ensure_admin_user(db)
        ensure_catalog_seed(db)
        db.commit()
    finally:
        db.close()
    yield


app = FastAPI(
    title="Shopping Mall API",
    description="Shopping mall backend skeleton",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(admin.router)
app.include_router(credits.router)
app.include_router(products.router)
app.include_router(cart.router)
app.include_router(orders.router)
app.include_router(membership.router)
app.include_router(seller.router)


@app.get("/")
def root():
    return {"message": "Shopping Mall API — see /health and /docs"}
