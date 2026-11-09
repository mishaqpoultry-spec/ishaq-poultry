from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import auth, customers, deliveries, payments, purchases, rates, stock, suppliers
from app.core.config import get_settings

settings = get_settings()

app = FastAPI(title=settings.app_name, version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in settings.cors_origins.split(",")],
    allow_methods=["*"],
    allow_headers=["*"],
)

API = "/api/v1"
app.include_router(auth.router, prefix=API)
app.include_router(customers.router, prefix=API)
app.include_router(suppliers.router, prefix=API)
app.include_router(purchases.router, prefix=API)
app.include_router(stock.router, prefix=API)
app.include_router(rates.router, prefix=API)
app.include_router(deliveries.router, prefix=API)
app.include_router(payments.router, prefix=API)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get(f"{API}/company")
def company():
    """Business details shown in the app header and on PDFs."""
    return {
        "name": settings.company_name,
        "phone": settings.company_phone,
        "address": settings.company_address,
    }
