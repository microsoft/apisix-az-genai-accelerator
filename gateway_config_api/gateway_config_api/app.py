from __future__ import annotations

from functools import lru_cache

import uvicorn
from fastapi import Depends, FastAPI, HTTPException, Request, status

from .models import PreferredBackends, UpdateResult
from .service import ConfigUpdateError, update_latency_route_weights
from .settings import Settings


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


def verify_shared_secret(
    request: Request, settings: Settings = Depends(get_settings)
) -> None:
    secret = settings.shared_secret
    if secret is None:
        return
    provided = request.headers.get("x-config-api-secret")
    if provided != secret.get_secret_value():
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")


app = FastAPI(title="APISIX Config API", version="0.1.0")


@app.post(
    "/config/set-preferred-backends",
    response_model=UpdateResult,
    status_code=status.HTTP_200_OK,
)
async def set_preferred_backends(
    payload: PreferredBackends,
    _: None = Depends(verify_shared_secret),
    settings: Settings = Depends(get_settings),
) -> UpdateResult:
    try:
        changed = update_latency_route_weights(
            settings.apisix_conf_path, payload.preferred_backends
        )
    except ConfigUpdateError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    return UpdateResult(updated_instances=changed)


@app.post(
    "/helpers/set-preferred-backends",
    response_model=UpdateResult,
    status_code=status.HTTP_200_OK,
)
async def set_preferred_backends_alias(
    payload: PreferredBackends,
    _: None = Depends(verify_shared_secret),
    settings: Settings = Depends(get_settings),
) -> UpdateResult:
    """
    Alias path matching APIM E2E test toolkit expectations.
    """
    return await set_preferred_backends(payload, _, settings)  # type: ignore[arg-type]


def main() -> None:
    settings = get_settings()
    uvicorn.run(
        "gateway_config_api.app:app",
        host=settings.bind_host,
        port=settings.bind_port,
        reload=False,
        workers=1,
    )


__all__ = ["app", "main"]
