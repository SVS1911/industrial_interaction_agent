from typing import Any
from pydantic import BaseModel, ConfigDict

class ApiItem(BaseModel):
    model_config = ConfigDict(extra="allow")
    data: dict[str, Any]
