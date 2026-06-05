-- Entry point for the Assets plugin. No global state; the service
-- is bound via DI and instantiated on demand.

return {
	AssetsService = require(script.AssetsService),
}
