# hindsight.nix — Hindsight memory engine (standalone container)
{ config, pkgs, ... }:
{
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.hindsight = {
    image = "ghcr.io/vectorize-io/hindsight:latest";
    ports = [ "8888:8888" "9999:9999" ]; # 8888:API, 9999:Control Plane UI
    volumes = [
      "/var/lib/hermes/.hermes/hindsight/pg0:/home/hindsight/.pg0"
      "/var/lib/hermes/.hermes/hindsight/cache:/home/hindsight/.cache"
    ];
    environmentFiles = [ "/var/lib/hermes/.hermes/hindsight/.env" ];
    environment = {
      HINDSIGHT_API_LLM_PROVIDER = "openai";
      HINDSIGHT_API_LLM_BASE_URL = "https://maas-coding-api.cn-huabei-1.xf-yun.com/v2";
      HINDSIGHT_API_LLM_MODEL = "xopglm51";
      HINDSIGHT_API_EMBEDDINGS_PROVIDER = "local";
      HINDSIGHT_API_EMBEDDINGS_LOCAL_MODEL = "all-MiniLM-L6-v2";
      HTTP_PROXY = "http://172.24.32.1:35353";
      HTTPS_PROXY = "http://172.24.32.1:35353";
      NO_PROXY = "localhost,127.0.0.1,::1,.xf-yun.com,10.88.0.0/16";
    };
  };
}