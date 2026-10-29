variable "VERSION" {
  default = "1.0"
}

variable "GIT_SHA" {
  default = "local"
}

variable "REGISTRY" {
  default = "localhost:5000"
}

variable "API_CONTEXT" {
  default = "../TP01/starter/shopapi"
}

// Activer explicitement les écritures distantes une fois le registre configuré.
variable "REMOTE_CACHE" {
  default = false
}

function "cache_export" {
  params = [component]
  result = REMOTE_CACHE ? ["type=registry,ref=${REGISTRY}/cache:${component},mode=max"] : []
}

group "default" {
  targets = ["api", "worker"]
}

// Convention de cible abstraite : ne pas invoquer _common directement.
target "_common" {
  labels = {
    "org.opencontainers.image.version"  = VERSION
    "org.opencontainers.image.revision" = GIT_SHA
  }
  platforms = ["linux/amd64", "linux/arm64"]
  cache-from = REMOTE_CACHE ? [
    "type=registry,ref=${REGISTRY}/cache:api",
    "type=registry,ref=${REGISTRY}/cache:worker",
    "type=registry,ref=${REGISTRY}/cache:worker-test"
  ] : []
}

target "api" {
  inherits = ["_common"]
  context = API_CONTEXT
  dockerfile = "Dockerfile"
  target = "production"
  args = {
    APP_VERSION = VERSION
    GIT_SHA     = GIT_SHA
  }
  tags = ["${REGISTRY}/shop-api:${VERSION}"]
  cache-to = cache_export("api")
}

target "worker" {
  inherits = ["_common"]
  context = "./starter/shop-worker"
  dockerfile = "Dockerfile"
  target = "runtime"
  tags = ["${REGISTRY}/shop-worker:${VERSION}"]
  secret = ["id=pipconf,src=./starter/shop-worker/pip.conf"]
  cache-to = cache_export("worker")
}

target "worker-test" {
  inherits = ["worker"]
  target = "test"
  tags = []
  output = ["type=cacheonly"]
  cache-to = cache_export("worker-test")
}
