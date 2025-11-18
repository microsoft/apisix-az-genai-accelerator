from __future__ import annotations

from pydantic import BaseModel, Field


class PreferredBackends(BaseModel):
    preferred_backends: list[str] = Field(
        alias="preferredBackends",
        min_length=1,
        description="Ordered list of backend identifiers (first wins)",
    )


class UpdateResult(BaseModel):
    updated_instances: int = Field(..., description="Number of instances whose weight changed")
