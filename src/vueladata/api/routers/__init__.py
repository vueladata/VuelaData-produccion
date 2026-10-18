from vueladata.api.routers.causa import router as causas_router
from vueladata.api.routers.regla_compensacion import router as reglas_compensacion_router
from vueladata.api.routers.compensacion import router as compensaciones_router
from vueladata.api.routers.pago import router as pagos_router
from vueladata.api.routers.evento_pago import router as eventos_pago_router

__all__ = [
    "causas_router",
    "reglas_compensacion_router",
    "compensaciones_router",
    "pagos_router",
    "eventos_pago_router",
]
