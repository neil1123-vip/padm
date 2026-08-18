variable "REGISTRY" {
  default = "ghcr.io/neil1123-vip"
}

variable "IMAGE_TAG" {
  default = "dev"
}

variable "GIT_REVISION" {
  default = "unknown"
}

variable "PADM_LOCK_PLATFORM_AMD64" {}
variable "PADM_LOCK_PLATFORM_ARM64" {}
variable "PADM_LOCK_VERSION" {}
variable "PADM_LOCK_SOURCE_URL" {}
variable "PADM_LOCK_ALPINE_BASE" {}
variable "PADM_LOCK_CA_CERTIFICATES_VERSION" {}
variable "PADM_LOCK_GCOMPAT_VERSION" {}
variable "PADM_LOCK_XRAY_VERSION" {}
variable "PADM_LOCK_XRAY_AMD64_ASSET" {}
variable "PADM_LOCK_XRAY_AMD64_SHA256" {}
variable "PADM_LOCK_XRAY_ARM64_ASSET" {}
variable "PADM_LOCK_XRAY_ARM64_SHA256" {}
variable "PADM_LOCK_UNZIP_VERSION" {}
variable "PADM_LOCK_SING_BOX_VERSION" {}
variable "PADM_LOCK_SING_BOX_AMD64_ASSET" {}
variable "PADM_LOCK_SING_BOX_AMD64_SHA256" {}
variable "PADM_LOCK_SING_BOX_ARM64_ASSET" {}
variable "PADM_LOCK_SING_BOX_ARM64_SHA256" {}
variable "PADM_LOCK_NGINX_VERSION" {}
variable "PADM_LOCK_NGINX_PACKAGE_VERSION" {}
variable "PADM_LOCK_ACME_SH_VERSION" {}
variable "PADM_LOCK_ACME_SH_URL" {}
variable "PADM_LOCK_ACME_SH_SHA256" {}
variable "PADM_LOCK_PYTHON3_VERSION" {}
variable "PADM_LOCK_OPENSSL_VERSION" {}
variable "PADM_LOCK_SOCAT_VERSION" {}
variable "PADM_LOCK_BASH_VERSION" {}
variable "PADM_LOCK_IPROUTE2_VERSION" {}
variable "PADM_LOCK_IPTABLES_VERSION" {}
variable "PADM_LOCK_NFTABLES_VERSION" {}
variable "PADM_LOCK_WIREGUARD_TOOLS_VERSION" {}
variable "PADM_LOCK_FAIL2BAN_VERSION" {}

group "default" {
  targets = ["xray", "sing-box", "nginx", "ops", "net"]
}

target "_common" {
  platforms = [PADM_LOCK_PLATFORM_AMD64, PADM_LOCK_PLATFORM_ARM64]
  args = {
    ALPINE_BASE = PADM_LOCK_ALPINE_BASE
    PADM_VERSION = PADM_LOCK_VERSION
    SOURCE_URL   = PADM_LOCK_SOURCE_URL
    VCS_REF      = GIT_REVISION
  }
  labels = {
    "org.opencontainers.image.source"   = PADM_LOCK_SOURCE_URL
    "org.opencontainers.image.version"  = PADM_LOCK_VERSION
    "org.opencontainers.image.revision" = GIT_REVISION
  }
}

target "xray" {
  inherits   = ["_common"]
  context    = "docker/images/xray"
  dockerfile = "Dockerfile"
  tags       = ["${REGISTRY}/padm-xray:${IMAGE_TAG}"]
  args = {
    CA_CERTIFICATES_VERSION = PADM_LOCK_CA_CERTIFICATES_VERSION
    UNZIP_VERSION           = PADM_LOCK_UNZIP_VERSION
    XRAY_VERSION            = PADM_LOCK_XRAY_VERSION
    XRAY_AMD64_ASSET        = PADM_LOCK_XRAY_AMD64_ASSET
    XRAY_AMD64_SHA256       = PADM_LOCK_XRAY_AMD64_SHA256
    XRAY_ARM64_ASSET        = PADM_LOCK_XRAY_ARM64_ASSET
    XRAY_ARM64_SHA256       = PADM_LOCK_XRAY_ARM64_SHA256
  }
}

target "sing-box" {
  inherits   = ["_common"]
  context    = "docker/images/sing-box"
  dockerfile = "Dockerfile"
  tags       = ["${REGISTRY}/padm-sing-box:${IMAGE_TAG}"]
  args = {
    CA_CERTIFICATES_VERSION = PADM_LOCK_CA_CERTIFICATES_VERSION
    GCOMPAT_VERSION         = PADM_LOCK_GCOMPAT_VERSION
    SING_BOX_VERSION        = PADM_LOCK_SING_BOX_VERSION
    SING_BOX_AMD64_ASSET    = PADM_LOCK_SING_BOX_AMD64_ASSET
    SING_BOX_AMD64_SHA256   = PADM_LOCK_SING_BOX_AMD64_SHA256
    SING_BOX_ARM64_ASSET    = PADM_LOCK_SING_BOX_ARM64_ASSET
    SING_BOX_ARM64_SHA256   = PADM_LOCK_SING_BOX_ARM64_SHA256
  }
}

target "nginx" {
  inherits   = ["_common"]
  context    = "docker/images/nginx"
  dockerfile = "Dockerfile"
  tags       = ["${REGISTRY}/padm-nginx:${IMAGE_TAG}"]
  args = {
    CA_CERTIFICATES_VERSION = PADM_LOCK_CA_CERTIFICATES_VERSION
    NGINX_VERSION           = PADM_LOCK_NGINX_VERSION
    NGINX_PACKAGE_VERSION   = PADM_LOCK_NGINX_PACKAGE_VERSION
  }
}

target "ops" {
  inherits   = ["_common"]
  context    = "docker/images/ops"
  dockerfile = "Dockerfile"
  tags       = ["${REGISTRY}/padm-ops:${IMAGE_TAG}"]
  args = {
    ACME_SH_VERSION         = PADM_LOCK_ACME_SH_VERSION
    ACME_SH_URL             = PADM_LOCK_ACME_SH_URL
    ACME_SH_SHA256          = PADM_LOCK_ACME_SH_SHA256
    CA_CERTIFICATES_VERSION = PADM_LOCK_CA_CERTIFICATES_VERSION
    OPENSSL_VERSION         = PADM_LOCK_OPENSSL_VERSION
    PYTHON3_VERSION         = PADM_LOCK_PYTHON3_VERSION
    SOCAT_VERSION           = PADM_LOCK_SOCAT_VERSION
  }
}

target "net" {
  inherits   = ["_common"]
  context    = "docker/images/net"
  dockerfile = "Dockerfile"
  tags       = ["${REGISTRY}/padm-net:${IMAGE_TAG}"]
  args = {
    BASH_VERSION            = PADM_LOCK_BASH_VERSION
    CA_CERTIFICATES_VERSION = PADM_LOCK_CA_CERTIFICATES_VERSION
    FAIL2BAN_VERSION        = PADM_LOCK_FAIL2BAN_VERSION
    IPROUTE2_VERSION        = PADM_LOCK_IPROUTE2_VERSION
    IPTABLES_VERSION        = PADM_LOCK_IPTABLES_VERSION
    NFTABLES_VERSION        = PADM_LOCK_NFTABLES_VERSION
    WIREGUARD_TOOLS_VERSION = PADM_LOCK_WIREGUARD_TOOLS_VERSION
  }
}
