variable "REGISTRY" {
  default = "ghcr.io"
}

variable "IMAGE_NAME" {
  default = "webapi"
}

variable "TAG" {
  default = "local"
}

variable "BUILD_CONFIGURATION" {
  default = "Release"
}

variable "PUSH" {
  default = false
}

# Define common labels
variable "VERSION" {
  default = "dev"
}

variable "REVISION" {
  default = ""
}

variable "BUILD_DATE" {
  default = ""
}

# Default target group
group "default" {
  targets = ["webapi"]
}

# Web API target
target "webapi" {
  context    = "."
  dockerfile = "src/Web.Api/Dockerfile"
  
  tags = [
    "${REGISTRY}/${IMAGE_NAME}:${TAG}",
  ]
  
  args = {
    BUILD_CONFIGURATION = "${BUILD_CONFIGURATION}"
  }
  
  labels = {
    "org.opencontainers.image.created"      = "${BUILD_DATE}"
    "org.opencontainers.image.title"        = "Web API"
    "org.opencontainers.image.description"  = "School Account Web API Application"
    "org.opencontainers.image.version"      = "${VERSION}"
    "org.opencontainers.image.revision"     = "${REVISION}"
    "org.opencontainers.image.vendor"       = "School Account"
  }
  
  platforms = ["linux/amd64"]
  
  output = [PUSH == "true" ? "type=registry" : "type=docker"]
  
  cache-from = ["type=gha"]
  cache-to   = ["type=gha,mode=max"]
}

# Development target (no cache, local only)
target "webapi-dev" {
  inherits = ["webapi"]
  
  tags = [
    "${IMAGE_NAME}:dev",
  ]
  
  no-cache = true
  output   = ["type=docker"]
  
  cache-from = []
  cache-to   = []
}

# CI target (with all metadata)
target "webapi-ci" {
  inherits = ["webapi"]
  
  output = ["type=registry,push=true"]
}