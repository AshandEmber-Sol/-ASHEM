# Ash & Ember ($ASHEM)

Memecoin en Solana sobre el programa Token-2022 (spl-token-2022), usando solo extensiones nativas: sin Anchor, sin contratos custom.

Supply inicial 1,000,000,000 | Decimales 9 | Extension TransferFeeConfig (1.5% con tope por transaccion) | Piso de circulante 300,000,000.

Transparencia: la extension Transfer Fee NO quema tokens por si sola; solo retiene un porcentaje en cada transferencia. La quema real es un paso explicito de burn ejecutado por un script (harvest de fees, burn, y apagado automatico del fee al llegar al piso de 300M).

Trabajo en progreso. La documentacion completa de comandos, scripts y la GitHub Action se ira agregando en este repositorio.
